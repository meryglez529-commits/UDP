# Demo architecture

## Minimal path

Host test script
-> RJ45
-> M88E1111 PHY
-> SGMII serial link
-> Xilinx GTX plus SGMII PCS/PMA configuration
-> Ethernet MAC
-> ARP and IPv4/UDP receive parser
-> deterministic echo/status responder
-> UDP/IP/Ethernet transmit formatter
-> host packet capture and oracle.

The Ethernet MAC owns Ethernet FCS generation/checking. The FPGA transport
logic validates Ethernet type, IPv4 header length, destination address, UDP
length, and configured port; it implements the IPv4 header checksum. UDP
checksum behavior is selected only after the protocol contract is confirmed.

## Canonical dependencies

| Official path | Purpose | Shared with product? | Risk |
|---|---|---:|---|
| fpga/boards/db500-k7/constraints/ | Reviewed board, GTX, PHY-management, and clock constraints | YES | High: all pins and clocks are currently open |
| fpga/common/clock_reset/ | Reset sequencing and declared clock-domain boundaries | YES | High: physical input frequency unresolved |
| fpga/boards/db500-k7/ip/sgmii_ethernet/ | Vendor PCS/PMA and Ethernet MAC configuration | YES | High: lane and PHY facts unresolved |
| fpga/common/udp_transport/ | ARP/IP/UDP packet pipeline | YES | Medium: protocol settings unresolved |
| fpga/demos/udp-smoke/ | Test-only top and host test procedure | NO | Low: excluded from product |

## Clock/reset/CDC and physical mapping

The SGMII transceiver channel, RX/TX polarity, selected reference clock,
management GPIO sites, and PHY reset behavior are open contract facts. The
demo does not create an XDC, an IP configuration, or crossing logic until they
are confirmed. The design will document each clock domain and every CDC before
simulation or implementation.

## Verification plan

- Simulation: self-checking packets for ARP reply, valid UDP response, length
  boundaries, malformed inputs, and no response to excluded commands.
- Build: source-driven synthesis, implementation, DRC, timing, candidate image
  identity, and versioned IP configuration.
- Board: after explicit authorization, configure only the exact candidate
  image, verify PHY status and SGMII lock, run a bounded host test, capture
  packets, then return the board to the documented safe state.
