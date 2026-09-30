# `s1_decode`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @Ammarahwakeel |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-02 (decode stage), tested by M-07 |
| **Spec** | SPEC §6, §7.1, §7.2, §7.4/§14/§15 (Zicbom issues in MEM/LSU/D$, not here), §8 (consumed by, not implemented by, this module), §9.1, §9.2, §10.2, §11, §13 (DRET), §19 (MXIF) |
| **Source** | `rtl/core/s1_decode.sv` |
| **Testbench** | `verif/unit/tb_s1_decode.sv` — 372 checks |

## Purpose

The instruction decoder for the ID pipeline stage. It is purely combinational and turns one 32-bit,
already-C-expanded instruction into a `decoded_op_t` control bundle. It exists as a separate module
because SPEC §7.2 describes ID-stage decode, regfile read, hazard detection, forwarding-source
selection, and completion-buffer allocation as one job, and this RTL deliberately splits that job
into three modules so each stays small enough to read in one sitting: this module turns an
instruction into control signals and never sees a register value (forwarded or otherwise);
`s1_regfile.sv` owns register-file reads and the four-source forwarding mux (SPEC §8.1);
`s1_completion_buffer.sv` owns CB allocation and the hazard/stall table (SPEC §8.2), which needs
pipeline state this module intentionally is not given. This module also does not check privilege —
CSR/privilege legality belongs to `s1_csr.sv`'s generated access-control matrix (SPEC §10.2), and
MRET/SRET/WFI legality at retire belongs to the privilege FSM (SPEC §10.1). `illegal` here is only
ever raised for encodings that are illegal in every privilege level and CSR mapping.

## Interface contract

Purely combinational. No clock, no reset, no state.

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `instr_i` | in | `ILEN` (32) | Instruction encoding | must already be a 32-bit, C-expanded instruction; `instr_i[1:0] == 2'b11` is enforced structurally — anything else forces `illegal=1` regardless of what the opcode case decided |
| `pc_i` | in | `XLEN` (64) | Program counter of this instruction | passed straight through to `decoded_o.pc` for diagnostics only; this module does **not** compute JAL/AUIPC targets from it — it just asserts `op1_is_pc` so the downstream ALU (SPEC §7.3) selects PC as an operand |
| `decoded_o` | out | `decoded_op_t` | Decoded control bundle (~30 fields) | every field is driven on every path (default-first, no inferred latches); `illegal` defaults to 1 and a case arm must actively clear it |

**Handshake:** none — no `valid`/`ready`, purely functional of the current inputs.
**Latency:** zero — combinational.
**Backpressure:** not applicable; there is no state to stall.
**Reset state:** none; outputs follow inputs.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `MXIF_EN` | `1'b1` | 0, 1 | Whether a coprocessor is attached (soc.yaml `MXIF_EN`). With `MXIF_EN=1`, an unrecognised opcode is marked `unit=UNIT_MXIF`, `mxif_candidate=1`, `illegal=0` (offered to the coprocessor). With `MXIF_EN=0`, the same encoding becomes `illegal=1`, `unit=UNIT_NONE` instead, since there is no coprocessor to ask (SPEC §7.2 design note). |

## Behaviour

### Field extraction

| Signal | Bits | Width | Purpose |
|---|---|---|---|
| `opcode` | `instr_i[6:0]` | 7 | selects instruction family (14 recognised opcodes) |
| `funct3` | `instr_i[14:12]` | 3 | secondary selector within family |
| `funct7` | `instr_i[31:25]` | 7 | tertiary selector — picks the ALU/ALT/MULDIV variant on `OP` and `OP-32` |
| `rd_f` | `instr_i[11:7]` | 5 | destination register field |
| `rs1_f` | `instr_i[19:15]` | 5 | source register 1 field |
| `rs2_f` | `instr_i[24:20]` | 5 | source register 2 field |

### Immediate pre-computation

All five formats are computed in parallel, sign-extended to `XLEN` (64), regardless of opcode; the
case arm for each opcode picks the one it needs.

| Immediate | Format | Bit source | Consumed by |
|---|---|---|---|
| `imm_i` | I-type | `sext(instr[31:20])` | `OP-IMM`, `OP-IMM-32`, `LOAD`, `JALR`; also reused (zero-extended, not sign-extended) as CSR uimm |
| `imm_s` | S-type | `sext({instr[31:25], instr[11:7]})` | `STORE` |
| `imm_b` | B-type | `sext({instr[31], instr[7], instr[30:25], instr[11:8], 0})` | `BRANCH` |
| `imm_u` | U-type | `{sext(instr[31:12]), 12'b0}` | `LUI`, `AUIPC` |
| `imm_j` | J-type | `sext({instr[31], instr[19:12], instr[20], instr[30:21], 0})` | `JAL` |

### Opcode families

| Opcode (binary) | Mnemonics | Discriminator | `unit` | Notes |
|---|---|---|---|---|
| `OP_LOAD` (`0000011`) | LB LH LW LBU LHU LWU LD | `funct3` | `UNIT_LSU` | `funct3=111` reserved |
| `OP_STORE` (`0100011`) | SB SH SW SD | `funct3` | `UNIT_LSU` | `funct3=111` reserved |
| `OP_IMM` (`0010011`) | ADDI SLLI SLTI SLTIU XORI SRLI SRAI ORI ANDI | `funct3`; `instr[30]` picks SRAI vs SRLI | `UNIT_ALU` | shamt upper bits (`imm_i[11:6]`) not validated — see Known limitations |
| `OP_IMM_32` (`0011011`) | ADDIW SLLIW SRLIW SRAIW | `funct3`; `instr[30]` picks SRAIW vs SRLIW | `UNIT_ALU` | `funct3` 010/011/100/110/111 reserved |
| `OP_AUIPC` (`0010111`) | AUIPC | — | `UNIT_ALU` | `op1_is_pc=1`, `imm=imm_u` |
| `OP_LUI` (`0110111`) | LUI | — | `UNIT_ALU` | `alu_op=ALU_PASS_B`, `imm=imm_u` |
| `OP_OP` (`0110011`) | ADD SUB SLL SLT SLTU XOR SRL SRA OR AND · MUL MULH MULHSU MULHU DIV DIVU REM REMU | `funct7` (`0000000` base / `0100000` alt / `0000001` muldiv) + `funct3` | `UNIT_ALU` / `UNIT_MUL` / `UNIT_DIV` | `FUNCT7_ALT` only legal for `funct3` 000 (SUB) and 101 (SRA); any other `funct3` under `FUNCT7_ALT` reserved |
| `OP_OP_32` (`0111011`) | ADDW SUBW SLLW SRLW SRAW · MULW DIVW DIVUW REMW REMUW | `funct7` + `funct3` | `UNIT_ALU` / `UNIT_MUL` / `UNIT_DIV` | no MULHW/MULHSUW/MULHUW — `funct3` 001/010/011 under `FUNCT7_MULDIV` reserved |
| `OP_BRANCH` (`1100011`) | BEQ BNE BLT BGE BLTU BGEU | `funct3` | `UNIT_ALU` (comparator) | `funct3` 010/011 reserved; `rs1`/`rs2` read raw, never through the ALU-imm mux |
| `OP_JAL` (`1101111`) | JAL | — | `UNIT_ALU` | `op1_is_pc=1`, `imm=imm_j`, `is_jal=1` |
| `OP_JALR` (`1100111`) | JALR | `funct3==000` | `UNIT_ALU` | any other `funct3` reserved |
| `OP_AMO` (`0101111`) | LR SC AMOSWAP AMOADD AMOXOR AMOAND AMOOR AMOMIN AMOMAX AMOMINU AMOMAXU (.W/.D) | `funct3` (010=W/011=D) then `funct7[6:2]` | `UNIT_LSU` | address = `rs1` only, no offset; `LR` excludes `rs2_re` and requires `rs2==0` (RVA; `rs2!=0` is reserved); any other `funct3` (byte/half width) reserved |
| `OP_MISC_MEM` (`0001111`) | FENCE, FENCE.I | `funct3==000/001` | `UNIT_NONE` | `rs1`/`rd` are reserved fields (riscv-opcodes `rv_i::fence`, `rv_zifencei::fence.i`), not fixed to 0 — this decoder ignores their value, per base-implementation forward-compatibility rules |
| `OP_MISC_MEM` (`0001111`) | CBO.INVAL CBO.CLEAN CBO.FLUSH CBO.ZERO (Zicbom/Zicboz) | `funct3==010`, then `instr[31:20]` (0/1/2/4) | `UNIT_LSU` | address = `rs1` only, no offset, same convention as AMO; `rd` **is** fixed to 0 here (riscv-opcodes `rv_zicbo`: `11..7=0`) — unlike FENCE, a nonzero `rd` is reserved, not ignored; any other `funct3` or `instr[31:20]` value under `funct3==010` reserved |
| `OP_SYSTEM` (`1110011`) | ECALL EBREAK SRET MRET WFI DRET SFENCE.VMA · CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI | `funct3==000` → `instr[31:20]` fixed pattern, or `funct7==0001001` (SFENCE.VMA, real `rs1`/`rs2` operands, `rd` fixed to 0); any other `funct3` → Zicsr via `funct3[1:0]` | `UNIT_NONE` / `UNIT_CSR` | ECALL/EBREAK/SRET/MRET/WFI/DRET all require `rs1==0 && rd==0` (fixed by their encoding, unlike FENCE); Zicsr immediate forms (`csr_imm=funct3[2]`) set `rs1_re=0` even though `rs1_f` still carries the zero-extended 5-bit uimm into `decoded_o.imm` |
| unrecognised opcode | — (MXIF candidate) | — | `UNIT_MXIF` / `UNIT_NONE` | see MXIF row below |

### Design rules (not opcode-specific)

- **Default-first, fail-closed.** `illegal` (and `unit=UNIT_NONE`, `rs1_re=rs2_re=rd_we=0`, etc.) is
  set before the `unique case` runs; each legal encoding must explicitly clear `illegal`. A forgotten
  case arm or a wrong funct3/funct7 guard defaults to illegal rather than silently executing.
- **MXIF candidate marking (SPEC §7.2 design note).** Any opcode not in the table above — including
  the F/D and V encodings SPEC §4.2 calls out (`LOAD-FP`/`STORE-FP`/`OP-V`), since RV64IMAC implements
  neither F nor V — falls into the same `default:` arm. `MXIF_EN=1` → `unit=UNIT_MXIF`,
  `mxif_candidate=1`, `illegal=0`. `MXIF_EN=0` → `unit=UNIT_NONE`, `illegal=1`.
- **Compressed-instruction guard (SPEC §7.1).** A final, unconditional check forces `illegal=1` if
  `instr_i[1:0] != 2'b11`, overriding whatever the opcode case decided. This is a structural leak
  guard, not an ISA rule — 16-bit encodings are expanded to 32-bit before this module ever sees them.

## Exceptions and errors

None. This module cannot fault. An instruction may be `illegal` (reserved funct3/funct7, or an
unknown opcode with `MXIF_EN=0`), but that is signaled via `decoded_o.illegal`, not an exception.
Privilege checks (CSR access, MRET/SRET/WFI legality) are performed downstream, not here.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | not independently verified against an artifact in this review | `make lint TB=s1_decode` |
| Unit test | **372 checks** — 101 named instructions (37 RV64I + 12 RV64I+ + 13 RVM + 11 RV64A + 15 SYSTEM + 4 Zicbom/Zicboz + 9 pseudo-instruction spot checks), every reserved funct3/funct7 pair adjacent to its legal neighbour, both `MXIF_EN` configurations, the compressed-instruction guard | `verif/unit/tb_s1_decode.sv` |
| Co-simulation | not independently verified against an artifact in this review | |
| Formal | not yet | candidate for T-07 |

## Known limitations

- **`rs1_re`/`rs2_re`/`rd_we` can stay `1` on illegal encodings** in the MXIF-default and AMO-reserved-width paths; harmless if consumers gate on `illegal`, but not tested by `tb_s1_decode` on those paths.
- **RV64C (Compressed) is not tested here by design.** C-form instructions are expanded at the IF/ID
  boundary; this decoder never sees them. Every "32-bit equivalent" in the compressed table is already
  covered by the RV64I/RV64I+/RVM sections (e.g. `c.addi`→`addi`, `c.lw`→`lw`, `c.jal`→`jal`).
- **No Zbb bit-manipulation.** Not decoded anywhere in the opcode case; out of scope for v1.0.
- **No per-config ISA-extension gating.** This decoder accepts RV64A, RV64M, Zicsr, Zifencei, Zicbom
  and Zicboz encodings unconditionally, regardless of `soc.yaml`'s ISA string for the active config.
  S1-Nano's ISA is RV64IMC (no A, no Zicsr/Zifencei, no Zicbom/Zicboz per SPEC §5.3), so on that
  config this decoder currently accepts instructions its own ISA string says it shouldn't. `MXIF_EN`
  is the only config-conditional legality check today. Pre-existing gap (predates the Zicbom/Zicboz
  addition), not something introduced by adding CBO support -- flagged here rather than silently
  carried forward.
- **`x0` is not special-cased.** Reads of `rs1`/`rs2`==`x0` and writes to `rd`==`x0` are decoded
  normally (`rd_we` can be `1` for `rd==0`, e.g. on `nop`/`j`/`csrw`); the regfile is responsible for
  discarding writes to `x0`, not this module.

## Open questions

- None for now, reviewer or future contricutors can add it.
