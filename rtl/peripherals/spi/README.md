# SPI Master (SystemVerilog)
 
A configurable, register-friendly SPI master core with support for all four
SPI clock modes (CPOL/CPHA), a software-programmable baud-rate divider, and
a modular FSM-driven datapath.
 
Core simulation reference: https://edaplayground.com/x/sSn_
 
---
 
## Overview
 
This project implements a full-duplex SPI master built from small,
single-purpose modules wired together in `spi_master.sv`. A parallel byte
is loaded in, shifted out on `mosi` while simultaneously shifting a byte in
from `miso`, and the received byte is presented back on `rx_data` with a
one-cycle `rx_valid` pulse when the transfer completes.
 
Alongside the SPI core, the project includes a set of standalone,
memory-mapped-style **peripheral registers** (`control_register`,
`divider_register`, `txdata_register`, `rxdata_register`, `cs_register`,
`status_register`) intended for a future bus-facing wrapper around the
core. See [Register file status](#register-file-status) below — not all of
these are currently wired into `spi_master`.
 
---
 

 
## Module reference
 
### Core datapath
 
| Module | Purpose |
|---|---|
| `spi_master` | Top-level core. Instantiates and wires together every module below, drives the SPI pins (`sclk`, `mosi`, `miso`, `cs`) and the parallel interface (`tx_data`, `rx_data`, `rx_valid`, `busy`). |
| `spi_fsm` | 4-state controller (`IDLE → LOAD → TRANSFER → FINISH → IDLE`). Decides, based on `cpol`/`cpha`, which SCLK edge samples RX and which shifts TX. Drives `cs_active`, `busy`, and every shift/capture/clear enable in the design. |
| `baud_generator` | Free-running divide-by-`divider` counter. Emits a one-cycle `tick` pulse every `divider` `clk` cycles, only while `enable` (`busy`) is high. |
| `sclk_generator` | Toggles the `sclk` output on every `tick` (one full SCLK period = `2 × divider` clocks). Idles at `cpol` when disabled. Emits one-cycle `sck_rising`/`sck_falling` pulses on each toggle. |
| `tx_shift_register` | Parallel-load, shift-left-out TX register. `mosi` is continuously wired to the current MSB (`data[WIDTH-1]`), so the first bit is valid immediately after `load`, satisfying CPHA=0 timing. |
| `rx_shift_register` | Serial-in, shift-left, MSB-first RX register. Captures `miso` into the LSB on every `shift_en` pulse. |
| `spi_counter` | 4-bit up-counter tracking bits transferred. `done` (`bits_done`) asserts when `count == 8`. Cleared once per transfer by the FSM's `LOAD` state. |
 
### Peripheral / configuration registers
 
| Module | Purpose | Wired into `spi_master`? |
|---|---|---|
| `control_register` | Decodes a 32-bit write into `enable`, `irq_en`, `cpol`, `cpha` (bits 0–3). | Not directly — feeds the core's `enable`/`cpol`/`cpha` inputs in the testbench wrapper, not inside `spi_master.sv` itself. |
| `divider_register` | Latches the lower 16 bits of a 32-bit write into `divider`. Resets to `100`. | Same as above — external to the core, feeds `divider`. |
| `txdata_register` | Latches a `WIDTH`-bit write into `tx_data`. | External — feeds `tx_data` into the core. |
| `rxdata_register` | Captures `rx_shift_data` on `capture_en`. | **Not used.** `spi_master` already performs this capture internally (see `rx_data`/`rx_valid` logic below). |
| `cs_register` | Software-writable, active-low 1-bit chip-select latch. | **Not used.** `spi_master` drives its own `cs` pin automatically from `cs_active`. |
| `status_register` | Combinational (`always_comb`) packing of `tx_full/tx_empty/rx_full/rx_empty/busy/irq` into a 32-bit status word. | **Not used.** No FIFO/IRQ source signals exist yet to feed it. |
 
These peripheral registers model a memory-mapped register file (the kind
that would sit behind an APB/AXI-lite bus in an SoC). `rxdata_register`,
`cs_register`, and `status_register` are currently orphaned — see
[Future work](#future-work).
 
---
 
## SPI clock modes
 
Mode is set via `cpol`/`cpha`, decoded inside `spi_fsm`:
 
| CPOL | CPHA | Idle clock | Leading edge (sample or shift) | Notes |
|---|---|---|---|---|
| 0 | 0 | Low | Rising = sample RX | Mode 0 (most common) |
| 0 | 1 | Low | Rising = shift TX | Mode 1 |
| 1 | 0 | High | Falling = sample RX | Mode 2 |
| 1 | 1 | High | Falling = shift TX | Mode 3 |
 
`sclk_generator` only cares about `cpol` for the idle level — all
leading/trailing-edge decisions live in `spi_fsm`'s `TRANSFER` state logic.
 
---
 
## Baud rate
 
```
SCLK period = 2 × divider × clk period
SCLK freq   = clk freq / (2 × divider)
```
 
`divider` is 16-bit; `divider == 0` is guarded in `baud_generator` (holds
`tick` low rather than dividing by zero).
 
---
 
## FSM states
 
```
IDLE ──(start)──► LOAD ──(always)──► TRANSFER ──(bits_done)──► FINISH ──(always)──► IDLE
                                         │  ▲
                                         └──┘ one shift/sample per SCLK edge
```
 
| State | `busy` | `cs_active` | Notes |
|---|---|---|---|
| `IDLE` | 0 | 0 | Waiting for `start` (`enable & start_pin`). |
| `LOAD` | 1 | 1 | One cycle only. Pulses `tx_load` (parallel-loads TX shifter) and `counter_clear`. |
| `TRANSFER` | 1 | 1 | Runs for `2 × divider × WIDTH` clocks. Each SCLK edge triggers either a sample (`rx_shift_en` + `counter_increment`) or a shift (`tx_shift_en`), per the mode table above. |
| `FINISH` | 0 | 0 | One cycle only. Pulses `rx_capture`, which latches `rx_data` and pulses `rx_valid` in `spi_master`. |
 
`cs_active` is asserted unconditionally for the full duration of `LOAD` +
`TRANSFER` (not gated by any SCLK edge), which is what keeps the physical
`cs` pin held low continuously across the whole byte transfer rather than
flickering per bit.
 
---
 
## Top-level ports (`spi_master`)
 
| Port | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst` | in | 1 | System clock, active-high async reset |
| `enable` | in | 1 | Master enable (from control register) |
| `start` | in | 1 | Start a transfer (qualified internally by `enable`) |
| `cpol`, `cpha` | in | 1 | SPI mode select |
| `divider` | in | 16 | Baud-rate divider |
| `tx_data` | in | `WIDTH` | Byte to transmit |
| `rx_data` | out | `WIDTH` | Byte received (valid when `rx_valid` pulses) |
| `rx_valid` | out | 1 | One-cycle pulse when `rx_data` is valid |
| `busy` | out | 1 | High for the duration of a transfer |
| `sclk`, `mosi`, `cs` | out | 1 | SPI clock, master-out, active-low chip select |
| `miso` | in | 1 | Master-in |
 
`WIDTH` is a module parameter (default 8).
 
---
 
## Known fix applied
 
`spi_master`'s `cs` output port was previously declared but never driven —
no `assign` or register connected it to the internally-generated
`cs_active` signal, leaving `cs` permanently undefined (`x`). This broke
any testbench slave model gated on `negedge cs` / `!cs`. Fixed with:
 
```systemverilog
assign cs = ~cs_active;
```
 
(`cs` is active-low; `cs_active` from `spi_fsm` is active-high.)
 
---
 
## Simulation
 
Two self-checking testbenches are included:
 
- **`spi_master_tb`** — drives `spi_master`'s ports directly (no register
  file), loads Mode 0, `divider = 4`, `tx_data = 0xCC`, waits for
  `rx_valid`, and prints the transfer result.
- **Register-mapped `spi_master_tb`** — exercises `control_register`,
  `txdata_register`, and `divider_register` via one-cycle write pulses
  (`write_en` + `write_data`) instead of driving the core directly, then
  self-checks `rx_data == SLAVE_RESPONSE` and prints
  `PASS`/`FAIL`.
Both testbenches include a behavioral SPI slave model (`always @(negedge
cs)` / `always @(posedge/negedge sclk)`) that shifts back a fixed response
byte (`8'b10101010`), used to validate the master's TX/RX path in loopback.
 
To run (Icarus Verilog example):
 
```bash
iverilog -g2012 -o sim spi_master.sv spi_fsm.sv sclk_generator.sv \
    baud_generator.sv tx_shift_register.sv rx_shift_register.sv \
    spi_counter.sv control_register.sv txdata_register.sv \
    divider_register.sv spi_master_tb.sv
vvp sim
gtkwave dump.vcd
```
 
---
 
## Future work
 
- Add a bus-facing wrapper module to connect `control_register`,
  `divider_register`, `txdata_register`, `cs_register`,
  `rxdata_register`, and `status_register` to an actual bus (APB/AXI-lite)
  and to `spi_master`, replacing the core's internal `rx_data`/`rx_valid`
  capture with the external `rxdata_register` + status-flag path.
- Add TX/RX FIFOs to back the `tx_full`/`tx_empty`/`rx_full`/`rx_empty`
  bits already stubbed into `status_register`.
- Add interrupt generation (`irq`) gated by `irq_en` from
  `control_register`, feeding `status_register`'s `irq` bit.
- Support multi-byte burst transfers with `cs` held low across multiple
  `start` pulses (would use `cs_register`'s manual override instead of, or
  OR'd with, the FSM's automatic `cs_active`).
- Parameterize `spi_counter`'s `done` comparison against `WIDTH` instead of
  the hardcoded `4'd8`, to support widths other than 8..

