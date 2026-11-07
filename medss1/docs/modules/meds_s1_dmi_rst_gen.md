# `meds_s1_dmi_rst_gen`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | https://github.com/zakriakhan2 |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/debug/meds_s1_dmi_rst_gen.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_dmi_rst_gen.sv` — 1014 checks |

## Purpose

Generates a clean active-low reset with **asynchronous assert and synchronous release** (R-C4) that is asserted by either the external reset or a single-cycle hardreset pulse. It is required by the hardreset design: `dmihardreset` must reset the core-clock Bridge FSM and its synchronisers so a wedged handshake can always be recovered. It also exists so that no consuming module ever builds reset logic inline, which R-C4 forbids in a leaf module; they instantiate this and use `rst_n_o` as an ordinary reset.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | external async active-low reset |
| `hardreset_pulse_i` | in | 1 | request an extra reset | one `clk_i` cycle, already synchronised into this domain; must be glitch-free (it drives an asynchronous reset pin) |
| `rst_n_o` | out | 1 | combined active-low reset | asserts immediately; releases synchronously |

**Handshake:** none. **Latency:** assert is immediate; release takes exactly two `clk_i` edges after both inputs are inactive. **Reset state:** `rst_n_o` is low while `rst_ni` is low.

## Parameters

None.

## Behaviour

The assert condition `rst_ni & ~hardreset_pulse_i` drives the asynchronous reset of a two-flop release chain, so reset asserts the moment either input asserts, even for a pulse narrower than a clock period. When the condition clears, the chain shifts a 1 through two flops, releasing `rst_n_o` on a clock edge.

## Exceptions and errors

None.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **1014 checks**: asynchronous assert from both sources including a sub-cycle pulse, release in exactly two edges, release only on a clock edge, and a 500-cycle random stress against a reference model; it must always release once the inputs are quiet. | `verif/unit/tb_meds_s1_dmi_rst_gen.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- `hardreset_pulse_i` drives an asynchronous reset pin directly, so it must come straight from flops. A reset-domain-crossing lint tool may still flag it.

## Open questions

None. It stays in `rtl/debug/` while the DTM is its only user (the `rtl/common/` README keeps single-subsystem primitives next to their user); it moves when a second user appears.
