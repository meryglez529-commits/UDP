#!/usr/bin/env python3
"""Verify transparent DATA echo, Jumbo frames, and CONTROL coexistence."""

from __future__ import annotations

import argparse
import socket
import struct
import time


CTRL = struct.Struct("!BBQHI")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-ip", default="192.168.1.10")
    parser.add_argument("--fpga-ip", default="192.168.1.20")
    parser.add_argument("--data-port", type=int, default=32001)
    parser.add_argument("--control-port", type=int, default=32000)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--jumbo-count", type=int, default=32)
    parser.add_argument("--watchdog-wait", type=float, default=0.7)
    return parser.parse_args()


def payload(size: int, sequence: int) -> bytes:
    prefix = struct.pack("!QI", sequence, size)
    if size <= len(prefix):
        return prefix[:size]
    return prefix + bytes(((index * 37 + sequence * 13) & 0xFF)
                          for index in range(size - len(prefix)))


def receive_expected(
    sock: socket.socket,
    endpoint: tuple[str, int],
    expected: bytes,
) -> None:
    received, source = sock.recvfrom(16384)
    if source != endpoint:
        raise RuntimeError(f"unexpected DATA source {source}")
    if received != expected:
        mismatch = next((i for i, pair in enumerate(zip(received, expected))
                         if pair[0] != pair[1]), None)
        raise RuntimeError(
            f"DATA mismatch length={len(received)}/{len(expected)} first={mismatch}"
        )


def data_transact(
    sock: socket.socket,
    endpoint: tuple[str, int],
    value: bytes,
    attempts: int = 3,
) -> None:
    for _ in range(attempts):
        sock.sendto(value, endpoint)
        try:
            receive_expected(sock, endpoint, value)
            return
        except socket.timeout:
            continue
    raise TimeoutError(f"no DATA echo for {len(value)} byte payload")


def main() -> int:
    args = parse_args()
    data_endpoint = (args.fpga_ip, args.data_port)
    ctrl_endpoint = (args.fpga_ip, args.control_port)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as data_sock, \
            socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as ctrl_sock:
        for sock in (data_sock, ctrl_sock):
            sock.settimeout(args.timeout)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
        data_sock.bind((args.host_ip, args.data_port))
        ctrl_sock.bind((args.host_ip, args.control_port))

        boundary_sizes = (1, 2, 7, 64, 1472, 8160, 8172, 8972)
        started = time.perf_counter()
        for sequence, size in enumerate(boundary_sizes, 1):
            data_transact(data_sock, data_endpoint, payload(size, sequence))
            print(f"PASS DATA echo bytes={size}")

        for sequence in range(1000, 1000 + args.jumbo_count):
            data_transact(data_sock, data_endpoint, payload(8972, sequence))
        elapsed = time.perf_counter() - started
        print(
            f"PASS Jumbo echo count={args.jumbo_count} bytes=8972 "
            f"elapsed_s={elapsed:.3f}"
        )

        # Issue CONTROL queries while DATA traffic is active. The query reads
        # the fixed identity register from the existing CONTROL test bank.
        for index in range(16):
            # A freshly programmed CONTROL window starts at request_id 1 and
            # advances in order; distant IDs are intentionally rejected.
            request_id = 1 + index
            ctrl_request = CTRL.pack(0x01, 0, request_id, 0x0010, 0)
            value = payload(8172, 2000 + index)
            data_sock.sendto(value, data_endpoint)
            ctrl_sock.sendto(ctrl_request, ctrl_endpoint)

            ctrl_reply, ctrl_source = ctrl_sock.recvfrom(2048)
            if ctrl_source != ctrl_endpoint:
                raise RuntimeError(f"unexpected CONTROL source {ctrl_source}")
            expected_ctrl = CTRL.pack(
                0x81, 0, request_id, 0x0010, 0xDB500001
            )
            if ctrl_reply != expected_ctrl:
                raise RuntimeError(f"CONTROL mismatch at coexistence index {index}")
            receive_expected(data_sock, data_endpoint, value)
        print("PASS CONTROL/DATA coexistence rounds=16")

        # CONTROL activity above arms the 0.5 s board-test watchdog.  After it
        # expires, DATA must remain usable and CONTROL must restart at ID 1.
        time.sleep(args.watchdog_wait)
        value = payload(8972, 3000)
        data_transact(data_sock, data_endpoint, value)
        request_id = 1
        ctrl_request = CTRL.pack(0x01, 0, request_id, 0x0010, 0)
        expected_ctrl = CTRL.pack(0x81, 0, request_id, 0x0010, 0xDB500001)
        ctrl_reply = None
        for _ in range(3):
            ctrl_sock.sendto(ctrl_request, ctrl_endpoint)
            try:
                candidate, source = ctrl_sock.recvfrom(2048)
            except socket.timeout:
                continue
            if source == ctrl_endpoint and candidate == expected_ctrl:
                ctrl_reply = candidate
                break
        if ctrl_reply is None:
            raise TimeoutError("CONTROL did not recover after watchdog reset")
        print("PASS watchdog isolation DATA=8972 CONTROL restart_id=1")

    print("RESULT=DB500_DATA_BOARD_TEST_PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
