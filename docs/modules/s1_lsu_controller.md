# `s1_lsu_controller`

| | |
|---|---|
| **Status** | WIP -- R-02 |
| **Owner** | R-02 |
| **Backup** | _(assign)_ |
| **Project** | R-02 -- WP6 |
| **Spec** | SPEC sections 11 and 14; INTERFACES.md section 2 |
| **Source** | `rtl/core/s1_lsu_controller.sv` |
| **Testbench** | `verif/unit/tb_s1_lsu_controller.sv` |

## Purpose

The scalar LSU controller accepts one decoded load or store, latches its request, checks size/alignment and the externally supplied PMA decision, performs one MEM-REQ transaction, and holds the result until the core accepts it. PMP is not integrated in this LSU slice; its default permissive behavior does not block LSU requests.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single clock domain |
| `rst_ni` | in | 1 | reset | asynchronous assert, synchronous de-assert convention |
| `lsu_valid_i` / `lsu_ready_o` | in/out | 1 | core request handshake | request is latched when valid is presented while ready is high |
| `lsu_addr_i` | in | `XLEN` | byte address | retained for the complete transaction |
| `lsu_wdata_i` | in | `XLEN` | store source value | passed to the datapath |
| `lsu_size_i` | in | 3 | log2 transfer size | `0` byte, `1` halfword, `2` word, `3` doubleword |
| `lsu_write_i` | in | 1 | load/store selector | high for stores |
| `lsu_unsigned_i` | in | 1 | load extension selector | applies to loads; ignored for stores |
| `lsu_mode_i` | in | 2 | privilege mode | forwarded to MEM-REQ |
| `lsu_id_i` | in | `MXIF_ID_W` | transaction ID | returned by the matching MEM-REQ response |
| `check_*` | out | varies | PMA request | presents the latched operation during CHECK |
| `pma_allow_i` | in | 1 | PMA decision | high permits the request; low produces a fault without a bus request |
| `pma_fault_code_i` | in | 6 | PMA access fault code | nonzero code is returned when PMA denies the operation |
| `mem_req_valid_o` / `mem_req_ready_i` | out/in | 1 | MEM-REQ request handshake | request payload remains stable until accepted |
| `mem_req_o` | out | `mem_req_t` | memory request | contains address, write, byte enables, lane-aligned data, size, mode, and ID |
| `mem_rsp_valid_i` / `mem_rsp_ready_o` | in/out | 1 | MEM-REQ response handshake | only a response with the latched ID is accepted |
| `mem_rsp_i` | in | `mem_rsp_t` | memory response | bus errors become load/store access faults |
| `lsu_resp_valid_o` / `lsu_resp_ready_i` | out/in | 1 | core response handshake | response and fault fields remain stable until accepted |
| `lsu_rdata_o` | out | `XLEN` | load result | zero for stores and fault responses |
| `lsu_fault_o` | out | 1 | fault indicator | high for alignment, PMA, or bus errors |
| `lsu_fault_code_o` | out | 6 | architectural fault code | standard load/store misaligned or access-fault code |
| `lsu_fault_addr_o` | out | `XLEN` | faulting address | address of the latched operation |

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| No local parameters | package defaults | `s1_pkg::XLEN` and `s1_pkg::MXIF_ID_W` | shared platform widths |

## Behaviour

The controller state machine is:

```text
IDLE -> CHECK -> ISSUE -> WAIT_RSP -> RESP -> IDLE
              \-> RESP on invalid size, misalignment, or PMA denial
```

`CHECK` presents the latched request to the external PMA boundary. Illegal accesses do not assert `mem_req_valid_o`. `ISSUE` holds the MEM-REQ payload stable until `mem_req_ready_i`. `WAIT_RSP` does not assert `mem_rsp_ready_o` for a mismatched response, so the response remains pending until the matching ID arrives. `RESP` holds the final data or fault until `lsu_resp_ready_i`.

This is a blocking reference controller with one outstanding operation. The separate states preserve the independent PMA, MEM-REQ, MEM-RSP, and core-response handshakes required by the MEM-stage boundary in SPEC section 7.4; pipelined overlap belongs to the owning R-02 memory-stage implementation.

## Exceptions and errors

- Invalid transfer size: illegal instruction, code 2.
- Load misaligned: code `EXC_LOAD_ADDR_MISALIGNED` (4).
- Load access fault: code `EXC_LOAD_ACCESS_FAULT` (5).
- Store misaligned: code `EXC_STORE_ADDR_MISALIGNED` (6).
- Store access fault: code `EXC_STORE_ACCESS_FAULT` (7).
- A PMA supplied nonzero fault code is returned for a PMA denial.
- A MEM-REQ bus error is normalized to the corresponding load/store access fault; bus `errcode` is not an architectural mcause.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | direct Verilator lint and ModelSim compile |
| Unit test | 177 checks | `verif/unit/tb_s1_lsu_controller.sv` |
| Co-simulation | not applicable yet | |
| Formal | not yet | |

The testbench covers all load widths, signed/unsigned extension, dirty store values, byte enables, SD, alignment faults, invalid sizes, request backpressure, mismatched response IDs, bus errors, and active PMA denial with no memory request.

## Known limitations

- One outstanding memory operation at a time.
- No store buffer or load forwarding yet.
- No AMO, LR/SC, or reservation-set behavior yet.
- PMA remains an external decision input. PMP integration belongs to a future protection unit and is not part of this LSU controller.
- No cache or address translation is implemented here.

## Open questions

- The MEM-REQ protocol currently has no atomic-operation field; AMO/LR/SC integration must extend the protocol before atomic instructions are added.
- The coprocessor-memory interlock will be added after the basic PMA and store-buffer paths are stable.
