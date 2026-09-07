# Open questions

| ID | Question | Why it matters | Owner / next evidence | State |
|---|---|---|---|---|
| OQ-001 | What is the assembled board revision and which core/MCON/AFE revisions are fitted? | Constraints and acceptance apply to a specific hardware revision. | Confirm board markings and BOM/PCB revision. | OPEN |
| OQ-002 | Which exact MGT116 TX/RX lane, polarity, and reference-clock input connect to the M88E1111 SGMII port? | Required before creating the GTX constraints and PCS/PMA configuration. | PCB net export or reviewed connector pin map. | OPEN |
| OQ-003 | What are the M88E1111 strap settings, MDIO address, reset timing, and reference-clock frequency? | Required to configure and verify the PHY safely. | PHY sheet plus M88E1111 data sheet and board observation. | OPEN |
| OQ-004 | What MAC address, board IP address, UDP port, and packet checksum policy are required by the deployed DB500 protocol? | Required for an interoperable host and FPGA demo. | Read the protocol document after its Word lock is released; reconcile with packet capture if needed. | OPEN |
| OQ-005 | What is the exact Xilinx IP configuration and license availability for SGMII plus Ethernet MAC in Vivado 2021.1? | Determines the reproducible implementation path. | Create configuration only after OQ-002 and OQ-003 are closed. | OPEN |
