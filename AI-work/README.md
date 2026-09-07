# Bring-up evidence and process records

Every FPGA work item uses the following state transition:

1. Plan: define the decision question, scope, safe defaults, acceptance
   criteria, dependencies, and authorization boundary before execution.
2. Execute: record the exact command or board procedure, tool version, inputs,
   outputs, and observed result.
3. Accept: compare the recorded result against the predeclared criterion; mark
   the item accepted, failed, blocked, or pending without substituting a build
   result for a board result.

Each accepted stage is committed to Git. Generated artifacts are ignored unless
they are explicitly released; reviewed Markdown records remain tracked.

The active unit is
bringup/db500-k7/udp-bringup-20260907/.
