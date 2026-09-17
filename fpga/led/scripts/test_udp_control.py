#!/usr/bin/env python3
"""Exercise DB500 CONTROL V1 against the FPGA test register bank."""

from __future__ import annotations

import argparse
import socket
import struct
import time
from dataclasses import dataclass


QUERY = 0x01
SET = 0x02
QUERY_RESPONSE = 0x81
SET_RESPONSE = 0x82
OK = 0x00
ERROR = 0x01
FORMAT = struct.Struct("!BBQHI")


@dataclass(frozen=True)
class Record:
    message_type: int
    status: int
    request_id: int
    address: int
    data: int

    def encode(self) -> bytes:
        return FORMAT.pack(
            self.message_type, self.status, self.request_id,
            self.address, self.data
        )

    @classmethod
    def decode(cls, payload: bytes) -> "Record":
        if len(payload) != FORMAT.size:
            raise RuntimeError(f"response length {len(payload)} != 16")
        return cls(*FORMAT.unpack(payload))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-ip", default="192.168.1.10")
    parser.add_argument("--fpga-ip", default="192.168.1.20")
    parser.add_argument("--port", type=int, default=32000)
    parser.add_argument("--timeout", type=float, default=0.050)
    parser.add_argument("--stress-seconds", type=float, default=0.0)
    parser.add_argument("--min-rate", type=float, default=5000.0)
    parser.add_argument("--fail-stop", action="store_true")
    parser.add_argument("--watchdog-recovery", action="store_true")
    parser.add_argument("--watchdog-timeout", type=float, default=0.500)
    parser.add_argument("--watchdog-guard", type=float, default=0.100)
    return parser.parse_args()


def expected_response(request: Record, *, data: int, status: int = OK) -> Record:
    return Record(
        request.message_type | 0x80,
        status,
        request.request_id,
        request.address,
        request.data if request.message_type == SET else data,
    )


def receive_record(sock: socket.socket, fpga_endpoint: tuple[str, int]) -> Record:
    payload, source = sock.recvfrom(2048)
    if source != fpga_endpoint:
        raise RuntimeError(f"unexpected response endpoint {source}")
    return Record.decode(payload)


def open_control_socket(args: argparse.Namespace) -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(args.timeout)
    sock.bind((args.host_ip, args.port))
    return sock


def transact(
    sock: socket.socket,
    fpga_endpoint: tuple[str, int],
    request: Record,
    expected: Record,
    attempts: int = 3,
) -> Record:
    encoded = request.encode()
    for _ in range(attempts):
        sock.sendto(encoded, fpga_endpoint)
        deadline = time.perf_counter() + sock.gettimeout()
        while time.perf_counter() < deadline:
            try:
                response = receive_record(sock, fpga_endpoint)
            except socket.timeout:
                break
            if response.request_id != request.request_id:
                continue
            if response != expected:
                raise RuntimeError(
                    f"request {request.request_id}: expected {expected}, got {response}"
                )
            return response
    raise TimeoutError(f"request {request.request_id}: no valid response")


def collect_pipeline(
    sock: socket.socket,
    fpga_endpoint: tuple[str, int],
    requests: list[Record],
    expected: dict[int, Record],
) -> dict[int, Record]:
    request_by_id = {request.request_id: request for request in requests}
    for request in request_by_id.values():
        sock.sendto(request.encode(), fpga_endpoint)
    received: dict[int, Record] = {}
    deadline = time.perf_counter() + 5.0
    resend_at = time.perf_counter() + max(sock.gettimeout(), 0.050)
    while len(received) < len(requests) and time.perf_counter() < deadline:
        try:
            response = receive_record(sock, fpga_endpoint)
        except socket.timeout:
            continue
        if response.request_id in expected:
            if response != expected[response.request_id]:
                raise RuntimeError(f"pipeline response mismatch: {response}")
            received[response.request_id] = response
        if time.perf_counter() >= resend_at:
            for request_id, request in request_by_id.items():
                if request_id not in received:
                    sock.sendto(request.encode(), fpga_endpoint)
            resend_at = time.perf_counter() + max(sock.gettimeout(), 0.050)
    if len(received) != len(requests):
        missing = sorted(set(expected) - set(received))
        raise TimeoutError(f"pipeline responses missing: {missing}")
    return received


def run_stress(
    sock: socket.socket,
    fpga_endpoint: tuple[str, int],
    first_id: int,
    seconds: float,
    min_rate: float,
) -> int:
    next_id = first_id
    highest_contiguous = first_id - 1
    pending: dict[int, tuple[Record, float]] = {}
    completed: set[int] = set()
    total_completed = 0
    started = time.perf_counter()
    stop_sending = started + seconds
    timeout = max(sock.gettimeout(), 0.010)

    while time.perf_counter() < stop_sending or pending:
        now = time.perf_counter()
        while now < stop_sending and next_id <= highest_contiguous + 4:
            address = 0x0010 if (next_id & 1) else 0x0011
            request = Record(QUERY, 0, next_id, address, 0)
            sock.sendto(request.encode(), fpga_endpoint)
            pending[next_id] = (request, now)
            next_id += 1

        try:
            response = receive_record(sock, fpga_endpoint)
            item = pending.get(response.request_id)
            if item is not None:
                request = item[0]
                if response.message_type != QUERY_RESPONSE or response.status != OK:
                    raise RuntimeError(f"stress error response: {response}")
                if response.address != request.address:
                    raise RuntimeError(f"stress address mismatch: {response}")
                completed.add(response.request_id)
                del pending[response.request_id]
                total_completed += 1
                while highest_contiguous + 1 in completed:
                    highest_contiguous += 1
                    completed.remove(highest_contiguous)
        except socket.timeout:
            pass

        now = time.perf_counter()
        for request_id, (request, sent_at) in list(pending.items()):
            if now - sent_at >= timeout:
                sock.sendto(request.encode(), fpga_endpoint)
                pending[request_id] = (request, now)

        if now > stop_sending + 2.0:
            raise TimeoutError(f"stress drain timed out with {len(pending)} pending")

    elapsed = time.perf_counter() - started
    rate = total_completed / elapsed
    print(
        f"PASS stress requests={total_completed} elapsed_s={elapsed:.3f} "
        f"rate={rate:.1f}_requests_per_s"
    )
    if rate < min_rate:
        raise RuntimeError(f"stress rate {rate:.1f} < required {min_rate:.1f}")
    return next_id


def main() -> int:
    args = parse_args()
    fpga_endpoint = (args.fpga_ip, args.port)
    with open_control_socket(args) as sock:

        initial = [
            Record(QUERY, 0, 1, 0x0010, 0),
            Record(SET, 0, 2, 0x0000, 0x12345678),
            Record(QUERY, 0, 3, 0x0000, 0),
            Record(QUERY, 0, 4, 0x0011, 0),
        ]
        initial_expected = {
            1: expected_response(initial[0], data=0xDB500001),
            2: expected_response(initial[1], data=0),
            3: expected_response(initial[2], data=0x12345678),
            4: expected_response(initial[3], data=1),
        }
        collect_pipeline(sock, fpga_endpoint, initial, initial_expected)
        print("PASS initial_window ids=1..4")

        by_id = {
            5: Record(SET, 0, 5, 0x0000, 0x50050005),
            6: Record(SET, 0, 6, 0x0001, 0x60060006),
            7: Record(QUERY, 0, 7, 0x0000, 0),
            8: Record(QUERY, 0, 8, 0x0001, 0),
        }
        reordered = [by_id[7], by_id[5], by_id[8], by_id[6]]
        reordered_expected = {
            5: expected_response(by_id[5], data=0),
            6: expected_response(by_id[6], data=0),
            7: expected_response(by_id[7], data=0x50050005),
            8: expected_response(by_id[8], data=0x60060006),
        }
        collect_pipeline(sock, fpga_endpoint, reordered, reordered_expected)
        print("PASS reordered_window arrival=7,5,8,6 execution=5,6,7,8")

        request9 = Record(SET, 0, 9, 0x0000, 0x90090009)
        response9 = expected_response(request9, data=0)
        sock.sendto(request9.encode(), fpga_endpoint)
        discarded = receive_record(sock, fpga_endpoint)
        if discarded != response9:
            raise RuntimeError(f"unexpected response before replay: {discarded}")
        replayed = transact(sock, fpga_endpoint, request9, response9)
        if replayed != response9:
            raise RuntimeError("saved SET result was not replayed")

        request10 = Record(QUERY, 0, 10, 0x0011, 0)
        transact(
            sock, fpga_endpoint, request10,
            expected_response(request10, data=4)
        )
        print("PASS lost_response_replay write_count=4")

        next_id = 11
        if args.stress_seconds > 0:
            next_id = run_stress(
                sock, fpga_endpoint, next_id,
                args.stress_seconds, args.min_rate
            )

        if args.fail_stop:
            invalid = Record(QUERY, 0, next_id, 0xFFFF, 0)
            transact(
                sock, fpga_endpoint, invalid,
                expected_response(invalid, data=0, status=ERROR)
            )
            blocked = Record(QUERY, 0, next_id + 1, 0x0010, 0)
            sock.sendto(blocked.encode(), fpga_endpoint)
            try:
                receive_record(sock, fpga_endpoint)
            except socket.timeout:
                print("PASS fail_stop subsequent_request_blocked")
            else:
                raise RuntimeError("request after ERROR was not blocked")

        if args.watchdog_recovery:
            # The recovery contract requires total CONTROL silence.  Close the
            # old socket so queued replies cannot be mistaken for the first
            # response in the new communication generation.
            wait_seconds = args.watchdog_timeout + args.watchdog_guard
            sock.close()
            time.sleep(wait_seconds)

            with open_control_socket(args) as recovery_sock:
                preserved = Record(QUERY, 0, 1, 0x0000, 0)
                transact(
                    recovery_sock, fpga_endpoint, preserved,
                    expected_response(preserved, data=0x90090009)
                )
                write_count = Record(QUERY, 0, 2, 0x0011, 0)
                transact(
                    recovery_sock, fpga_endpoint, write_count,
                    expected_response(write_count, data=4)
                )
                reset_count = Record(QUERY, 0, 3, 0x0012, 0)
                transact(
                    recovery_sock, fpga_endpoint, reset_count,
                    expected_response(reset_count, data=1)
                )
            print(
                "PASS watchdog_recovery request_id_restarted=1 "
                "scratch0=0x90090009 write_count=4 reset_count=1"
            )

    print("RESULT=DB500_CONTROL_HOST_TEST_PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
