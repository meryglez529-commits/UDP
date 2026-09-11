#!/usr/bin/env python3
"""Send deterministic UDP payloads through the DB500 echo-test image."""

from __future__ import annotations

import argparse
import socket
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-ip", default="192.168.1.10")
    parser.add_argument("--fpga-ip", default="192.168.1.20")
    parser.add_argument("--port", type=int, default=32000)
    parser.add_argument("--timeout", type=float, default=2.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payloads = [
        b"DB500 UDP echo",
        bytes(range(256)),
        bytes((index * 37 + 11) & 0xFF for index in range(1472)),
    ]

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(args.timeout)
        sock.bind((args.host_ip, args.port))

        for sequence, payload in enumerate(payloads, start=1):
            started = time.perf_counter()
            sock.sendto(payload, (args.fpga_ip, args.port))
            echoed, source = sock.recvfrom(2048)
            elapsed_ms = (time.perf_counter() - started) * 1000.0

            if source != (args.fpga_ip, args.port):
                raise RuntimeError(f"packet {sequence}: unexpected source {source}")
            if echoed != payload:
                raise RuntimeError(
                    f"packet {sequence}: payload mismatch "
                    f"sent={len(payload)} received={len(echoed)}"
                )
            print(
                f"PASS packet={sequence} bytes={len(payload)} "
                f"round_trip_ms={elapsed_ms:.3f}"
            )

    print("RESULT=UDP_ECHO_HOST_TEST_PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
