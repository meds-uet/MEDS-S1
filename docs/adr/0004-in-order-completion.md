# ADR-0004 — In-order completion for v1.0, MXIF port kept

| | |
|---|---|
| **Status** | Proposed |
| **Date** | 2026-11-08 |
| **Deciders** | _(tech lead to sign off)_ |
| **Reversibility** | Hard |

## Context

SPEC §9 describes a completion buffer with out-of-order completion. The core in `s1_core` is a
classic 5-stage pipeline: MUL and DIV run inside EX and stall it, so every instruction leaves EX in
program order and WB is the only commit point. INTERFACES I1 (MXIF) requires offload at the retire
pointer (R1.1) and the commit channel to exist in RTL at v1.0 (R1.3).

## Options considered

### A. Completion buffer, as in SPEC §9
Overlaps multi-cycle units with younger instructions. More logic, a second write path, and a
retire pointer to maintain.

### B. In-order completion, MXIF port removed
Smallest core, but MEDS-V cannot attach and R1.3 is broken.

### C. In-order completion, MXIF port kept and tied off
WB is the commit point, so offload at retire (R1.1) needs no extra logic.

## Decision

Option C. The core completes in order and WB commits. The `x_issue_*`/`x_commit_*`/`x_result_*`
ports exist on `s1_core`; `x_issue_valid_o` is tied to 0 until MEDS-V is attached.

## Consequences

**Good:** no completion buffer, one write path to architectural state, MXIF wires present (R1.3).
**Bad:** nothing overlaps a divide; the SPEC and this core differ on §9.
**We accept:** the stall cost of MUL/DIV in EX for v1.0.

## Revisit when

Profiling shows MUL/DIV stalls dominating a target workload, or MXIF-1.1 relaxes R1.1.
