# `meds_s1_clint`

| | |
|---|---|
| **Status** | IMPLEMENTED — T-05 |
| **Project** | T-05 (WP9) |
| **Spec** | SPEC §24, INTERFACES.md §6 (I7), ADR-0005 |
| **Source** | `rtl/peripherals/meds_s1_clint.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_clint.sv` |

## Purpose

Core-local interrupts: the software interrupt (`msip`) and timer interrupt (`mtime` / `mtimecmp`) required for RISC-V machine-mode interrupt handling.

MEDS-S1 is **single-hart**, so this module implements one software interrupt bit, one timer compare register, and one timer counter. There is no hart index in the module or register map.

CLINT is not defined by the RISC-V privileged specification. This implementation follows the SiFive de-facto CLINT register layout, which is widely supported by existing RISC-V software. The standardised alternative is ACLINT, which separates the machine timer (MTIMER) and machine software interrupt (MSWI) interfaces. Migrating to ACLINT would require changing the register map and corresponding software/platform integration.

## Register map

Window: 64 KiB at `0x0200_0000` (the `clint` region in `configs/*.yaml`). `ADDR_W = 16`, `REG_DW = 64`.

| Offset | Name | Access | Width | Reset | Meaning |
|---|---|---|---|---|---|
| `0x0000` | `msip` | RW | 32 | `0` | Bit 0 raises the software interrupt; bits 31:1 read as zero |
| `0x4000` | `mtimecmp` | RW | 64 | `0xFFFFFFFFFFFFFFFF` | Timer comparand |
| `0xBFF8` | `mtime` | RW | 64 | `0` | Real-time counter |

Everything else in the window is unmapped and returns `SLVERR`.

**Register implementation note:** The RTL uses a 64-bit register data path. `msip` is implemented using bit 0; its remaining read-data bits are zero.

**Access widths.** The 64-bit peripheral bus (ADR-0005) supports 4-byte and 8-byte naturally aligned accesses. `mtime` and `mtimecmp` can be accessed in a single 64-bit transaction. Byte strobes determine which bytes are updated during writes. A 32-bit bus read-high/read-low/re-read sequence is therefore unnecessary for full-width accesses.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | Clock | Single clock domain |
| `rst_ni` | in | 1 | Reset | Asynchronous active-low reset |
| `rtc_tick_i` | in | 1 | Real-time tick | One `clk_i` cycle wide, generated at `rtc_hz` by `board_top` (SPEC §25). `mtime` counts this signal, never raw `clk_i` cycles |
| `lite_req_i` / `lite_rsp_o` | in/out | `lite_req_t` / `lite_rsp_t` | I4 bus | Frozen interface; see `meds_s1_lite_regif` |
| `msip_o` | out | 1 | → `mip.MSIP` | Active-high level interrupt |
| `mtip_o` | out | 1 | → `mip.MTIP` | Active-high level interrupt; not edge-detected |

**Reset state:** `msip` resets to zero, `mtime` resets to zero, and `mtimecmp` resets to all ones. Consequently, both `msip_o` and `mtip_o` are low immediately after reset.

## Parameters

None.

The module is single-hart by platform decision. Address and data widths are fixed internally using local parameters (`ADDR_W = 16`, `REG_DW = 64`) to match the CLINT region and peripheral bus configuration.

## Behaviour

### Software interrupt

- `msip` is controlled by writes to offset `0x0000`.
- Writing a value with bit 0 set asserts `msip_o`.
- Writing a value with bit 0 clear deasserts `msip_o`.
- Reading the register returns the current state of bit 0.
- The interrupt output directly reflects the stored bit and remains asserted until software clears it.

### Timer counter

- `mtime` is a 64-bit counter.
- It increments by one on each rising edge of `clk_i` when `rtc_tick_i` is asserted.
- It does not increment when `rtc_tick_i` is low.
- Software can read and write `mtime`.
- Byte strobes control partial writes.
- If an MTIME write and an RTC tick occur in the same cycle, the software write takes priority and the tick is not applied.

### Timer compare and interrupt

- `mtimecmp` is a 64-bit software-programmable compare register.
- It resets to `0xFFFFFFFFFFFFFFFF`.
- `mtip_o` is asserted whenever:

  `mtime >= mtimecmp`

- The comparison is **greater than or equal to**, not equality. Using equality would cause the interrupt to deassert as soon as `mtime` increments past `mtimecmp`, potentially missing the interrupt if software does not service it during that exact cycle.
- When software writes a new `mtimecmp` value while `mtip_o` is asserted, the output updates according to the new comparison result. If the new compare value is greater than `mtime`, the interrupt deasserts; otherwise, it remains asserted.
- `mtime` continues counting on RTC ticks during bus accesses, except when an MTIME write takes priority over a simultaneous tick.

### Bus access and errors

- Register reads return the selected register's current value.
- Mapped register addresses return successful responses for valid reads and writes.
- Writes to `mtime` and `mtimecmp` use byte strobes to update selected bytes.
- Unmapped addresses return a slave error (`SLVERR`) response.
- The register interface is handled through `meds_s1_lite_regif`.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | PASS | `make lint` |
| Unit test | PASS — 28 checks | `verif/unit/tb_meds_s1_clint.sv` |
| Repository checks | PASS | `make check` |
| Configuration elaboration | PASS — all four configurations | `s1_ai`, `s1_base`, `s1_linux`, `s1_nano` |

### Unit test coverage

The directed testbench verifies:

- Reset values and interrupt outputs.
- MSIP set, clear, and readback.
- Full-width MTIME and MTIMECMP accesses.
- MTIME holding when `rtc_tick_i` is low.
- MTIME incrementing on an RTC tick.
- MTIP behavior below, at, and above the compare value.
- Low-byte MTIME write strobes.
- High-byte MTIMECMP write strobes.
- Unmapped read and write error responses.

Run the unit test with:

```bash
make test-unit TB=meds_s1_clint
```

The testbench currently reports 28 passing checks.