# `boards/kc705/`

A board port is exactly four files (NFR-8): `board.yaml`, `board.xdc`,
`board_top.sv`, `openocd.cfg`. Nothing else may be board-aware.

`board_top.sv` instantiates PLLs, memory controllers and IO buffers — **no logic**.

| File | Status |
|---|---|
| `board.yaml` | present |
| `board.xdc` | TODO |
| `board_top.sv` | TODO |
| `openocd.cfg` | TODO |

Owner project: T-08 (KC705 port), M-12 (Xilinx IP survey)
