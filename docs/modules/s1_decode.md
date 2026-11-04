# `s1_decode`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @Ammarahwakeel |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-02 |
| **Spec** | SPEC §7.1, §7.2, §9.2; INTERFACES.md §1.8 |
| **Source** | `rtl/core/s1_decode.sv` |
| **Testbench** | `verif/unit/tb_s1_decode.sv` — 573 checks |

## Purpose

The ID-stage instruction decoder. It turns one 32-bit instruction into a `decoded_op_t` control
bundle. It is a separate module so that decode is pure instruction-to-control logic: it reads no
register values, holds no pipeline state, and makes no privilege checks.

## Interface contract

Purely combinational. No clock, no reset, no state.

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `instr_i` | in | `ILEN` (32) | instruction | already C-expanded (SPEC §7.1); `instr_i[1:0] != 2'b11` decodes as illegal |
| `pc_i` | in | `XLEN` (64) | PC of `instr_i` | copied to `decoded_o.pc`; not used in decode |
| `decoded_o` | out | `decoded_op_t` | control bundle | every field driven on every path |

**Latency:** zero — combinational.
**Reset state:** none; outputs follow inputs.

**`decoded_o.illegal` means "illegal if nothing else accepts it", not "trap now".** With
`MXIF_EN=1` it is never set except for a still-compressed encoding; unrecognised encodings become
MXIF candidates instead.

**On an MXIF candidate, `rs1_re`, `rs2_re` and `rd_we` are all 1 as placeholders.** The decoder
cannot know which registers a coprocessor instruction uses. The consumer must take the real
write-back from `x_issue_writeback`; using `rd_we` would make an instruction without a scalar result
wait at retire for a result that never arrives (SPEC §9.2).

**`rd_we` is not gated by `rd == x0`**, and CSR instructions always set `rd_we=1`. The register file
discards `x0` writes. The CSR unit must apply the Zicsr side-effect rules itself: CSRRW/CSRRWI with
`rd=x0` do not read the CSR; CSRRS/CSRRC with `rs1=x0` and CSRRSI/CSRRCI with `uimm=0` do not write it.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `MXIF_EN` | `1'b1` | 0, 1 | 1: unrecognised encodings are MXIF candidates. 0: they are illegal. |

## Behaviour

All five immediates (I, S, B, U, J) are computed in parallel, sign-extended to 64 bits; each opcode
selects one. The Zicsr `uimm` is `rs1` zero-extended.

### Recognised encodings

Anything not listed here is unrecognised.

| Opcode | Instructions | `unit` | Legal only when |
|---|---|---|---|
| `LOAD` | LB LH LW LD LBU LHU LWU | LSU | `funct3 != 111` |
| `STORE` | SB SH SW SD | LSU | `funct3` ∈ {000–011} |
| `OP-IMM` | ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI | ALU | shifts: `instr[31:26]` = `000000` (SLLI, SRLI) or `010000` (SRAI) |
| `OP-IMM-32` | ADDIW SLLIW SRLIW SRAIW | ALU | `funct3` ∈ {000, 001, 101}; shifts: `instr[31:25]` = `0000000` or `0100000` (SRAIW only) |
| `OP` | ADD SUB SLL SLT SLTU XOR SRL SRA OR AND | ALU | `funct7 = 0000000`, or `0100000` with `funct3` ∈ {000, 101} |
| `OP` | MUL MULH MULHSU MULHU · DIV DIVU REM REMU | MUL · DIV | `funct7 = 0000001` |
| `OP-32` | ADDW SUBW SLLW SRLW SRAW | ALU | `funct7 = 0000000` with `funct3` ∈ {000, 001, 101}, or `0100000` with `funct3` ∈ {000, 101} |
| `OP-32` | MULW · DIVW DIVUW REMW REMUW | MUL · DIV | `funct7 = 0000001`, `funct3` ∈ {000, 100–111} |
| `LUI`, `AUIPC` | LUI AUIPC | ALU | always |
| `JAL` | JAL | ALU | always |
| `JALR` | JALR | ALU | `funct3 = 000` |
| `BRANCH` | BEQ BNE BLT BGE BLTU BGEU | ALU | `funct3 ∉ {010, 011}` |
| `AMO` | LR SC AMOSWAP AMOADD AMOXOR AMOAND AMOOR AMOMIN AMOMAX AMOMINU AMOMAXU (.W, .D) | LSU | `funct3` ∈ {010, 011}; `funct7[6:2]` a defined op; LR: `rs2 = 0` |
| `MISC-MEM` | FENCE FENCE.I | NONE | `funct3` ∈ {000, 001}; `rs1`, `rd` and the other immediate bits are ignored |
| `MISC-MEM` | CBO.INVAL CBO.CLEAN CBO.FLUSH CBO.ZERO | LSU | `funct3 = 010`, `rd = 0`, `instr[31:20]` ∈ {0, 1, 2, 4} |
| `SYSTEM` | ECALL EBREAK MRET WFI | NONE | `funct3 = 000`, `rs1 = rd = 0`, `instr[31:20]` an exact match |
| `SYSTEM` | CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI | CSR | `funct3[1:0] != 00` |

### Operand routing

| Instruction | `rs1_re` | `rs2_re` | `rd_we` | `op1_is_pc` | `op2_is_imm` | `imm` |
|---|---|---|---|---|---|---|
| OP, OP-32 (ALU, MUL, DIV) | 1 | 1 | 1 | 0 | 0 | — |
| OP-IMM, OP-IMM-32 | 1 | 0 | 1 | 0 | 1 | I |
| LUI (`alu_op=ALU_PASS_B`) | 0 | 0 | 1 | 0 | 1 | U |
| AUIPC | 0 | 0 | 1 | 1 | 1 | U |
| JAL (`is_jal`) | 0 | 0 | 1 | 1 | 1 | J |
| JALR (`is_jalr`) | 1 | 0 | 1 | 0 | 1 | I |
| BRANCH (`is_branch`, `cmp_op`) | 1 | 1 | 0 | 0 | 0 | B |
| LOAD (`is_load`) | 1 | 0 | 1 | 0 | 1 | I |
| STORE (`is_store`) | 1 | 1 | 0 | 0 | 1 | S |
| LR | 1 | 0 | 1 | 0 | 0 | — |
| SC, AMO* | 1 | 1 | 1 | 0 | 0 | — |
| CBO.* | 1 | 0 | 0 | 0 | 0 | — |
| FENCE, FENCE.I, ECALL, EBREAK, MRET, WFI | 0 | 0 | 0 | 0 | 0 | — |
| CSRR{W,S,C} | 1 | 0 | 1 | 0 | 0 | — |
| CSRR{W,S,C}I (`csr_imm`) | 0 | 0 | 1 | 0 | 0 | `uimm` |
| MXIF candidate | 1 | 1 | 1 | 0 | 0 | — |

For JAL and JALR, the ALU operands give the target; the link value `pc+4` is not encoded in the
bundle. AMO and CBO addresses are `rs1` with no offset.

### Unrecognised encodings

The opcode case starts from a default bundle with `illegal=1`; each recognised encoding clears it.
If `illegal` is still 1 afterwards, the bundle is reset to the default, so no partly decoded field
survives. Then:

- `MXIF_EN=1`: `unit=UNIT_MXIF`, `mxif_candidate=1`, `illegal=0` (SPEC §7.2). This covers unknown
  opcodes, including OP-V, LOAD-FP and STORE-FP (INTERFACES.md §1.8), and reserved encodings under
  known opcodes.
- `MXIF_EN=0`: `unit=UNIT_NONE`, `illegal=1`.

Finally, if `instr_i[1:0] != 2'b11` the bundle is reset to the illegal default regardless of
`MXIF_EN`.

## Exceptions and errors

None. Illegality is reported in `decoded_o.illegal`; the trap is raised downstream.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean on all four configs | `make lint CONFIG=<name>` |
| Unit test | **573 checks** — every instruction in the table above, 9 pseudo-instructions, reserved-encoding spot checks under both `MXIF_EN` values, compressed-encoding guard | `make test-unit TB=s1_decode` |
| Co-simulation | not yet | |
| Formal | not yet | |

## Known limitations

- **No per-config ISA gating.** The decoder accepts the union of all configs' ISAs (SPEC §5.3):
  A, Zicsr, Zifencei, Zicbom and Zicboz are recognised on every config, including those whose
  ISA string excludes them. `MXIF_EN` is the only configuration input.
- **SRET, DRET and SFENCE.VMA are not decoded.** The core is M+U only (`misa.S` reads 0, SPEC
  §10.1) and has no Debug Mode yet, so they are unrecognised encodings like any other. They cannot
  be decoded without a privilege check, and nothing downstream performs one at retire. They return
  with S-mode and the debug module, gated on the privilege or Debug state.
- **MRET is decoded in every privilege level.** The decoder has no privilege input; EX must raise
  illegal-instruction for MRET when `priv_i != PRIV_M`.
- **No opcode routing from `soc.yaml`.** SPEC §7.2 allows `soc.yaml` to route opcodes to the
  coprocessor; the decoder only routes encodings it does not recognise.
- **Encodings longer than 32 bits** (`instr_i[4:2] = 111`) are treated as unrecognised and become
  MXIF candidates when `MXIF_EN=1`.
- **MXIF candidates over-report register use.** Every MXIF candidate has `rs1_re`, `rs2_re` and
  `rd_we` set, because the decoder cannot know which registers a coprocessor instruction uses. The
  hazard logic therefore stalls each one on RAW hazards against `rs1`, `rs2` and `rd` even when the
  instruction ignores them. This costs nothing with `MXIF_EN=0`, which produces no candidates. With a
  coprocessor attached, the cost is stalls on unrelated hazards until the decoder is given the
  coprocessor's real operand use.

## Open questions

None.
