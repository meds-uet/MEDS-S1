# `<module_name>`

| | |
|---|---|
| **Status** | SKELETON / WIP / COMPLETE |
| **Owner** | @github-handle |
| **Backup** | @github-handle |
| **Project** | catalogue id, e.g. T-02 |
| **Spec** | SPEC §x.y, INTERFACES.md §z |
| **Source** | `rtl/<subsystem>/<module_name>.sv` |
| **Testbench** | `verif/unit/tb_<module_name>.sv` |

## Purpose

One paragraph: what this module does and why it exists as a separate module.

## Interface contract

What a *caller* may assume, and what this module assumes of *them*. This is the part that matters —
ports alone are not a contract.

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert |
| … | | | | |

**Handshake:** e.g. `valid`/`ready`, `valid` does not depend combinationally on `ready` (R-C10).
**Latency:** e.g. one cycle, registered.
**Backpressure:** what happens when the consumer stalls.
**Reset state:** what the outputs are at reset.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| | | | |

## Behaviour

State machine, timing, corner cases. A diagram if it earns its place.

## Exceptions and errors

What this module can raise, when, and what the caller must do about it.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | | |
| Unit test | `n` checks | `verif/unit/tb_<module>.sv` |
| Co-simulation | covered / not applicable | |
| Formal | | |

## Known limitations

Things a reader would otherwise waste time discovering. A stated limitation is a decision; an
unstated one is a bug.

## Open questions

Anything the next person should resolve, with your current thinking.
