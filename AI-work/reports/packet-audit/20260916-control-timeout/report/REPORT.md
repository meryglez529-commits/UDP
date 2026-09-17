# DB500 CONTROL V1 packet audit

Overall verdict: **PASS**

- Capture SHA-256: `5981e6fcbdf18e61babe8540c00c4620e14fcc21a3093d9c08aa5456c616697b`
- Packet count: 23 (11 requests, 12 responses)
- Decoder: current fixed 16-byte CONTROL V1 format from `MODULE.md` and `db500_udp_control.v`
- Request arrival order: `[1, 2, 3, 4, 7, 5, 8, 6, 9, 9, 10]`
- Response order: `[1, 2, 3, 4, 4, 5, 6, 7, 8, 9, 9, 10]`
- Duplicate request IDs: `[9]`
- Replayed response IDs: `[4, 9]`
- Requests without a captured response: `[]`

## Findings

- All captured UDP payloads conform to the current 16-byte CONTROL V1 byte map.
- Requests 7,5,8,6 arrived out of order; responses were emitted in execution order 5,6,7,8.
- SET request 9 was retransmitted unchanged and received an identical replay response.
- Response IDs 4 and 9 appear more than once; duplicate responses are legal replay output and retain identical fields.
- QUERY 10 returned write_count=4, proving retransmitted SET 9 did not execute twice.

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
| 1 | PC -> FPGA | QUERY | 1 | 0x0010 | 0x00000000 | PASS |
| 2 | PC -> FPGA | SET | 2 | 0x0000 | 0x12345678 | PASS |
| 3 | PC -> FPGA | QUERY | 3 | 0x0000 | 0x00000000 | PASS |
| 4 | PC -> FPGA | QUERY | 4 | 0x0011 | 0x00000000 | PASS |
| 5 | FPGA -> PC | QUERY_RESPONSE | 1 | 0x0010 | 0xDB500001 | PASS |
| 6 | FPGA -> PC | SET_RESPONSE | 2 | 0x0000 | 0x12345678 | PASS |
| 7 | FPGA -> PC | QUERY_RESPONSE | 3 | 0x0000 | 0x12345678 | PASS |
| 8 | FPGA -> PC | QUERY_RESPONSE | 4 | 0x0011 | 0x00000001 | PASS |
| 9 | FPGA -> PC | QUERY_RESPONSE | 4 | 0x0011 | 0x00000001 | PASS |
| 10 | PC -> FPGA | QUERY | 7 | 0x0000 | 0x00000000 | PASS |
| 11 | PC -> FPGA | SET | 5 | 0x0000 | 0x50050005 | PASS |
| 12 | PC -> FPGA | QUERY | 8 | 0x0001 | 0x00000000 | PASS |
| 13 | PC -> FPGA | SET | 6 | 0x0001 | 0x60060006 | PASS |
| 14 | FPGA -> PC | SET_RESPONSE | 5 | 0x0000 | 0x50050005 | PASS |
| 15 | FPGA -> PC | SET_RESPONSE | 6 | 0x0001 | 0x60060006 | PASS |
| 16 | FPGA -> PC | QUERY_RESPONSE | 7 | 0x0000 | 0x50050005 | PASS |
| 17 | FPGA -> PC | QUERY_RESPONSE | 8 | 0x0001 | 0x60060006 | PASS |
| 18 | PC -> FPGA | SET | 9 | 0x0000 | 0x90090009 | PASS |
| 19 | FPGA -> PC | SET_RESPONSE | 9 | 0x0000 | 0x90090009 | PASS |
| 20 | PC -> FPGA | SET | 9 | 0x0000 | 0x90090009 | PASS |
| 21 | FPGA -> PC | SET_RESPONSE | 9 | 0x0000 | 0x90090009 | PASS |
| 22 | PC -> FPGA | QUERY | 10 | 0x0011 | 0x00000000 | PASS |
| 23 | FPGA -> PC | QUERY_RESPONSE | 10 | 0x0011 | 0x00000004 | PASS |

## Provenance

- Capture: `D:\MyFPGAProject\UDP\AI-work\reports\packet-audit\20260916-control-timeout\capture.pcapng`
- Protocol specification: `D:\MyFPGAProject\UDP\AI-work\modules\db500-udp-control\MODULE.md` (`aa1da10c64d6013f3f22d2153506cf423235b3da83340a6dd37ca3b7366378fb`)
- RTL source: `D:\MyFPGAProject\UDP\fpga\led\led.srcs\sources_1\new\ethernet\db500_udp_control.v` (`2a2cfea232c81ba1b9c08df63ac9221b1a8844fb3fd06f12cce5164d48252a36`)
