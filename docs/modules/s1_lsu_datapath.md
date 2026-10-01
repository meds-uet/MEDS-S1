# `s1_lsu_datapath`

| | |
|---|---|
| **Status** | WIP -- R-02 |
| **Owner** | R-02 |
| **Backup** | _(assign)_ |
| **Project** | R-02 -- WP6 |
| **Spec** | SPEC sections 11 and 14 |
| **Source** | `rtl/core/s1_lsu_datapath.sv` |
| **Testbench** | `verif/unit/tb_s1_lsu_controller.sv` |

## Purpose

The combinational LSU datapath converts a decoded scalar memory operation into byte enables and lane-aligned store data, and converts an XLEN-wide memory response into a sign-extended or zero-extended load result. It also reports supported transfer sizes and natural-alignment validity. The controller owns sequencing; this module owns width and byte-lane transformations.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `addr_offset_i` | in | `3` | byte offset | selects lanes in the XLEN memory beat; the controller retains the full address |
| `store_data_i` | in | `XLEN` | source store value | only the selected transfer width is used |
| `size_i` | in | 3 | log2 transfer size | `0` byte, `1` halfword, `2` word, `3` doubleword |
| `load_unsigned_i` | in | 1 | load extension mode | zero-extend when high; sign-extend when low |
| `response_data_i` | in | `XLEN` | memory response beat | interpreted as little-endian byte lanes |
| `size_valid_o` | out | 1 | supported-size result | low for unsupported sizes |
| `alignment_ok_o` | out | 1 | natural-alignment result | byte always valid; larger transfers require natural alignment |
| `mem_be_o` | out | `XLEN/8` | store byte enables | transfer mask shifted by address lane offset |
| `mem_wdata_o` | out | `XLEN` | lane-aligned store data | upper bits outside the transfer width are zero before shifting, except SD |
| `load_data_o` | out | `XLEN` | extended load result | valid combinationally from `response_data_i` |

**Latency:** zero cycles; purely combinational.

**Reset state:** none; the module has no clock or reset.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `XLEN` | 64 | 64 for the current platform | operand, response, and output width |

## Behaviour

Natural alignment requirements are:

- byte: any address
- halfword: `addr_i[0] == 0`
- word: `addr_i[1:0] == 0`
- doubleword: `addr_i[2:0] == 0`

Store values are masked to 8, 16, 32, or 64 bits before lane shifting. This prevents upper register bits from leaking into `mem_wdata_o` for SB, SH, and SW. The controller and downstream memory must still honor `mem_be_o`.

Loads select the requested bytes after shifting the response by the address offset. LB/LH/LW sign-extend when `load_unsigned_i` is low; LBU/LHU/LWU zero-extend. LD returns the selected XLEN-wide value.

## Exceptions and errors

The datapath does not raise architectural exceptions. It reports `size_valid_o` and `alignment_ok_o`; the controller converts failures into load/store misaligned faults.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | direct Verilator lint and ModelSim compile |
| Unit test | 172 checks | `verif/unit/tb_s1_lsu_controller.sv` |
| Co-simulation | not applicable yet | |
| Formal | not yet | |

Coverage includes all load widths, signed/unsigned behavior, negative LH/LW values, dirty upper-bit SB/SH/SW stores, SD, and alignment failures.

## Known limitations

- XLEN=64 is the validated configuration.
- Misaligned accesses are rejected rather than split into multiple transactions.
- PMA, PMP, store-buffer forwarding, and atomics are outside this combinational datapath.

## Open questions

- Whether future cache or store-buffer interfaces need a wider internal lane representation than the current XLEN-wide MEM-REQ payload.
