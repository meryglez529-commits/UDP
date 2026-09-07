# DB500 UDP FPGA Bring-up

This repository prepares a reproducible FPGA bring-up path for a DB500-class
scanning-control platform. Its first product is a safe UDP communication demo:
device discovery, read-only status, and a demonstrably correct UDP reply path.

The repository has two ownership roots:

- fpga/ contains authored, buildable FPGA sources and constraints.
- AI-work/ contains plans, execution records, acceptance evidence, and the
  bring-up handoff. It is the audit trail for every stage.

The original hardware and protocol files remain in the repository root. The
Word protocol document is currently open by another application, so it is
registered as an input but will be added to Git only after its lock is released.

Current board status is recorded in
AI-work/bringup/db500-k7/udp-bringup-20260907/STATUS.md.
