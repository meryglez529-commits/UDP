#!/usr/bin/env python3
"""Measure the DB500 UDP echo path without stop-and-wait serialization."""

from __future__ import annotations

import argparse
import csv
import json
import math
import secrets
import socket
import struct
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


MAGIC = b"UPF1"
HEADER = struct.Struct("!4sIIQ")
MIN_PAYLOAD_BYTES = HEADER.size
BODY_XOR = 0xA5A55A5A


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-ip", default="192.168.1.10")
    parser.add_argument("--fpga-ip", default="192.168.1.20")
    parser.add_argument("--port", type=int, default=32000)
    parser.add_argument("--payload-bytes", type=int, default=1472)
    duration_group = parser.add_mutually_exclusive_group()
    duration_group.add_argument("--duration", type=float, default=10.0)
    duration_group.add_argument("--count", type=int)
    parser.add_argument(
        "--target-mbps",
        type=float,
        default=10.0,
        help="Application payload rate. Use 0 for best effort.",
    )
    parser.add_argument(
        "--burst-size",
        type=int,
        default=64,
        help="Maximum token-bucket batch; also controls host-visible burstiness.",
    )
    parser.add_argument("--drain-quiet", type=float, default=2.0)
    parser.add_argument("--drain-max", type=float, default=5.0)
    parser.add_argument("--socket-buffer", type=int, default=4 * 1024 * 1024)
    parser.add_argument("--rtt-sample-stride", type=int, default=32)
    parser.add_argument("--run-id", type=lambda value: int(value, 0))
    parser.add_argument(
        "--allow-reorder",
        action="store_true",
        help=(
            "Report reorder-only runs as PASS_WITH_KNOWN_REORDER_GAP. "
            "Loss, duplicate, corruption, send, and receive errors remain blocking."
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "logs",
    )
    parser.add_argument("--label", default="udp_perf")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def build_body(run_id: int, sequence: int, length: int) -> bytes:
    word = struct.pack("!I", (run_id ^ sequence ^ BODY_XOR) & 0xFFFFFFFF)
    repeats, remainder = divmod(length, len(word))
    return word * repeats + word[:remainder]


def build_payload(run_id: int, sequence: int, send_ns: int, length: int) -> bytes:
    body_length = length - HEADER.size
    return HEADER.pack(MAGIC, run_id, sequence, send_ns) + build_body(
        run_id, sequence, body_length
    )


def percentile(sorted_values: list[float], percent: float) -> float | None:
    if not sorted_values:
        return None
    position = (len(sorted_values) - 1) * percent / 100.0
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return sorted_values[lower]
    weight = position - lower
    return sorted_values[lower] * (1.0 - weight) + sorted_values[upper] * weight


@dataclass
class SharedStats:
    attempted: int = 0
    submitted: int = 0
    submitted_bytes: int = 0
    send_errors: int = 0
    received_total: int = 0
    received_valid: int = 0
    received_unique: int = 0
    received_unique_bytes: int = 0
    duplicate: int = 0
    reorder: int = 0
    corrupt: int = 0
    foreign: int = 0
    highest_sequence: int = -1
    last_receive_ns: int = 0
    rtt_count: int = 0
    rtt_sum_us: float = 0.0
    rtt_min_us: float | None = None
    rtt_max_us: float | None = None
    rtt_samples_us: list[float] = field(default_factory=list)
    receiver_error: str | None = None
    send_ok: bytearray = field(default_factory=bytearray, repr=False)
    received_ok: bytearray = field(default_factory=bytearray, repr=False)


def receive_loop(
    sock: socket.socket,
    source: tuple[str, int],
    run_id: int,
    payload_length: int,
    sample_stride: int,
    stats: SharedStats,
    stop_event: threading.Event,
) -> None:
    while not stop_event.is_set():
        try:
            payload, packet_source = sock.recvfrom(65535)
        except socket.timeout:
            continue
        except OSError as error:
            if stop_event.is_set():
                break
            stats.receiver_error = repr(error)
            break

        receive_ns = time.perf_counter_ns()
        stats.last_receive_ns = receive_ns
        stats.received_total += 1

        if packet_source != source or len(payload) < HEADER.size:
            stats.foreign += 1
            continue

        magic, packet_run_id, sequence, send_ns = HEADER.unpack_from(payload)
        if magic != MAGIC or packet_run_id != run_id:
            stats.foreign += 1
            continue
        if len(payload) != payload_length:
            stats.corrupt += 1
            continue

        expected_body = build_body(run_id, sequence, payload_length - HEADER.size)
        if payload[HEADER.size :] != expected_body:
            stats.corrupt += 1
            continue

        # attempted is published before sendto(), so a valid echo cannot
        # legitimately contain a sequence beyond this bound.
        if sequence >= stats.attempted:
            stats.corrupt += 1
            continue

        stats.received_valid += 1
        if sequence >= len(stats.received_ok):
            stats.received_ok.extend(b"\x00" * (sequence + 1 - len(stats.received_ok)))
        if stats.received_ok[sequence]:
            stats.duplicate += 1
            continue

        stats.received_ok[sequence] = 1
        stats.received_unique += 1
        stats.received_unique_bytes += len(payload)
        if sequence < stats.highest_sequence:
            stats.reorder += 1
        else:
            stats.highest_sequence = sequence

        rtt_us = (receive_ns - send_ns) / 1000.0
        stats.rtt_count += 1
        stats.rtt_sum_us += rtt_us
        stats.rtt_min_us = rtt_us if stats.rtt_min_us is None else min(
            stats.rtt_min_us, rtt_us
        )
        stats.rtt_max_us = rtt_us if stats.rtt_max_us is None else max(
            stats.rtt_max_us, rtt_us
        )
        if sequence % sample_stride == 0:
            stats.rtt_samples_us.append(rtt_us)


def snapshot_row(
    elapsed: float, stats: SharedStats, previous: dict[str, float]
) -> dict[str, float]:
    interval = max(elapsed - previous["elapsed"], 1e-9)
    submitted_bytes = stats.submitted_bytes
    received_bytes = stats.received_unique_bytes
    submitted = stats.submitted
    received = stats.received_unique
    row = {
        "elapsed_s": elapsed,
        "offered_mbps": (submitted_bytes - previous["submitted_bytes"])
        * 8.0
        / interval
        / 1e6,
        "received_mbps": (received_bytes - previous["received_bytes"])
        * 8.0
        / interval
        / 1e6,
        "offered_pps": (submitted - previous["submitted"]) / interval,
        "received_pps": (received - previous["received"]) / interval,
        "submitted": submitted,
        "received_unique": received,
        "send_errors": stats.send_errors,
        "duplicate": stats.duplicate,
        "reorder": stats.reorder,
        "corrupt": stats.corrupt,
        "foreign": stats.foreign,
    }
    previous.update(
        elapsed=elapsed,
        submitted_bytes=submitted_bytes,
        received_bytes=received_bytes,
        submitted=submitted,
        received=received,
    )
    return row


def count_confirmed_loss(stats: SharedStats) -> int:
    common_length = min(len(stats.send_ok), len(stats.received_ok))
    confirmed_received = sum(
        1
        for index in range(common_length)
        if stats.send_ok[index] and stats.received_ok[index]
    )
    return stats.submitted - confirmed_received


def make_summary(
    args: argparse.Namespace,
    run_id: int,
    stats: SharedStats,
    send_elapsed: float,
    total_elapsed: float,
    sndbuf: int,
    rcvbuf: int,
    received_at_send_end: int,
    received_bytes_at_send_end: int,
) -> dict[str, object]:
    samples = sorted(stats.rtt_samples_us)
    loss = count_confirmed_loss(stats)
    blocking_error = (
        stats.send_errors != 0
        or loss != 0
        or stats.duplicate != 0
        or stats.corrupt != 0
        or stats.receiver_error is not None
    )
    if blocking_error:
        result = "OBSERVED_ERRORS"
    elif stats.reorder != 0:
        result = (
            "PASS_WITH_KNOWN_REORDER_GAP"
            if args.allow_reorder
            else "OBSERVED_ERRORS"
        )
    else:
        result = "PASS"
    strict_error_free = (
        stats.send_errors == 0
        and loss == 0
        and stats.duplicate == 0
        and stats.reorder == 0
        and stats.corrupt == 0
        and stats.receiver_error is None
    )
    return {
        "result": result,
        "strict_error_free": strict_error_free,
        "reorder_policy": (
            "KNOWN_EXTERNAL_GAP_NON_BLOCKING"
            if args.allow_reorder
            else "STRICT"
        ),
        "run_id": f"0x{run_id:08X}",
        "host_ip": args.host_ip,
        "fpga_ip": args.fpga_ip,
        "port": args.port,
        "payload_bytes": args.payload_bytes,
        "target_mbps": args.target_mbps,
        "requested_duration_s": None if args.count is not None else args.duration,
        "requested_count": args.count,
        "send_elapsed_s": send_elapsed,
        "total_elapsed_s": total_elapsed,
        "socket_sndbuf": sndbuf,
        "socket_rcvbuf": rcvbuf,
        "attempted": stats.attempted,
        "submitted": stats.submitted,
        "send_errors": stats.send_errors,
        "received_total": stats.received_total,
        "received_unique": stats.received_unique,
        "received_unique_at_send_end": received_at_send_end,
        "host_visible_loss": loss,
        "duplicate": stats.duplicate,
        "reorder": stats.reorder,
        "corrupt": stats.corrupt,
        "foreign": stats.foreign,
        "application_offered_mbps": stats.submitted_bytes
        * 8.0
        / max(send_elapsed, 1e-9)
        / 1e6,
        "received_goodput_mbps": received_bytes_at_send_end
        * 8.0
        / max(send_elapsed, 1e-9)
        / 1e6,
        "offered_pps": stats.submitted / max(send_elapsed, 1e-9),
        "received_pps": received_at_send_end / max(send_elapsed, 1e-9),
        "rtt_samples": len(samples),
        "rtt_min_us": stats.rtt_min_us,
        "rtt_mean_us": (
            stats.rtt_sum_us / stats.rtt_count if stats.rtt_count else None
        ),
        "rtt_max_us": stats.rtt_max_us,
        "rtt_p50_us": percentile(samples, 50.0),
        "rtt_p95_us": percentile(samples, 95.0),
        "rtt_p99_us": percentile(samples, 99.0),
        "rtt_p99_9_us": percentile(samples, 99.9),
        "loss_attribution": "HOST_VISIBLE_ONLY",
        "socket_receive_overflow": "UNOBSERVABLE_WITH_STANDARD_WINDOWS_UDP_SOCKET",
        "receiver_error": stats.receiver_error,
    }


def write_results(
    args: argparse.Namespace,
    summary: dict[str, object],
    interval_rows: list[dict[str, float]],
) -> tuple[Path, Path]:
    args.output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"{args.label}_{timestamp}_{summary['run_id']}"
    json_path = args.output_dir / f"{stem}.json"
    csv_path = args.output_dir / f"{stem}.csv"
    json_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    if interval_rows:
        with csv_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(interval_rows[0]))
            writer.writeheader()
            writer.writerows(interval_rows)
    else:
        csv_path.write_text("", encoding="utf-8")
    return json_path, csv_path


def run_self_test() -> int:
    for length in (HEADER.size, 64, 256, 1472):
        payload = build_payload(0x12345678, 99, 123456789, length)
        magic, run_id, sequence, send_ns = HEADER.unpack_from(payload)
        assert magic == MAGIC
        assert run_id == 0x12345678
        assert sequence == 99
        assert send_ns == 123456789
        assert len(payload) == length
        assert payload[HEADER.size :] == build_body(
            run_id, sequence, length - HEADER.size
        )
    values = [1.0, 2.0, 3.0, 4.0]
    assert percentile(values, 50.0) == 2.5
    assert percentile(values, 0.0) == 1.0
    assert percentile(values, 100.0) == 4.0
    stats = SharedStats(submitted=3)
    stats.send_ok = bytearray((1, 1, 1))
    stats.received_ok = bytearray((1, 0, 1))
    assert count_confirmed_loss(stats) == 1
    print("RESULT=UDP_PERFORMANCE_SCRIPT_SELF_TEST_PASSED")
    return 0


def validate_args(args: argparse.Namespace) -> None:
    if not MIN_PAYLOAD_BYTES <= args.payload_bytes <= 1472:
        raise ValueError(
            f"payload length must be {MIN_PAYLOAD_BYTES}..1472 bytes"
        )
    if args.duration is not None and args.duration <= 0:
        raise ValueError("duration must be positive")
    if args.count is not None and args.count <= 0:
        raise ValueError("count must be positive")
    if args.target_mbps < 0:
        raise ValueError("target Mbps must be non-negative")
    if args.burst_size <= 0:
        raise ValueError("burst size must be positive")
    if args.drain_quiet < 0 or args.drain_max < args.drain_quiet:
        raise ValueError("drain-max must be at least drain-quiet")
    if args.rtt_sample_stride <= 0:
        raise ValueError("RTT sample stride must be positive")


def main() -> int:
    args = parse_args()
    if args.self_test:
        return run_self_test()
    validate_args(args)

    run_id = args.run_id if args.run_id is not None else secrets.randbits(32)
    run_id &= 0xFFFFFFFF
    destination = (args.fpga_ip, args.port)
    stats = SharedStats()
    interval_rows: list[dict[str, float]] = []
    stop_event = threading.Event()

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, args.socket_buffer)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, args.socket_buffer)
        sock.settimeout(0.1)
        sock.bind((args.host_ip, args.port))
        sndbuf = sock.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF)
        rcvbuf = sock.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)

        receiver = threading.Thread(
            target=receive_loop,
            args=(
                sock,
                destination,
                run_id,
                args.payload_bytes,
                args.rtt_sample_stride,
                stats,
                stop_event,
            ),
            name="udp-perf-receiver",
            daemon=True,
        )
        receiver.start()

        print(
            f"START run_id=0x{run_id:08X} payload={args.payload_bytes} "
            f"target_mbps={args.target_mbps:g} sndbuf={sndbuf} rcvbuf={rcvbuf}"
        )
        start_ns = time.perf_counter_ns()
        previous = {
            "elapsed": 0.0,
            "submitted_bytes": 0.0,
            "received_bytes": 0.0,
            "submitted": 0.0,
            "received": 0.0,
        }
        next_report_ns = start_ns + 1_000_000_000
        target_pps = (
            args.target_mbps * 1e6 / (args.payload_bytes * 8.0)
            if args.target_mbps > 0
            else 0.0
        )
        tokens = 1.0 if target_pps > 0 else float(args.burst_size)
        token_time_ns = start_ns

        while True:
            now_ns = time.perf_counter_ns()
            elapsed = (now_ns - start_ns) / 1e9
            if args.count is not None:
                if stats.attempted >= args.count:
                    break
            elif elapsed >= args.duration:
                break

            if target_pps > 0:
                tokens = min(
                    float(args.burst_size),
                    tokens + (now_ns - token_time_ns) * target_pps / 1e9,
                )
                token_time_ns = now_ns
                if tokens < 1.0:
                    wait_s = min((1.0 - tokens) / target_pps, 0.001)
                    if wait_s > 0.0002:
                        time.sleep(wait_s * 0.8)
                    continue
                send_batch = min(int(tokens), args.burst_size)
            else:
                send_batch = args.burst_size

            if args.count is not None:
                send_batch = min(send_batch, args.count - stats.attempted)

            for _ in range(send_batch):
                sequence = stats.attempted
                send_ns = time.perf_counter_ns()
                payload = build_payload(
                    run_id, sequence, send_ns, args.payload_bytes
                )
                stats.attempted += 1
                stats.send_ok.append(0)
                try:
                    sent = sock.sendto(payload, destination)
                except OSError as error:
                    stats.send_errors += 1
                    print(
                        f"SEND_ERROR sequence={sequence} "
                        f"winerror={getattr(error, 'winerror', None)} error={error}",
                        file=sys.stderr,
                    )
                else:
                    if sent != len(payload):
                        stats.send_errors += 1
                    else:
                        stats.send_ok[sequence] = 1
                        stats.submitted += 1
                        stats.submitted_bytes += sent
                if target_pps > 0:
                    tokens -= 1.0

            now_ns = time.perf_counter_ns()
            if now_ns >= next_report_ns:
                elapsed = (now_ns - start_ns) / 1e9
                row = snapshot_row(elapsed, stats, previous)
                interval_rows.append(row)
                print(
                    f"PROGRESS elapsed={elapsed:.1f}s "
                    f"offered={row['offered_mbps']:.1f}Mbps "
                    f"received={row['received_mbps']:.1f}Mbps "
                    f"tx_pps={row['offered_pps']:.0f} "
                    f"rx_pps={row['received_pps']:.0f} "
                    f"submitted={stats.submitted} received={stats.received_unique} "
                    f"corrupt={stats.corrupt}"
                )
                next_report_ns += 1_000_000_000

        send_end_ns = time.perf_counter_ns()
        send_elapsed = (send_end_ns - start_ns) / 1e9
        received_at_send_end = stats.received_unique
        received_bytes_at_send_end = stats.received_unique_bytes
        if previous["elapsed"] < send_elapsed:
            interval_rows.append(snapshot_row(send_elapsed, stats, previous))
        drain_start_ns = send_end_ns
        while True:
            now_ns = time.perf_counter_ns()
            drain_elapsed = (now_ns - drain_start_ns) / 1e9
            quiet_reference = max(stats.last_receive_ns, send_end_ns)
            quiet_elapsed = (now_ns - quiet_reference) / 1e9
            if quiet_elapsed >= args.drain_quiet or drain_elapsed >= args.drain_max:
                break
            time.sleep(0.02)

        stop_event.set()
        receiver.join(timeout=1.0)
        total_elapsed = (time.perf_counter_ns() - start_ns) / 1e9

    summary = make_summary(
        args,
        run_id,
        stats,
        send_elapsed,
        total_elapsed,
        sndbuf,
        rcvbuf,
        received_at_send_end,
        received_bytes_at_send_end,
    )
    json_path, csv_path = write_results(args, summary, interval_rows)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    print(f"JSON={json_path.resolve()}")
    print(f"CSV={csv_path.resolve()}")
    print(f"RESULT={summary['result']}")
    return 0 if str(summary["result"]).startswith("PASS") else 2


if __name__ == "__main__":
    raise SystemExit(main())
