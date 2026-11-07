# `<extension-name>`

| | |
|---|---|
| **Status** | experimental / stable / deprecated |
| **Owner** | @github-handle |
| **Opcode space** | custom-N, funct3=…, funct7=… |
| **Registry rows** | REGISTRY.md §1 §2 |
| **Coupling** | MXIF (tight) — see SPEC §21 before assuming this |

## Why this extension exists

What is slow or impossible without it, and the measurement that shows it. "It seemed useful" is not
an answer — SPEC §33.4 requires the baseline before the design.

## Instructions

### `<mnemonic> rd, rs1, rs2`

| | |
|---|---|
| **Encoding** | `funct7[6:0] rs2[4:0] rs1[4:0] funct3[2:0] rd[4:0] opcode[6:0]` |
| **Semantics** | precise description, including edge cases |
| **Latency** | cycles, and whether pipelined |
| **Exceptions** | which, and when — remember R1.9: none after `x_norollback` |
| **`fence`** | does this instruction have memory side effects? |

## Checklist status

- [ ] 1. `<name>.opcodes` in riscv-opcodes format
- [ ] 2. Allocation row in `extensions/REGISTRY.md`
- [ ] 3. Golden-reference model in `model/`
- [ ] 4. Toolchain path in `sw/`
- [ ] 5. RISCOF tests in `tests/`
- [ ] 6. CSR allocation, if any
- [ ] 7. This README complete
