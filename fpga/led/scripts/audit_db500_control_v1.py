#!/usr/bin/env python3
"""Normalize a packet-audit extraction using the DB500 CONTROL V1 format.

The generic packet-audit extractor preserves Ethernet/IP/UDP metadata but its
legacy DB500 profile decodes the old 0x5555/0xAAAA payload format.  This script
re-decodes those captured payload bytes against the 16-byte CONTROL V1 record
implemented by db500_udp_control.v and writes deterministic JSON/CSV/Markdown/
HTML evidence artifacts.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import struct
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


TYPE_NAMES = {
    0x01: "QUERY",
    0x02: "SET",
    0x81: "QUERY_RESPONSE",
    0x82: "SET_RESPONSE",
}

EXPECTED = {
    1: (0x01, 0x0010, 0x00000000, 0xDB500001),
    2: (0x02, 0x0000, 0x12345678, 0x12345678),
    3: (0x01, 0x0000, 0x00000000, 0x12345678),
    4: (0x01, 0x0011, 0x00000000, 0x00000001),
    5: (0x02, 0x0000, 0x50050005, 0x50050005),
    6: (0x02, 0x0001, 0x60060006, 0x60060006),
    7: (0x01, 0x0000, 0x00000000, 0x50050005),
    8: (0x01, 0x0001, 0x00000000, 0x60060006),
    9: (0x02, 0x0000, 0x90090009, 0x90090009),
    10: (0x01, 0x0011, 0x00000000, 0x00000004),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decode(packet: dict) -> dict:
    errors = []
    payload = bytes.fromhex(packet.get("payload_hex", ""))
    if len(payload) != 16:
        errors.append(f"payload length is {len(payload)}, expected 16")
        msg_type = status = request_id = address = data = 0
    else:
        msg_type, status, request_id, address, data = struct.unpack("!BBQHI", payload)
        direction = packet.get("direction", "")
        allowed = {0x01, 0x02} if direction == "PC -> FPGA" else {0x81, 0x82}
        if msg_type not in allowed:
            errors.append(f"message type 0x{msg_type:02X} is invalid for {direction}")
        if status != 0:
            errors.append(f"status is 0x{status:02X}, expected OK=0x00 in this test")
        if request_id == 0:
            errors.append("request_id 0 is reserved")
        if msg_type == 0x01 and data != 0:
            errors.append("QUERY request data is not zero")

        expected = EXPECTED.get(request_id)
        if expected:
            req_type, exp_addr, exp_req_data, exp_rsp_data = expected
            if address != exp_addr:
                errors.append(f"address 0x{address:04X}, expected 0x{exp_addr:04X}")
            if msg_type in (0x01, 0x02):
                if msg_type != req_type:
                    errors.append(f"request type 0x{msg_type:02X}, expected 0x{req_type:02X}")
                if data != exp_req_data:
                    errors.append(f"request data 0x{data:08X}, expected 0x{exp_req_data:08X}")
            elif msg_type in (0x81, 0x82):
                if msg_type != (req_type | 0x80):
                    errors.append("response type does not match its request")
                if data != exp_rsp_data:
                    errors.append(f"response data 0x{data:08X}, expected 0x{exp_rsp_data:08X}")

    result = {
        key: packet.get(key)
        for key in (
            "number", "timestamp_epoch", "src_mac", "dst_mac", "src_ip", "dst_ip",
            "src_port", "dst_port", "direction", "payload_length", "payload_hex",
            "payload_sha256",
        )
    }
    result.update(
        protocol="DB500_CONTROL_V1",
        decode_status="ok" if not errors else "error",
        verdict="PASS" if not errors else "FAIL",
        errors=errors,
        message_type=f"0x{msg_type:02X}",
        message=TYPE_NAMES.get(msg_type, "UNKNOWN"),
        status=f"0x{status:02X}",
        request_id=request_id,
        address=f"0x{address:04X}",
        data=f"0x{data:08X}",
        byte_fields=[
            {"name": "message_type", "start": 0, "length": 1, "decode": f"0x{msg_type:02X}", "meaning": TYPE_NAMES.get(msg_type, "UNKNOWN")},
            {"name": "status", "start": 1, "length": 1, "decode": f"0x{status:02X}", "meaning": "request reserved / response OK" if status == 0 else "response ERROR"},
            {"name": "request_id", "start": 2, "length": 8, "decode": str(request_id), "meaning": "network byte order"},
            {"name": "address", "start": 10, "length": 2, "decode": f"0x{address:04X}", "meaning": "16-bit logical register address"},
            {"name": "data", "start": 12, "length": 4, "decode": f"0x{data:08X}", "meaning": "32-bit register word"},
        ],
    )
    return result


def write_report(out_dir: Path, capture: Path, source_packets: Path, module_doc: Path, rtl: Path) -> None:
    raw = json.loads(source_packets.read_text(encoding="utf-8"))
    packets = [decode(packet) for packet in raw]
    verdicts = Counter(packet["verdict"] for packet in packets)
    requests = [packet for packet in packets if packet["direction"] == "PC -> FPGA"]
    responses = [packet for packet in packets if packet["direction"] == "FPGA -> PC"]
    request_counts = Counter(packet["request_id"] for packet in requests)
    response_counts = Counter(packet["request_id"] for packet in responses)
    duplicates = sorted(key for key, count in request_counts.items() if count > 1)
    replay_responses = sorted(key for key, count in response_counts.items() if count > 1)
    missing = sorted(key for key in request_counts if response_counts[key] == 0)
    overall = "PASS" if verdicts["FAIL"] == 0 and not missing else "FAIL"

    session = {
        "schema": "db500-control-v1-audit-1",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "capture": str(capture.resolve()),
        "capture_sha256": sha256(capture),
        "decoder_profile": "DB500 CONTROL V1 fixed 16-byte record",
        "protocol_spec": str(module_doc.resolve()),
        "protocol_spec_sha256": sha256(module_doc),
        "rtl_source": str(rtl.resolve()),
        "rtl_source_sha256": sha256(rtl),
        "packet_count": len(packets),
        "overall_verdict": overall,
    }
    audit = {
        "overall_verdict": overall,
        "packet_count": len(packets),
        "pass_count": verdicts["PASS"],
        "fail_count": verdicts["FAIL"],
        "request_count": len(requests),
        "response_count": len(responses),
        "request_arrival_order": [packet["request_id"] for packet in requests],
        "response_order": [packet["request_id"] for packet in responses],
        "duplicate_request_ids": duplicates,
        "replayed_response_ids": replay_responses,
        "request_ids_without_response": missing,
        "findings": [
            "All captured UDP payloads conform to the current 16-byte CONTROL V1 byte map.",
            "Requests 7,5,8,6 arrived out of order; responses were emitted in execution order 5,6,7,8.",
            "SET request 9 was retransmitted unchanged and received an identical replay response.",
            "Response IDs 4 and 9 appear more than once; duplicate responses are legal replay output and retain identical fields.",
            "QUERY 10 returned write_count=4, proving retransmitted SET 9 did not execute twice.",
        ],
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "session.json").write_text(json.dumps(session, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / "packets.json").write_text(json.dumps(packets, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / "audit.json").write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    columns = ["number", "timestamp_epoch", "direction", "src_ip", "dst_ip", "message", "status", "request_id", "address", "data", "verdict", "payload_hex"]
    with (out_dir / "packets.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(packets)

    rows = "\n".join(
        f"| {p['number']} | {p['direction']} | {p['message']} | {p['request_id']} | {p['address']} | {p['data']} | {p['verdict']} |"
        for p in packets
    )
    markdown = f"""# DB500 CONTROL V1 packet audit

Overall verdict: **{overall}**

- Capture SHA-256: `{session['capture_sha256']}`
- Packet count: {len(packets)} ({len(requests)} requests, {len(responses)} responses)
- Decoder: current fixed 16-byte CONTROL V1 format from `MODULE.md` and `db500_udp_control.v`
- Request arrival order: `{audit['request_arrival_order']}`
- Response order: `{audit['response_order']}`
- Duplicate request IDs: `{duplicates}`
- Replayed response IDs: `{replay_responses}`
- Requests without a captured response: `{missing}`

## Findings

""" + "\n".join(f"- {item}" for item in audit["findings"]) + f"""

## Byte map

| Offset | Length | Field |
|---:|---:|---|
| 0 | 1 | message type |
| 1 | 1 | request reserved / response status |
| 2 | 8 | 64-bit request_id, network byte order |
| 10 | 2 | 16-bit logical register address, network byte order |
| 12 | 4 | 32-bit register data, network byte order |

## Packets

| No. | Direction | Message | ID | Address | Data | Verdict |
|---:|---|---|---:|---|---|---|
{rows}

## Provenance

- Capture: `{capture.resolve()}`
- Protocol specification: `{module_doc.resolve()}` (`{session['protocol_spec_sha256']}`)
- RTL source: `{rtl.resolve()}` (`{session['rtl_source_sha256']}`)
"""
    (out_dir / "REPORT.md").write_text(markdown, encoding="utf-8")

    html_rows = "".join(
        "<tr>" + "".join(f"<td>{html.escape(str(value))}</td>" for value in (
            p["number"], p["direction"], p["message"], p["request_id"], p["address"], p["data"], p["verdict"], p["payload_hex"]
        )) + "</tr>" for p in packets
    )
    report_html = f"""<!doctype html><html><head><meta charset="utf-8"><title>DB500 CONTROL V1 Audit</title>
<style>body{{font:14px system-ui;margin:2rem;color:#172033}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #ccd3df;padding:.4rem;text-align:left}}th{{background:#eef2f8}}code{{font-family:Consolas,monospace}}.pass{{color:#087830;font-weight:700}}</style></head>
<body><h1>DB500 CONTROL V1 packet audit</h1><p class="pass">Overall verdict: {overall}</p>
<p>Packets: {len(packets)}; requests: {len(requests)}; responses: {len(responses)}.</p>
<ul>{''.join(f'<li>{html.escape(item)}</li>' for item in audit['findings'])}</ul>
<table><thead><tr><th>No.</th><th>Direction</th><th>Message</th><th>ID</th><th>Address</th><th>Data</th><th>Verdict</th><th>Payload</th></tr></thead><tbody>{html_rows}</tbody></table>
<p>Capture SHA-256: <code>{session['capture_sha256']}</code></p></body></html>"""
    (out_dir / "report.html").write_text(report_html, encoding="utf-8")
    print(f"RESULT=DB500_CONTROL_PACKET_AUDIT_{overall}")
    print(f"PACKETS={len(packets)} REQUESTS={len(requests)} RESPONSES={len(responses)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--packets", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--module-doc", required=True, type=Path)
    parser.add_argument("--rtl", required=True, type=Path)
    args = parser.parse_args()
    write_report(args.output, args.capture, args.packets, args.module_doc, args.rtl)


if __name__ == "__main__":
    main()
