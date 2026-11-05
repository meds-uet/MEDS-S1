# `s1_rvc_expand`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | Ayesha Anwar (@ayeshaanwaar05) |
| **Backup** | _(assign at the T-01 design review)_ |
| **Project** | T-01 (core frontend) |
| **Spec** | SPEC §7.1 (C expansion at the IF/ID boundary), SCOPE_CONTRACT §3 (no compressed MXIF channel); RISC-V Unprivileged ISA, "C" chapter, RV64C column |
| **Source** | `rtl/core/s1_rvc_expand.sv` |
| **Testbench** | `verif/unit/tb_s1_rvc_expand.sv`: 131 177 checks, exhaustive |

## Purpose

Turns one 16-bit RV64C parcel into the 32-bit instruction it abbreviates, or flags it as reserved.
SPEC §7.1 puts expansion at the IF/ID boundary so that decode, the completion buffer and MXIF only
ever see 32-bit encodings. That choice lets MXIF-1.0 omit CV-X-IF's compressed channel. It is a
separate module from `s1_fetch` because it is a pure function of 16 bits. That makes it the one
block in the frontend that can be verified exhaustively, and it keeps the decoding tables out of
the fetch control logic.

## Interface contract

Purely combinational. No clock, no reset, no state.

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `instr_i` | in | `CLEN` (16) | one instruction parcel | any value; `[1:0] == 2'b11` is not a compressed instruction |
| `instr_o` | out | `ILEN` (32) | expanded encoding | meaningful only when `illegal_o == 0`; **all-zero when `illegal_o == 1`** |
| `illegal_o` | out | 1 | reserved encoding | also 1 for `instr_i[1:0] == 2'b11` |

**Latency:** zero, combinational.
**Reset state:** none; outputs follow inputs.

The caller decides what an illegal parcel means. `s1_fetch` turns it into an
`EXC_ILLEGAL_INSTR` with `mtval` = the parcel. No coprocessor can rescue it, because MXIF never
sees 16-bit encodings.

## Parameters

None. `CLEN` and `ILEN` come from `s1_pkg` and are fixed by the ISA.

## Behaviour

One `unique case` on `{quadrant, funct3}`, with defaults assigned before it (R-C3). The immediate
for each field layout is built once, in its own `assign`, so every case arm is a single
concatenation that can be checked against the spec table by eye.

### Illegal (reserved) encodings

Only encodings the RV64C tables call *reserved* raise `illegal_o`:

| Encoding | Why reserved |
|---|---|
| `C.ADDI4SPN` with `nzuimm = 0` | includes the all-zero parcel, which the ISA defines as illegal |
| quadrant 0, `funct3 = 100` | reserved (Zcb would use it; not in scope) |
| `C.ADDIW` with `rd = x0` | reserved |
| `C.ADDI16SP` with `nzimm = 0` | reserved |
| `C.LUI` with `nzimm = 0` | reserved |
| quadrant 1, `funct6 = 100111`, `funct2 ∈ {10, 11}` | reserved |
| `C.LWSP` / `C.LDSP` with `rd = x0` | reserved |
| `C.JR` with `rs1 = x0` | reserved |
| `instr_i[1:0] == 2'b11` | not a compressed instruction |

### HINTs are legal

`C.NOP` with a non-zero immediate, `C.ADDI` with `rd = x0` or `imm = 0`, `C.LI`/`C.LUI`/`C.MV`/`C.ADD`/`C.SLLI`
with `rd = x0`, and the RV64 shift forms with `shamt = 0` are HINTs. They expand to their base
instruction like any other encoding. Calling them illegal would trap programs that the ISA says must
run. The first version of this module got `C.LUI rd=x0` wrong in exactly this way.

### `C.FLD`/`C.FSD`/`C.FLDSP`/`C.FSDSP` expand, even without D

S1-Core has no D extension, yet these four expand to `FLD`/`FSD` rather than being flagged here.
Decode does not reject unknown opcodes. It forwards them to MXIF and raises illegal-instruction only
if no coprocessor accepts (SPEC §7.2). So today the trap still happens, one stage later, with the
same `mtval`, because `s1_fetch` carries the original 16 bits. If an FP coprocessor is ever attached,
it gets the compressed forms for free, which is the retrofit INTERFACES.md §1.8 item 6 asks us to
avoid making painful.

## Exceptions and errors

None raised directly; `illegal_o` is information for the caller.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, no waivers | `make lint` |
| Unit test | **131 177 checks**: all 65 536 inputs against the reference model (`illegal_o` and `instr_o` each), 44 assembler-derived vectors, 10 named reserved encodings, 6 named HINTs | `verif/unit/tb_s1_rvc_expand.sv` |
| Reference model | `verif/common/rvc_golden.svh`, written in a different style (integer immediates and generic format encoders). **Cross-checked once, exhaustively, against GNU `objdump`** on all 49 152 compressed encodings: zero semantic differences. The one intended disagreement is `0x6101` (`C.ADDI16SP` with `nzimm = 0`), which objdump decodes leniently and the spec reserves | procedure below |
| Mutation | re-injecting the first version's `C.LDSP` offset bug (bit 8 dropped) fails the testbench on the first affected encoding | |
| Co-simulation | covered indirectly once R-05 lands | |
| Formal | not needed; the input space is enumerated | |

To repeat the objdump cross-check: dump `rvc_golden()` for every parcel, write the compressed
parcels and the model's expansions into two raw binaries at matching addresses, disassemble both
with `riscv64-unknown-elf-objdump -D -b binary -m riscv:rv64 -M numeric`, and compare after
normalising objdump's aliases (`mv`, `li`, `nop`, `c.*` HINT spellings).

## Known limitations

- RV64C only. The RV32-only slots (`C.JAL`, `C.FLW`, `C.FSW` and friends) are the RV64 `C.ADDIW`,
  `C.LD`, `C.SD` here, as the ISA requires.
- No Zcb, Zcmp, Zcmt or Zcmop. Their encodings are either reserved here or alias RV64C instructions.

## Open questions

None for this module. The policy questions it depends on (`C.F*` expansion, no compressed MXIF
channel) are recorded above and in SCOPE_CONTRACT §3.
