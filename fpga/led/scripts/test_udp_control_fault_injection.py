#!/usr/bin/env python3
"""Black-box DB500 CONTROL fault-injection tests for the current FPGA image."""

from __future__ import annotations

import argparse
import copy
import heapq
import hashlib
import json
import socket
import struct
import time
from collections import Counter, deque
from dataclasses import asdict, dataclass, replace
from datetime import datetime
from pathlib import Path
from typing import Iterable


QUERY = 0x01
SET = 0x02
QUERY_RESPONSE = 0x81
SET_RESPONSE = 0x82
OK = 0x00
ERROR = 0x01
FORMAT = struct.Struct("!BBQHI")
SIGNATURE = 0xDB500001


class TestFailure(RuntimeError):
    """A protocol or test-oracle failure."""


@dataclass(frozen=True)
class Record:
    message_type: int
    status: int
    request_id: int
    address: int
    data: int

    def encode(self) -> bytes:
        return FORMAT.pack(
            self.message_type,
            self.status,
            self.request_id,
            self.address,
            self.data,
        )

    @classmethod
    def decode(cls, payload: bytes) -> "Record":
        if len(payload) != FORMAT.size:
            raise TestFailure(f"response length {len(payload)} != 16")
        return cls(*FORMAT.unpack(payload))


@dataclass
class RegisterModel:
    scratch0: int
    scratch1: int
    write_count: int
    watchdog_count: int


def expected_response(
    request: Record,
    *,
    data: int,
    status: int = OK,
) -> Record:
    return Record(
        request.message_type | 0x80,
        status,
        request.request_id,
        request.address,
        request.data if request.message_type == SET else data,
    )


class EventLog:
    def __init__(
        self,
        output_dir: Path,
        label: str,
        *,
        detailed_packets: bool = True,
    ) -> None:
        output_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.jsonl_path = output_dir / f"control_fault_{stamp}_{label}.jsonl"
        self.text_path = output_dir / f"control_fault_{stamp}_{label}.log"
        self.summary_path = output_dir / f"control_fault_{stamp}_{label}.json"
        self.context_path = output_dir / f"control_fault_{stamp}_{label}_context.json"
        self._jsonl = self.jsonl_path.open("w", encoding="utf-8")
        self._text = self.text_path.open("w", encoding="utf-8")
        self.index = 0
        self.started = time.perf_counter()
        self.detailed_packets = detailed_packets
        self.recent: deque[dict[str, object]] = deque(maxlen=1000)

    def event(self, kind: str, **fields: object) -> None:
        item = {
            "event_index": self.index,
            "monotonic_s": time.perf_counter(),
            "elapsed_s": time.perf_counter() - self.started,
            "kind": kind,
            **fields,
        }
        self.index += 1
        self.recent.append(item)
        noisy = kind in {"tx", "rx", "rx_record", "random_delivery"}
        if kind in {"random_request_action", "random_response_action"}:
            noisy = fields.get("action") == "PASS" and not fields.get("delay_s")
        interesting_tx = kind == "tx" and fields.get("action") != "PASS"
        if self.detailed_packets or not noisy or interesting_tx:
            self._jsonl.write(json.dumps(item, ensure_ascii=False) + "\n")
            self._jsonl.flush()

    def line(self, message: str) -> None:
        line = f"{time.perf_counter() - self.started:12.6f} {message}"
        print(line, flush=True)
        self._text.write(line + "\n")
        self._text.flush()

    def summary(self, value: dict[str, object]) -> None:
        self.summary_path.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def dump_context(self) -> None:
        self.context_path.write_text(
            json.dumps(list(self.recent), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def close(self) -> None:
        self._jsonl.close()
        self._text.close()


class Harness:
    def __init__(
        self,
        host_ip: str,
        fpga_ip: str,
        port: int,
        logger: EventLog,
    ) -> None:
        self.host_endpoint = (host_ip, port)
        self.fpga_endpoint = (fpga_ip, port)
        self.log = logger
        self.sock: socket.socket | None = None

    def open(self) -> None:
        if self.sock is not None:
            return
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(self.host_endpoint)
        self.sock = sock
        self.log.event("socket_open", endpoint=self.host_endpoint)

    def close(self) -> None:
        if self.sock is not None:
            self.sock.close()
            self.sock = None
            self.log.event("socket_close")

    def quiet_reopen(self, seconds: float) -> None:
        self.close()
        self.log.event("quiet_start", duration_s=seconds)
        time.sleep(seconds)
        self.log.event("quiet_end", duration_s=seconds)
        self.open()

    def send_payload(
        self,
        payload: bytes,
        *,
        action: str = "PASS",
        request_id: int | None = None,
    ) -> None:
        if self.sock is None:
            raise TestFailure("socket is closed")
        sent = self.sock.sendto(payload, self.fpga_endpoint)
        self.log.event(
            "tx",
            action=action,
            request_id=request_id,
            length=len(payload),
            sent=sent,
            payload_sha256=hashlib.sha256(payload).hexdigest(),
        )

    def send(self, record: Record, *, action: str = "PASS") -> None:
        self.send_payload(
            record.encode(), action=action, request_id=record.request_id
        )

    def recv(self, timeout: float) -> Record:
        if self.sock is None:
            raise TestFailure("socket is closed")
        self.sock.settimeout(timeout)
        payload, source = self.sock.recvfrom(2048)
        actual_source = (source[0], source[1])
        self.log.event(
            "rx",
            source=actual_source,
            length=len(payload),
            payload_sha256=hashlib.sha256(payload).hexdigest(),
        )
        if actual_source != self.fpga_endpoint:
            raise TestFailure(f"unexpected response endpoint {actual_source}")
        record = Record.decode(payload)
        self.log.event("rx_record", **asdict(record))
        return record

    def expect_silence(self, seconds: float, context: str) -> None:
        deadline = time.perf_counter() + seconds
        while True:
            remaining = deadline - time.perf_counter()
            if remaining <= 0:
                return
            try:
                response = self.recv(remaining)
            except socket.timeout:
                return
            raise TestFailure(f"{context}: unexpected response {response}")

    def drain(self, seconds: float = 0.005) -> list[Record]:
        drained: list[Record] = []
        deadline = time.perf_counter() + seconds
        while True:
            remaining = deadline - time.perf_counter()
            if remaining <= 0:
                return drained
            try:
                drained.append(self.recv(remaining))
            except socket.timeout:
                return drained

    def collect(
        self,
        expected: dict[int, Record],
        *,
        timeout: float = 0.250,
        allow_identical_duplicates: bool = True,
    ) -> dict[int, Record]:
        received: dict[int, Record] = {}
        deadline = time.perf_counter() + timeout
        while len(received) < len(expected):
            remaining = deadline - time.perf_counter()
            if remaining <= 0:
                missing = sorted(set(expected) - set(received))
                raise TestFailure(f"missing responses {missing}")
            try:
                response = self.recv(remaining)
            except socket.timeout as exc:
                missing = sorted(set(expected) - set(received))
                raise TestFailure(f"missing responses {missing}") from exc
            reference = expected.get(response.request_id)
            if reference is None:
                raise TestFailure(f"unexpected response {response}")
            if response != reference:
                raise TestFailure(
                    f"response {response.request_id}: expected {reference}, got {response}"
                )
            if response.request_id in received and not allow_identical_duplicates:
                raise TestFailure(f"unexpected duplicate response {response.request_id}")
            received[response.request_id] = response
        return received

    def one(self, request: Record, expected: Record, timeout: float = 0.250) -> Record:
        self.send(request)
        return self.collect({request.request_id: expected}, timeout=timeout)[
            request.request_id
        ]


def make_query(request_id: int, address: int) -> Record:
    return Record(QUERY, 0, request_id, address, 0)


def make_set(request_id: int, address: int, data: int) -> Record:
    return Record(SET, 0, request_id, address, data & 0xFFFFFFFF)


def verify_query(record: Record, request: Record, data: int) -> None:
    expected = expected_response(request, data=data)
    if record != expected:
        raise TestFailure(f"expected {expected}, got {record}")


def probe_generation_fixed(harness: Harness) -> RegisterModel:
    requests = {
        1: make_query(1, 0x0010),
        2: make_query(2, 0x0000),
        3: make_query(3, 0x0001),
        4: make_query(4, 0x0011),
    }
    for request in requests.values():
        harness.send(request)

    received: dict[int, Record] = {}
    deadline = time.perf_counter() + 0.250
    while len(received) < 4:
        remaining = deadline - time.perf_counter()
        if remaining <= 0:
            raise TestFailure(f"probe missing {sorted(set(requests) - set(received))}")
        response = harness.recv(remaining)
        request = requests.get(response.request_id)
        if request is None:
            raise TestFailure(f"probe unexpected response {response}")
        if (
            response.message_type != QUERY_RESPONSE
            or response.status != OK
            or response.address != request.address
        ):
            raise TestFailure(f"probe malformed response {response}")
        received[response.request_id] = response

    if received[1].data != SIGNATURE:
        raise TestFailure(f"signature 0x{received[1].data:08X} != 0x{SIGNATURE:08X}")

    reset_request = make_query(5, 0x0012)
    harness.send(reset_request)
    reset_response = harness.recv(0.250)
    if (
        reset_response.message_type != QUERY_RESPONSE
        or reset_response.status != OK
        or reset_response.request_id != 5
        or reset_response.address != 0x0012
    ):
        raise TestFailure(f"watchdog probe malformed {reset_response}")

    return RegisterModel(
        scratch0=received[2].data,
        scratch1=received[3].data,
        write_count=received[4].data,
        watchdog_count=reset_response.data,
    )


def verify_recovery_stable(
    harness: Harness,
    watchdog_count: int,
    *,
    first_id: int = 6,
    interval_s: float = 0.050,
) -> int:
    """Prove that the recovered generation stays active after traffic resumes."""
    for request_id in (first_id, first_id + 1):
        request = make_query(request_id, 0x0012)
        expected = expected_response(request, data=watchdog_count)
        harness.send(request)
        response = harness.recv(0.250)
        if response != expected:
            raise TestFailure(
                f"recovery stability probe {request_id}: expected {expected}, "
                f"got {response}"
            )
        if request_id == first_id:
            time.sleep(interval_s)
    return first_id + 1


def dependency_chain(
    harness: Harness,
    model: RegisterModel,
    first_id: int,
    value_a: int,
    value_b: int,
    order: Iterable[int],
) -> None:
    requests = {
        first_id: make_set(first_id, 0x0000, value_a),
        first_id + 1: make_query(first_id + 1, 0x0000),
        first_id + 2: make_set(first_id + 2, 0x0000, value_b),
        first_id + 3: make_query(first_id + 3, 0x0000),
    }
    expected = {
        first_id: expected_response(requests[first_id], data=0),
        first_id + 1: expected_response(requests[first_id + 1], data=value_a),
        first_id + 2: expected_response(requests[first_id + 2], data=0),
        first_id + 3: expected_response(requests[first_id + 3], data=value_b),
    }
    for offset in order:
        harness.send(requests[first_id + offset])
    harness.collect(expected)
    model.scratch0 = value_b & 0xFFFFFFFF
    model.write_count = (model.write_count + 2) & 0xFFFFFFFF


def verify_probe(
    observed: RegisterModel,
    expected: RegisterModel,
    *,
    expected_reset_delta: int,
) -> None:
    if observed.scratch0 != expected.scratch0:
        raise TestFailure(
            f"scratch0 0x{observed.scratch0:08X} != 0x{expected.scratch0:08X}"
        )
    if observed.scratch1 != expected.scratch1:
        raise TestFailure(
            f"scratch1 0x{observed.scratch1:08X} != 0x{expected.scratch1:08X}"
        )
    if observed.write_count != expected.write_count:
        raise TestFailure(
            f"write_count {observed.write_count} != {expected.write_count}"
        )
    expected_reset = (expected.watchdog_count + expected_reset_delta) & 0xFFFFFFFF
    if observed.watchdog_count != expected_reset:
        raise TestFailure(
            f"watchdog_count {observed.watchdog_count} != {expected_reset}"
        )
    expected.watchdog_count = observed.watchdog_count


def run_deterministic(harness: Harness, quiet_s: float) -> dict[str, object]:
    harness.quiet_reopen(quiet_s)
    model = probe_generation_fixed(harness)
    harness.log.line(
        "PASS D00 generation_probe "
        f"scratch0=0x{model.scratch0:08X} scratch1=0x{model.scratch1:08X} "
        f"write_count={model.write_count} watchdog_count={model.watchdog_count}"
    )

    dependency_chain(harness, model, 6, 0xD0100006, 0xD0100008, range(4))
    harness.log.line("PASS D01 no_fault_dependency_chain")

    # D02: request 10 is absent while 11..13 arrive.  No later response may
    # appear until the missing head is supplied.
    first = 10
    req = {
        first: make_set(first, 0x0000, 0xD020000A),
        first + 1: make_query(first + 1, 0x0000),
        first + 2: make_set(first + 2, 0x0000, 0xD020000C),
        first + 3: make_query(first + 3, 0x0000),
    }
    for request_id in (11, 12, 13):
        harness.send(req[request_id])
    harness.expect_silence(0.005, "D02 before missing head")
    harness.send(req[10])
    harness.collect(
        {
            10: expected_response(req[10], data=0),
            11: expected_response(req[11], data=0xD020000A),
            12: expected_response(req[12], data=0),
            13: expected_response(req[13], data=0xD020000C),
        }
    )
    model.scratch0 = 0xD020000C
    model.write_count = (model.write_count + 2) & 0xFFFFFFFF
    harness.log.line("PASS D02 missing_head_blocks_later_execution")

    dependency_chain(harness, model, 14, 0xD030000E, 0xD0300010, (3, 1, 2, 0))
    harness.log.line("PASS D03 reordered_arrival_ordered_execution")

    # D04: repeated SET before/after completion must increment once.
    set18 = make_set(18, 0x0001, 0xD0400012)
    expected18 = expected_response(set18, data=0)
    for _ in range(3):
        harness.send(set18, action="DUPLICATE")
    q19 = make_query(19, 0x0001)
    q20 = make_query(20, 0x0011)
    q21 = make_query(21, 0x0010)
    for request in (q19, q20, q21):
        harness.send(request)
    model.scratch1 = set18.data
    model.write_count = (model.write_count + 1) & 0xFFFFFFFF
    harness.collect(
        {
            18: expected18,
            19: expected_response(q19, data=model.scratch1),
            20: expected_response(q20, data=model.write_count),
            21: expected_response(q21, data=SIGNATURE),
        }
    )
    harness.drain(0.010)
    harness.one(set18, expected18)
    harness.drain(0.005)
    harness.log.line("PASS D04 duplicate_request_executes_once")

    # D05: discard the first response and request the saved SET result.
    set22 = make_set(22, 0x0001, 0xD0500016)
    expected22 = expected_response(set22, data=0)
    harness.send(set22)
    discarded22 = harness.recv(0.250)
    if discarded22 != expected22:
        raise TestFailure(f"D05 first response mismatch {discarded22}")
    model.scratch1 = set22.data
    model.write_count = (model.write_count + 1) & 0xFFFFFFFF
    harness.one(set22, expected22)
    q23 = make_query(23, 0x0011)
    q24 = make_query(24, 0x0001)
    q25 = make_query(25, 0x0010)
    for request in (q23, q24, q25):
        harness.send(request)
    harness.collect(
        {
            23: expected_response(q23, data=model.write_count),
            24: expected_response(q24, data=model.scratch1),
            25: expected_response(q25, data=SIGNATURE),
        }
    )
    harness.log.line("PASS D05 lost_set_response_replayed_without_rewrite")

    # D06: preserve the first QUERY value after a later SET changes storage.
    q26 = make_query(26, 0x0000)
    original_value = model.scratch0
    harness.send(q26)
    discarded26 = harness.recv(0.250)
    verify_query(discarded26, q26, original_value)
    set27 = make_set(27, 0x0000, 0xD060001B)
    harness.one(set27, expected_response(set27, data=0))
    model.scratch0 = set27.data
    model.write_count = (model.write_count + 1) & 0xFFFFFFFF
    harness.one(q26, expected_response(q26, data=original_value))
    q28 = make_query(28, 0x0000)
    q29 = make_query(29, 0x0011)
    for request in (q28, q29):
        harness.send(request)
    harness.collect(
        {
            28: expected_response(q28, data=model.scratch0),
            29: expected_response(q29, data=model.write_count),
        }
    )
    harness.log.line("PASS D06 query_replay_preserves_first_read_value")

    # D07: deliver a four-response set to the host model in reverse order and
    # add an identical duplicate.  H may advance only after all gaps close.
    queries = {
        30: make_query(30, 0x0010),
        31: make_query(31, 0x0000),
        32: make_query(32, 0x0001),
        33: make_query(33, 0x0011),
    }
    expected = {
        30: expected_response(queries[30], data=SIGNATURE),
        31: expected_response(queries[31], data=model.scratch0),
        32: expected_response(queries[32], data=model.scratch1),
        33: expected_response(queries[33], data=model.write_count),
    }
    for request in queries.values():
        harness.send(request)
    responses = harness.collect(expected)
    completed: set[int] = set()
    highest = 29
    for request_id in (33, 32, 31, 31, 30):
        if responses[request_id] != expected[request_id]:
            raise TestFailure("D07 altered response")
        completed.add(request_id)
        while highest + 1 in completed:
            highest += 1
            completed.remove(highest)
    if highest != 33:
        raise TestFailure(f"D07 host cumulative prefix stopped at {highest}")
    harness.log.line("PASS D07 host_merges_reordered_duplicate_responses")

    # D08: request 38 is outside the 34..37 allowance and must be retried.
    outside = make_query(38, 0x0010)
    harness.send(outside)
    harness.expect_silence(0.005, "D08 outside-window request")
    dependency_chain(harness, model, 34, 0xD0800022, 0xD0800024, range(4))
    harness.one(outside, expected_response(outside, data=SIGNATURE))
    q39 = make_query(39, 0x0000)
    q40 = make_query(40, 0x0011)
    q41 = make_query(41, 0x0001)
    for request in (q39, q40, q41):
        harness.send(request)
    harness.collect(
        {
            39: expected_response(q39, data=model.scratch0),
            40: expected_response(q40, data=model.write_count),
            41: expected_response(q41, data=model.scratch1),
        }
    )
    harness.log.line("PASS D08 outside_window_requires_retransmission")

    # D10: malformed UDP payloads must not consume request 42.
    malformed = [
        b"",
        b"\x01",
        bytes(15),
        bytes(17),
        bytes(1473),
        FORMAT.pack(0x7F, 0, 42, 0, 0),
        FORMAT.pack(QUERY, 1, 42, 0, 0),
        FORMAT.pack(QUERY, 0, 0, 0, 0),
        FORMAT.pack(QUERY, 0, 42, 0, 1),
    ]
    for index, payload in enumerate(malformed):
        harness.send_payload(payload, action=f"MALFORMED_{index}")
        harness.expect_silence(0.003, f"D10 malformed {index}")
    dependency_chain(harness, model, 42, 0xD100002A, 0xD100002C, range(4))
    harness.log.line("PASS D10 malformed_payloads_do_not_consume_request_id")

    # D12 request-side burst: the first two logical attempts never reach the
    # socket; the third is the first FPGA-visible copy.
    q46 = make_query(46, 0x0010)
    harness.log.event("inject_drop", direction="request", request_id=46, attempt=0)
    harness.log.event("inject_drop", direction="request", request_id=46, attempt=1)
    harness.one(q46, expected_response(q46, data=SIGNATURE))
    q47 = make_query(47, 0x0000)
    q48 = make_query(48, 0x0001)
    q49 = make_query(49, 0x0011)
    for request in (q47, q48, q49):
        harness.send(request)
    harness.collect(
        {
            47: expected_response(q47, data=model.scratch0),
            48: expected_response(q48, data=model.scratch1),
            49: expected_response(q49, data=model.write_count),
        }
    )

    set50 = make_set(50, 0x0001, 0xD1200032)
    expected50 = expected_response(set50, data=0)
    for attempt in range(2):
        harness.send(set50)
        dropped = harness.recv(0.250)
        if dropped != expected50:
            raise TestFailure(f"D12 dropped response mismatch {dropped}")
        harness.log.event(
            "inject_drop", direction="response", request_id=50, attempt=attempt
        )
    harness.one(set50, expected50)
    model.scratch1 = set50.data
    model.write_count = (model.write_count + 1) & 0xFFFFFFFF
    q51 = make_query(51, 0x0011)
    q52 = make_query(52, 0x0001)
    q53 = make_query(53, 0x0010)
    for request in (q51, q52, q53):
        harness.send(request)
    harness.collect(
        {
            51: expected_response(q51, data=model.write_count),
            52: expected_response(q52, data=model.scratch1),
            53: expected_response(q53, data=SIGNATURE),
        }
    )
    harness.log.line("PASS D12 request_and_response_burst_drop_recovered")

    # D13: all visible responses are dropped by the host model.  The SET still
    # executes once, then total silence permits one watchdog reset.
    set54 = make_set(54, 0x0000, 0xD1300036)
    expected54 = expected_response(set54, data=0)
    for attempt, wait_s in enumerate((0.002, 0.004, 0.008)):
        harness.send(set54)
        dropped = harness.recv(0.250)
        if dropped != expected54:
            raise TestFailure(f"D13 dropped response mismatch {dropped}")
        harness.log.event(
            "inject_drop", direction="response", request_id=54, attempt=attempt
        )
        time.sleep(wait_s)
    model.scratch0 = set54.data
    model.write_count = (model.write_count + 1) & 0xFFFFFFFF
    previous_reset = model.watchdog_count
    harness.quiet_reopen(quiet_s)
    observed = probe_generation_fixed(harness)
    verify_probe(observed, model, expected_reset_delta=1)
    if model.watchdog_count != ((previous_reset + 1) & 0xFFFFFFFF):
        raise TestFailure("D13 watchdog delta mismatch")
    harness.log.line("PASS D13 retry_exhaustion_watchdog_recovery")

    dependency_chain(harness, model, 6, 0xD1800006, 0xD1800008, range(4))
    harness.log.line("PASS D18 post_recovery_ordered_window")

    # D09: same id with different content causes fail-stop; the accepted first
    # SET remains exactly-once and survives communication recovery.
    set10 = make_set(10, 0x0000, 0xD090000A)
    harness.one(set10, expected_response(set10, data=0))
    model.scratch0 = set10.data
    model.write_count = (model.write_count + 1) & 0xFFFFFFFF
    conflict = make_set(10, 0x0000, 0xBAD0000A)
    harness.send(conflict, action="ID_CONFLICT")
    harness.expect_silence(0.010, "D09 conflict")
    blocked11 = make_query(11, 0x0010)
    harness.send(blocked11)
    harness.expect_silence(0.010, "D09 fault hold")
    harness.quiet_reopen(quiet_s)
    observed = probe_generation_fixed(harness)
    verify_probe(observed, model, expected_reset_delta=1)
    harness.log.line("PASS D09 id_conflict_fail_stop_and_recovery")

    # D11 + D14: register ERROR enters fail-stop.  Replaying the completed
    # ERROR every 100 ms keeps the watchdog active; only total silence resets.
    bad6 = make_query(6, 0xFFFF)
    error6 = expected_response(bad6, data=0, status=ERROR)
    harness.one(bad6, error6)
    blocked7 = make_query(7, 0x0010)
    harness.send(blocked7)
    harness.expect_silence(0.010, "D11 request after ERROR")
    keepalive_started = time.perf_counter()
    replies = 0
    while time.perf_counter() - keepalive_started < 0.700:
        harness.one(bad6, error6)
        replies += 1
        time.sleep(0.100)
    if replies < 6:
        raise TestFailure(f"D14 only {replies} replay replies")
    harness.quiet_reopen(quiet_s)
    observed = probe_generation_fixed(harness)
    verify_probe(observed, model, expected_reset_delta=1)
    harness.log.line("PASS D11 register_error_fail_stop")
    harness.log.line("PASS D14 traffic_prevents_watchdog_then_silence_recovers")

    # D15: ordinary healthy inactivity also ends exactly one generation.
    q6 = make_query(6, 0x0010)
    harness.one(q6, expected_response(q6, data=SIGNATURE))
    harness.quiet_reopen(quiet_s)
    observed = probe_generation_fixed(harness)
    verify_probe(observed, model, expected_reset_delta=1)
    harness.log.line("PASS D15 ordinary_idle_generation_reset")

    dependency_chain(harness, model, 6, 0xD1800106, 0xD1800108, range(4))
    harness.log.line("PASS D18 final_post_recovery_health")

    return {
        "result": "PASS",
        "suite": "deterministic_black_box",
        "scratch0": model.scratch0,
        "scratch1": model.scratch1,
        "write_count": model.write_count,
        "watchdog_count": model.watchdog_count,
        "not_covered_current_firmware": ["D16", "D17a", "D17b"],
    }


@dataclass(frozen=True)
class RandomProfile:
    name: str
    min_completions: int
    drop_rate: float
    duplicate_rate: float
    reorder_rate: float
    delay_rate: float
    max_delay_s: float
    min_action_count: int
    burst_every: int


RANDOM_PROFILES = {
    "debug": RandomProfile(
        "debug", 2_000, 0.002, 0.003, 0.003, 0.005, 0.001, 2, 500
    ),
    "r0": RandomProfile(
        "r0", 1_000_000, 0.0001, 0.0002, 0.0002,
        0.0002, 0.001, 100, 0,
    ),
    "r1": RandomProfile(
        "r1", 5_000_000, 0.001, 0.002, 0.002,
        0.005, 0.002, 1_000, 10_000,
    ),
    "r2": RandomProfile(
        "r2", 2_000_000, 0.01, 0.01, 0.01,
        0.02, 0.010, 10_000, 1_000,
    ),
}


@dataclass
class PendingRequest:
    request: Record
    expected: Record
    attempts: int = 0
    next_retry: float = 0.0
    completed: bool = False


def keyed_u64(seed: int, *parts: object) -> int:
    key = "|".join([str(seed), *(str(part) for part in parts)]).encode("utf-8")
    return int.from_bytes(hashlib.sha256(key).digest()[:8], "big")


def keyed_unit(seed: int, *parts: object) -> float:
    return keyed_u64(seed, *parts) / float(1 << 64)


class RandomCampaign:
    RETRY_WAITS = (0.002, 0.004, 0.008)

    def __init__(
        self,
        harness: Harness,
        profile: RandomProfile,
        seed: int,
        quiet_s: float,
    ) -> None:
        self.harness = harness
        self.profile = profile
        self.seed = seed
        self.quiet_s = quiet_s
        self.counts: Counter[str] = Counter()
        self.total_completed = 0
        self.total_created = 0
        self.recovery_count = 0
        self.generation = 0
        self.sequence = 0
        self.request_attempt_index = 0
        self.burst_remaining = 0
        self.next_progress = 0.0

        self.model: RegisterModel
        self.generation_start: RegisterModel
        self.proven_model: RegisterModel
        self.proven_prefix = 5
        self.generation_base_id = 5
        self.highest = 5
        self.next_id = 6
        self.pending: dict[int, PendingRequest] = {}
        self.completed_ids: set[int] = set()
        self.expected_history: dict[int, Record] = {}
        self.generation_requests: dict[int, Record] = {}
        self.actual_send_count: Counter[int] = Counter()
        self.response_occurrence: Counter[int] = Counter()
        # A response observed at the socket proves that request and every
        # earlier request in the generation reached the ordered executor.  It
        # remains evidence even when the response injector later drops it.
        self.responses_seen: set[int] = set()
        self.tx_events: list[tuple[float, int, int, bytes, str]] = []
        self.delivery_events: list[tuple[float, int, Record, str]] = []

    def _push_tx(
        self,
        due: float,
        request_id: int,
        payload: bytes,
        action: str,
    ) -> None:
        self.sequence += 1
        heapq.heappush(
            self.tx_events, (due, self.sequence, request_id, payload, action)
        )

    def _push_delivery(
        self,
        due: float,
        response: Record,
        action: str,
    ) -> None:
        self.sequence += 1
        heapq.heappush(
            self.delivery_events, (due, self.sequence, response, action)
        )

    def _choose_action(
        self,
        direction: str,
        request_id: int,
        occurrence: int,
    ) -> tuple[str, float]:
        unit = keyed_unit(
            self.seed, self.generation, direction, request_id, occurrence, "action"
        )
        if unit < self.profile.drop_rate:
            action = "DROP"
        elif unit < self.profile.drop_rate + self.profile.duplicate_rate:
            action = "DUPLICATE"
        elif unit < (
            self.profile.drop_rate
            + self.profile.duplicate_rate
            + self.profile.reorder_rate
        ):
            action = "REORDER"
        else:
            action = "PASS"

        delay = 0.0
        if action != "DROP" and keyed_unit(
            self.seed,
            self.generation,
            direction,
            request_id,
            occurrence,
            "delay_enable",
        ) < self.profile.delay_rate:
            delay = self.profile.max_delay_s * keyed_unit(
                self.seed,
                self.generation,
                direction,
                request_id,
                occurrence,
                "delay_value",
            )
            self.counts[f"{direction}_DELAY"] += 1
        if action == "REORDER":
            delay += self.profile.max_delay_s
        self.counts[f"{direction}_{action}"] += 1
        return action, delay

    def _schedule_attempt(self, pending: PendingRequest, now: float) -> None:
        attempt = pending.attempts
        request_id = pending.request.request_id
        self.request_attempt_index += 1

        forced_burst = False
        if self.burst_remaining > 0:
            forced_burst = True
        elif (
            self.profile.burst_every > 0
            and self.request_attempt_index % self.profile.burst_every == 0
        ):
            self.burst_remaining = 2 + (
                keyed_u64(
                    self.seed,
                    self.generation,
                    request_id,
                    attempt,
                    "burst_length",
                )
                % 3
            )
            forced_burst = True

        if forced_burst:
            action = "BURST_DROP"
            delay = 0.0
            self.burst_remaining -= 1
            self.counts["request_BURST_DROP"] += 1
        else:
            action, delay = self._choose_action("request", request_id, attempt)

        self.harness.log.event(
            "random_request_action",
            generation=self.generation,
            request_id=request_id,
            attempt=attempt,
            action=action,
            delay_s=delay,
        )
        if action not in {"DROP", "BURST_DROP"}:
            copies = 2 if action == "DUPLICATE" else 1
            for copy_index in range(copies):
                self._push_tx(
                    now + delay + copy_index * 0.000001,
                    request_id,
                    pending.request.encode(),
                    action,
                )

        pending.attempts += 1
        pending.next_retry = now + self.RETRY_WAITS[attempt]

    def _create_request(self, request_id: int, now: float) -> None:
        slot = (request_id - 6) & 3
        if slot == 0:
            data = 0xA0000000 ^ (keyed_u64(self.seed, request_id, "s0") & 0x0FFFFFFF)
            request = make_set(request_id, 0x0000, data)
            expected = expected_response(request, data=0)
            self.model.scratch0 = data
            self.model.write_count = (self.model.write_count + 1) & 0xFFFFFFFF
        elif slot == 1:
            request = make_query(request_id, 0x0000)
            expected = expected_response(request, data=self.model.scratch0)
        elif slot == 2:
            data = 0xB0000000 ^ (keyed_u64(self.seed, request_id, "s1") & 0x0FFFFFFF)
            request = make_set(request_id, 0x0001, data)
            expected = expected_response(request, data=0)
            self.model.scratch1 = data
            self.model.write_count = (self.model.write_count + 1) & 0xFFFFFFFF
        else:
            request = make_query(request_id, 0x0001)
            expected = expected_response(request, data=self.model.scratch1)

        pending = PendingRequest(request=request, expected=expected)
        self.pending[request_id] = pending
        self.expected_history[request_id] = expected
        self.generation_requests[request_id] = request
        self.total_created += 1
        self._schedule_attempt(pending, now)

    def _send_due(self, now: float) -> None:
        while self.tx_events and self.tx_events[0][0] <= now:
            _, _, request_id, payload, action = heapq.heappop(self.tx_events)
            self.harness.send_payload(
                payload, action=action, request_id=request_id
            )
            self.actual_send_count[request_id] += 1

    def _receive_available(self, now: float) -> None:
        while True:
            try:
                response = self.harness.recv(0.0)
            except (socket.timeout, BlockingIOError):
                return
            reference = self.expected_history.get(response.request_id)
            if reference is None:
                raise TestFailure(
                    f"generation {self.generation}: unknown response {response}"
                )
            if response != reference:
                raise TestFailure(
                    f"generation {self.generation} response {response.request_id}: "
                    f"expected {reference}, got {response}"
                )
            self.responses_seen.add(response.request_id)
            # Seeing response N proves ordered execution through N.  Advance
            # the proven state incrementally so recovery never has to replay
            # millions of historical requests while the wire is silent.
            if response.request_id > self.proven_prefix:
                for proven_id in range(
                    self.proven_prefix + 1, response.request_id + 1
                ):
                    request = self.generation_requests.get(proven_id)
                    if request is None:
                        raise TestFailure(
                            f"response {response.request_id} proves unknown "
                            f"request {proven_id}"
                        )
                    self._apply_set(self.proven_model, request)
                self.proven_prefix = response.request_id
            occurrence = self.response_occurrence[response.request_id]
            self.response_occurrence[response.request_id] += 1
            action, delay = self._choose_action(
                "response", response.request_id, occurrence
            )
            self.harness.log.event(
                "random_response_action",
                generation=self.generation,
                request_id=response.request_id,
                occurrence=occurrence,
                action=action,
                delay_s=delay,
            )
            if action == "DROP":
                continue
            copies = 2 if action == "DUPLICATE" else 1
            for copy_index in range(copies):
                self._push_delivery(
                    now + delay + copy_index * 0.000001,
                    response,
                    action,
                )

    def _deliver_due(self, now: float) -> None:
        while self.delivery_events and self.delivery_events[0][0] <= now:
            _, _, response, action = heapq.heappop(self.delivery_events)
            pending = self.pending.get(response.request_id)
            self.harness.log.event(
                "random_delivery",
                generation=self.generation,
                request_id=response.request_id,
                action=action,
                duplicate=bool(pending is None or pending.completed),
            )
            if pending is None or pending.completed:
                self.counts["host_duplicate_delivery"] += 1
                continue
            if response != pending.expected:
                raise TestFailure(f"delivered response changed {response}")
            pending.completed = True
            self.completed_ids.add(response.request_id)
            self.total_completed += 1
            while self.highest + 1 in self.completed_ids:
                self.highest += 1
                self.completed_ids.remove(self.highest)
                self.pending.pop(self.highest, None)

    def _retry_or_recover(self, now: float) -> bool:
        for request_id in sorted(self.pending):
            pending = self.pending[request_id]
            if pending.completed or now < pending.next_retry:
                continue
            if pending.attempts < 3:
                self.counts["request_retry"] += 1
                self._schedule_attempt(pending, now)
            else:
                self.harness.log.event(
                    "retry_exhausted",
                    generation=self.generation,
                    request_id=request_id,
                )
                self._recover_generation()
                return True
        return False

    def _flush_scheduled_transmissions(self) -> None:
        while self.tx_events:
            due = self.tx_events[0][0]
            now = time.perf_counter()
            if due > now:
                time.sleep(min(due - now, 0.010))
            self._send_due(time.perf_counter())
            self._receive_available(time.perf_counter())
        # Give every actually transmitted datagram time to reach the direct
        # link, execute, and produce any response that the old generation will
        # deliberately discard before socket closure.
        deadline = time.perf_counter() + max(0.020, self.profile.max_delay_s)
        while time.perf_counter() < deadline:
            self._receive_available(time.perf_counter())
            time.sleep(0.0002)

    @staticmethod
    def _apply_set(model: RegisterModel, request: Record) -> None:
        if request.message_type != SET:
            return
        if request.address == 0x0000:
            model.scratch0 = request.data
        elif request.address == 0x0001:
            model.scratch1 = request.data
        else:
            raise TestFailure(f"random model unexpected SET address {request.address}")
        model.write_count = (model.write_count + 1) & 0xFFFFFFFF

    def _recover_generation(self) -> None:
        self._flush_scheduled_transmissions()

        # sendto() is only an upper bound on execution.  In particular, the
        # Windows/NDIS/NIC path may hold a datagram long enough for the FPGA
        # silence watchdog to start a new generation before that datagram
        # reaches the wire.  Conversely, seeing response N proves that the
        # strictly ordered executor completed every request through N.  After
        # retry exhaustion, accept only a hardware state corresponding to one
        # exact prefix between those two bounds; never assume that every
        # sendto() call executed.
        executed_prefix_min = self.proven_prefix
        request_id = self.generation_base_id + 1
        executed_prefix_max = self.generation_base_id
        while request_id in self.generation_requests:
            if self.actual_send_count[request_id] == 0:
                break
            executed_prefix_max = request_id
            request_id += 1

        if executed_prefix_min > executed_prefix_max:
            raise TestFailure(
                "recovery evidence is inconsistent: "
                f"response prefix {executed_prefix_min} exceeds sent prefix "
                f"{executed_prefix_max}"
            )

        self.harness.log.event(
            "generation_recovery_start",
            generation=self.generation,
            executed_prefix_min=executed_prefix_min,
            executed_prefix_max=executed_prefix_max,
            generated_max=max(
                self.generation_requests, default=self.generation_base_id
            ),
        )
        # Only the tail after the greatest response observed is uncertain.
        # W=4 bounds this to at most four requests.
        candidate = copy.deepcopy(self.proven_model)
        candidate_states: list[tuple[int, RegisterModel]] = [
            (executed_prefix_min, copy.deepcopy(candidate))
        ]
        for prefix in range(executed_prefix_min + 1, executed_prefix_max + 1):
            self._apply_set(candidate, self.generation_requests[prefix])
            candidate_states.append((prefix, copy.deepcopy(candidate)))

        self.harness.quiet_reopen(self.quiet_s)
        observed = probe_generation_fixed(self.harness)

        reset_delta = (
            observed.watchdog_count - self.generation_start.watchdog_count
        ) & 0xFFFFFFFF
        # During high-rate Windows/NDIS traffic, datagrams already accepted by
        # sendto() can cross the first watchdog boundary and re-arm ACTIVITY
        # inside the intentional quiet period.  Multiple resets are therefore
        # valid only inside recovery, are bounded here, and are followed by an
        # active-traffic stability proof.  The dedicated R3 test remains
        # strict: exactly one reset per controlled cycle.
        if not 1 <= reset_delta <= 8:
            raise TestFailure(
                f"watchdog reset delta {reset_delta} outside recovery bound 1..8"
            )

        matching_prefixes: list[int] = []
        for prefix, state in candidate_states:
            if (
                observed.scratch0 == state.scratch0
                and observed.scratch1 == state.scratch1
                and observed.write_count == state.write_count
            ):
                matching_prefixes.append(prefix)
        if not matching_prefixes:
            raise TestFailure(
                "recovered register state is not any legal executed prefix "
                f"[{executed_prefix_min}, {executed_prefix_max}]: "
                f"scratch0=0x{observed.scratch0:08X} "
                f"scratch1=0x{observed.scratch1:08X} "
                f"write_count={observed.write_count}"
            )
        self.harness.log.event(
            "generation_recovery_verified",
            generation=self.generation,
            executed_prefix_min=executed_prefix_min,
            executed_prefix_max=executed_prefix_max,
            matching_prefixes=matching_prefixes,
            scratch0=observed.scratch0,
            scratch1=observed.scratch1,
            write_count=observed.write_count,
            watchdog_count=observed.watchdog_count,
            watchdog_reset_delta=reset_delta,
        )
        stable_prefix = verify_recovery_stable(
            self.harness, observed.watchdog_count
        )
        self.recovery_count += 1
        self.counts["watchdog_recovery"] += 1
        self.model = copy.deepcopy(observed)
        self._start_generation_state(base_id=stable_prefix)

    def _start_generation_state(self, *, base_id: int = 5) -> None:
        self.generation += 1
        self.generation_start = copy.deepcopy(self.model)
        self.proven_model = copy.deepcopy(self.model)
        self.generation_base_id = base_id
        self.proven_prefix = base_id
        self.highest = base_id
        self.next_id = base_id + 1
        self.pending.clear()
        self.completed_ids.clear()
        self.expected_history.clear()
        self.generation_requests.clear()
        self.actual_send_count.clear()
        self.response_occurrence.clear()
        self.responses_seen.clear()
        self.tx_events.clear()
        self.delivery_events.clear()
        self.burst_remaining = 0

    def _enabled_gate_actions(self) -> list[str]:
        enabled: list[str] = []
        if self.profile.drop_rate:
            enabled.append("DROP")
        if self.profile.duplicate_rate:
            enabled.append("DUPLICATE")
        if self.profile.reorder_rate:
            enabled.append("REORDER")
        if self.profile.delay_rate:
            enabled.append("DELAY")
        return enabled

    def _gates_met(self) -> bool:
        if self.total_completed < self.profile.min_completions:
            return False
        for action in self._enabled_gate_actions():
            total = self.counts[f"request_{action}"] + self.counts[
                f"response_{action}"
            ]
            if total < self.profile.min_action_count:
                return False
        return True

    def run(self) -> dict[str, object]:
        self.harness.quiet_reopen(self.quiet_s)
        self.model = probe_generation_fixed(self.harness)
        self._start_generation_state()
        started = time.perf_counter()
        self.next_progress = started + 5.0
        sending = True

        while True:
            now = time.perf_counter()
            self._send_due(now)
            self._receive_available(now)
            self._deliver_due(now)
            if self._retry_or_recover(now):
                continue

            if sending and self._gates_met():
                sending = False
                self.harness.log.event(
                    "random_gates_met",
                    profile=self.profile.name,
                    completed=self.total_completed,
                    elapsed_s=now - started,
                    counts=dict(self.counts),
                )

            while sending and self.next_id <= self.highest + 4:
                self._create_request(self.next_id, now)
                self.next_id += 1

            if now >= self.next_progress:
                elapsed = now - started
                rate = self.total_completed / elapsed if elapsed else 0.0
                self.harness.log.line(
                    f"PROGRESS profile={self.profile.name} seed={self.seed} "
                    f"completed={self.total_completed} rate={rate:.1f}/s "
                    f"generation={self.generation} recoveries={self.recovery_count}"
                )
                self.harness.log.event(
                    "progress",
                    profile=self.profile.name,
                    seed=self.seed,
                    completed=self.total_completed,
                    elapsed_s=elapsed,
                    rate=rate,
                    generation=self.generation,
                    recoveries=self.recovery_count,
                    counts=dict(self.counts),
                )
                self.next_progress = now + 5.0

            if (
                not sending
                and not self.pending
                and not self.tx_events
                and not self.delivery_events
            ):
                break
            # Windows commonly rounds sub-millisecond sleeps up to about
            # 1 ms.  Yield without imposing that latency so the four-request
            # window, rather than the host scheduler, remains the main rate
            # limiter during long runs.
            time.sleep(0)

        # End with an intentional clean generation boundary and compare the
        # persistent register state against the complete reference model.
        final_expected = copy.deepcopy(self.model)
        self.harness.quiet_reopen(self.quiet_s)
        final_observed = probe_generation_fixed(self.harness)
        verify_probe(final_observed, final_expected, expected_reset_delta=1)
        elapsed = time.perf_counter() - started
        rate = self.total_completed / elapsed if elapsed else 0.0
        return {
            "result": "PASS",
            "suite": "random_black_box",
            "profile": self.profile.name,
            "seed": self.seed,
            "elapsed_s": elapsed,
            "completed": self.total_completed,
            "created": self.total_created,
            "rate_per_s": rate,
            "generations": self.generation,
            "watchdog_recoveries": self.recovery_count,
            "counts": dict(self.counts),
            "scratch0": final_expected.scratch0,
            "scratch1": final_expected.scratch1,
            "write_count": final_expected.write_count,
            "watchdog_count": final_expected.watchdog_count,
        }


def run_recovery_cycles(
    harness: Harness,
    quiet_s: float,
    cycles: int,
) -> dict[str, object]:
    harness.quiet_reopen(quiet_s)
    model = probe_generation_fixed(harness)
    started = time.perf_counter()
    for cycle in range(cycles):
        value = 0xC0000000 | (cycle & 0x0FFFFFFF)
        request = make_set(6, 0x0000, value)
        expected = expected_response(request, data=0)
        for attempt in range(3):
            harness.send(request, action="R3_RESPONSE_DROP")
            response = harness.recv(0.250)
            if response != expected:
                raise TestFailure(
                    f"R3 cycle {cycle} response mismatch {response}"
                )
            harness.log.event(
                "inject_drop",
                direction="response",
                cycle=cycle,
                attempt=attempt,
                request_id=6,
            )
            time.sleep((0.002, 0.004, 0.008)[attempt])
        model.scratch0 = value
        model.write_count = (model.write_count + 1) & 0xFFFFFFFF
        harness.quiet_reopen(quiet_s)
        observed = probe_generation_fixed(harness)
        verify_probe(observed, model, expected_reset_delta=1)
        if (cycle + 1) % 10 == 0 or cycle + 1 == cycles:
            elapsed = time.perf_counter() - started
            harness.log.line(
                f"PROGRESS R3 cycles={cycle + 1}/{cycles} "
                f"elapsed_s={elapsed:.3f} write_count={model.write_count} "
                f"watchdog_count={model.watchdog_count}"
            )
    elapsed = time.perf_counter() - started
    return {
        "result": "PASS",
        "suite": "watchdog_recovery_cycles",
        "cycles": cycles,
        "elapsed_s": elapsed,
        "failure_rate_observed": 0.0,
        "rule_of_three_95_upper": 3.0 / cycles if cycles else None,
        "scratch0": model.scratch0,
        "write_count": model.write_count,
        "watchdog_count": model.watchdog_count,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-ip", default="192.168.1.10")
    parser.add_argument("--fpga-ip", default="192.168.1.20")
    parser.add_argument("--port", type=int, default=32000)
    parser.add_argument("--quiet-seconds", type=float, default=0.650)
    parser.add_argument(
        "--output-dir", type=Path, default=Path("fpga/led/logs/control-fault")
    )
    parser.add_argument(
        "--mode",
        choices=("deterministic", "random", "recovery"),
        default="deterministic",
    )
    parser.add_argument("--profile", choices=tuple(RANDOM_PROFILES), default="debug")
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=1)
    parser.add_argument("--min-completions", type=int)
    parser.add_argument("--min-action-count", type=int)
    parser.add_argument("--burst-every", type=int)
    parser.add_argument("--cycles", type=int, default=100)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    label = args.mode
    if args.mode == "random":
        label = f"{args.profile}_seed{args.seed}"
    elif args.mode == "recovery":
        label = f"recovery_{args.cycles}"
    logger = EventLog(
        args.output_dir,
        label,
        detailed_packets=args.mode == "deterministic",
    )
    harness = Harness(args.host_ip, args.fpga_ip, args.port, logger)
    summary: dict[str, object]
    try:
        logger.line(
            "START current_firmware_black_box "
            "bitstream_sha256=021B0DC22234F45FE71F9131F5B87C122A9BBC6CAB26B409ECFEE7AAC559076A"
        )
        if args.mode == "deterministic":
            summary = run_deterministic(harness, args.quiet_seconds)
        elif args.mode == "random":
            profile = RANDOM_PROFILES[args.profile]
            if args.min_completions is not None:
                profile = replace(profile, min_completions=args.min_completions)
            if args.min_action_count is not None:
                profile = replace(profile, min_action_count=args.min_action_count)
            if args.burst_every is not None:
                if args.burst_every < 0:
                    parser.error("--burst-every must be non-negative")
                profile = replace(profile, burst_every=args.burst_every)
            logger.event("random_profile", profile=asdict(profile), seed=args.seed)
            summary = RandomCampaign(
                harness,
                profile,
                args.seed,
                args.quiet_seconds,
            ).run()
        elif args.mode == "recovery":
            summary = run_recovery_cycles(
                harness,
                args.quiet_seconds,
                args.cycles,
            )
        else:
            raise AssertionError(args.mode)
        logger.line(f"RESULT={summary['result']}")
        logger.summary(summary)
        return 0
    except KeyboardInterrupt:
        summary = {
            "result": "INTERRUPTED",
            "suite": args.mode,
            "note": "Operator stopped the run; no PASS verdict is inferred.",
        }
        logger.event("interrupted", **summary)
        logger.dump_context()
        logger.line("RESULT=INTERRUPTED")
        logger.summary(summary)
        return 130
    except Exception as exc:
        summary = {
            "result": "FAIL_UNLOCALIZED",
            "suite": args.mode,
            "error_type": type(exc).__name__,
            "error": str(exc),
        }
        logger.event("failure", **summary)
        logger.dump_context()
        logger.line(f"RESULT=FAIL_UNLOCALIZED error={type(exc).__name__}: {exc}")
        logger.summary(summary)
        return 1
    finally:
        harness.close()
        logger.close()


if __name__ == "__main__":
    raise SystemExit(main())
