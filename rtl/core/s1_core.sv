// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : integration (Oct,2026)
// Modified By  :
//
// s1_core      : S1-Core -- RV64IMAC, classic 5-stage, in order  [WIP -- T-02]
// Description  :
//
//   IF  ->  ID  ->  EX  ->  MEM  ->  WB
//
// Single issue, in-order issue, **in-order completion**, one instruction
// committed per cycle in WB.  `RV64IMAC_Zicsr_Zifencei`, machine and user
// mode; the CSR file, PMP and counters are outside the core.
//
// There is no completion buffer, no coprocessor port, and no multi-cycle unit
// hanging off the side of the pipeline.  MUL and DIV run inside EX and stall
// it, so every result leaves EX in program order and there is exactly one
// write path to architectural state: WB.  That is what makes this core small
// enough to read in an afternoon and cheap to attach things to.
//
// The core speaks MEM-REQ (`INTERFACES.md` I2) on both memory ports and never
// AXI (`rtl/core/README.md` rule 1).  Caches, fabric, CLINT, PLIC and debug
// all attach at this boundary.
//
// -----------------------------------------------------------------------------
// FOR WHOEVER IS BUILDING THE OTHER HALF
//
// Everything you need to attach to is a port of this module, and every one of
// them is a frozen interface from specs/INTERFACES.md:
//
//   imem_*, dmem_*     I2 MEM-REQ.  valid/ready, payload stable until accepted,
//                      `valid` never a function of `ready`.  One request
//                      outstanding per port.  Put your I$ and D$ here.
//   csr_*, trap_*,     the CSR file -- OUTSIDE this core (it is another
//   mret_o, priv_*,    project's).  EX queries it (side-effect free), WB
//   irq_*, instret_o,  commits to it, asks it to take traps and xRET, and it
//   perf_*_o           answers with the vector, mepc, the privilege mode and
//                      any pending interrupt (already masked, I7).  It owns
//                      the PMP CSRs and the counters, fed by instret_o and
//                      the perf_*_o event lines.
//   rvfi_o             I6.  One committed instruction per cycle; this is what
//                      Spike co-simulation reads.
//   fence_i_o          asserted for one cycle when FENCE.I commits: invalidate
//                      the I$ now, the redirect is already on its way.
//   store_err_o        a bus error draining an already-committed store.
//                      Imprecise by construction -- raise it as a machine
//                      check at the platform level.
//   chk_*, pma_*,      the PMA and PMP checks.  Both are OUTSIDE this core;
//   pmp_allow_i        it asks, you answer in the same cycle.  The PMP
//                      configuration comes from the CSR file, not from here.
//   md_*               RV64M.  Also outside: EX stalls on it, so it needs no
//                      tag and cannot complete out of order.
//
// verif/cosim/tb_s1_core.sv models memory behind imem/dmem, answers the PMA/PMP
// query permissively, ties md_* off, stands in for the CSR file with a minimal
// model (verif/cosim/tb_csr_model.sv), and runs every RV64I instruction against
// spike.  What is deliberately absent, and where this core departs
// from the SPEC, is written down in docs/modules/s1_core.md.
// -----------------------------------------------------------------------------
//
// Reference: SPEC 6, 7, 8, 10-12; INTERFACES.md I2, I6, I7.
// =============================================================================

module s1_core
  import s1_pkg::*;
#(
  parameter logic [XLEN-1:0] RESET_PC    = BOOT_ADDR,
  // SPEC 7.2: with this set the decoder marks an unrecognised encoding as an
  // MXIF candidate instead of illegal.  There is no MXIF port on this core
  // yet, so a candidate still ends as illegal-instruction (in EX) either way;
  // the parameter is here so the decode path is already the one SPEC asks for.
  parameter bit              MXIF_EN     = 1'b0
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  // ---- I$ port, MEM-REQ (INTERFACES.md I2) --------------------------------
  output logic            imem_req_valid_o,
  input  logic            imem_req_ready_i,
  output mem_req_t        imem_req_o,
  input  logic            imem_rsp_valid_i,
  output logic            imem_rsp_ready_o,
  input  mem_rsp_t        imem_rsp_i,

  // ---- D$ port, MEM-REQ ---------------------------------------------------
  output logic            dmem_req_valid_o,
  input  logic            dmem_req_ready_i,
  output mem_req_t        dmem_req_o,
  input  logic            dmem_rsp_valid_i,
  output logic            dmem_rsp_ready_o,
  input  mem_rsp_t        dmem_rsp_i,

  // ---- Zifencei to the caches ---------------------------------------------
  output logic            fence_i_o,

  // ---- A bus error draining an already-committed store --------------------
  output logic            store_err_o,
  output logic [XLEN-1:0] store_err_addr_o,

  // ---- Physical-memory checks — EXTERNAL (SPEC 11) ------------------------
  // One query per data access, answered combinationally in the same cycle.
  // Two independent checkers, deliberately: PMA comes from soc.yaml, PMP from
  // the CSRs below.
  output logic [XLEN-1:0]     chk_addr_o,
  output logic [2:0]          chk_size_o,       // log2 bytes
  output logic                chk_rd_o,
  output logic                chk_wr_o,
  output logic                chk_ex_o,         // instruction fetch; tied 0 today
  output priv_lvl_e           chk_priv_o,       // effective mode, after MPRV
  input  pma_t                pma_i,
  input  logic                pma_fault_i,
  input  logic                pmp_allow_i,


  // ---- RV64M multiply / divide — EXTERNAL (SPEC 2.1) ----------------------
  // Not a pipeline unit: EX asserts `start` in the instruction's first EX
  // cycle and holds it until `done`, and the answer is EX's result.  One
  // operation at a time; results never arrive out of order.
  output logic                md_start_o,
  output muldiv_op_e          md_op_o,
  output logic [XLEN-1:0]     md_a_o,
  output logic [XLEN-1:0]     md_b_o,
  output logic                md_flush_o,
  input  logic                md_done_i,
  input  logic [XLEN-1:0]     md_result_i,

  // ---- CSR file -- EXTERNAL (SPEC 10) --------------------------------------
  // Query from EX: side-effect free, answered combinationally.
  output logic [11:0]         csr_addr_o,
  output logic                csr_re_o,
  output logic                csr_we_o,
  input  logic [XLEN-1:0]     csr_rdata_i,
  input  logic                csr_illegal_i,
  // The only write, from WB, never speculative.
  output csr_upd_t            csr_commit_o,
  // Traps and xRET, from WB; trap_vec_i may depend combinationally on
  // trap_req_o (vectored interrupts).
  output trap_req_t           trap_req_o,
  output logic                mret_o,
  input  logic [XLEN-1:0]     trap_vec_i,
  input  logic [XLEN-1:0]     mepc_i,
  // Privilege: current, and effective for loads/stores (after MPRV).
  input  priv_lvl_e           priv_i,
  input  priv_lvl_e           priv_data_i,
  // A pending, enabled interrupt, already prioritised by the CSR file.
  input  logic                irq_valid_i,
  input  logic [5:0]          irq_code_i,
  // Counters: one instruction retired (not trapped), and the event lines.
  output logic                instret_o,
  output logic                perf_br_taken_o,
  output logic                perf_br_mispredict_o,
  output logic                perf_load_retired_o,
  output logic                perf_store_retired_o,
  output logic                perf_sb_full_o,
  output logic                perf_muldiv_stall_o,
  output logic                perf_load_use_o,
  output logic                perf_hazard_stall_o,

  // ---- RVFI trace (INTERFACES.md I6) --------------------------------------
  output rvfi_t           rvfi_o
);

  // ===========================================================================
  // Inter-stage nets
  // ===========================================================================
  logic        fetch_rsp_valid, fetch_rsp_ready;
  fetch_rsp_t  fetch_rsp;

  logic        id_ex_valid, id_ex_ready;
  id_ex_t      id_ex;

  logic        ex_mem_valid, ex_mem_ready;
  ex_mem_t     ex_mem;

  logic        mem_wb_valid, mem_wb_pend;
  mem_wb_t     mem_wb;

  localparam int unsigned RF_N_READ = 2;   // rs1, rs2
  logic [REG_ADDR_W-1:0] rf_rs1_addr, rf_rs2_addr;
  logic [RF_N_READ-1:0][REG_ADDR_W-1:0] rf_raddr;
  logic [RF_N_READ-1:0][XLEN-1:0]       rf_rdata;
  rf_wr_t                rf_wr;

  logic                  wb_flush, wb_redirect_valid, wb_busy;
  logic [XLEN-1:0]       wb_redirect_pc;
  flush_cause_e          wb_flush_cause;
  logic                  sb_commit;
  logic [TAG_W-1:0]      sb_commit_tag;

  logic                  ex_redirect_valid;
  logic [XLEN-1:0]       ex_redirect_pc;


  logic            sb_empty;


  logic [63:0]     order_q;

  // ===========================================================================
  // IF -- fetch, realign, BTFN, C expansion
  // ===========================================================================
  s1_fetch #(
    .RESET_PC (RESET_PC)
  ) u_fetch (
    .clk_i                   (clk_i),
    .rst_ni                  (rst_ni),

    .ex_redirect_valid_i     (ex_redirect_valid),
    .ex_redirect_pc_i        (ex_redirect_pc),
    .retire_redirect_valid_i (wb_redirect_valid),
    .retire_redirect_pc_i    (wb_redirect_pc),
    .priv_i                  (priv_i),

    .imem_req_valid_o        (imem_req_valid_o),
    .imem_req_ready_i        (imem_req_ready_i),
    .imem_req_o              (imem_req_o),
    .imem_rsp_valid_i        (imem_rsp_valid_i),
    .imem_rsp_ready_o        (imem_rsp_ready_o),
    .imem_rsp_i              (imem_rsp_i),

    .fetch_rsp_valid_o       (fetch_rsp_valid),
    .fetch_rsp_ready_i       (fetch_rsp_ready),
    .fetch_rsp_o             (fetch_rsp),

    .nxt_rs1_addr_o          (rf_rs1_addr),
    .nxt_rs2_addr_o          (rf_rs2_addr)
  );

  // ===========================================================================
  // ID -- decode, register read, hazards
  // ===========================================================================

  // ID serialises CSR and system instructions on an empty pipeline.  "Empty"
  // is everything downstream of the ID/EX register, which ID checks itself --
  // including a read still waiting in MEM/WB, which mem_wb_valid does not
  // show until the cycle it completes.
  logic downstream_busy;
  assign downstream_busy = ex_mem_valid || mem_wb_pend || mem_wb_valid || wb_busy
                        || !sb_empty;

  s1_id #(
    .MXIF_EN (MXIF_EN)
  ) u_id (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),

    .flush_i             (wb_flush),
    .ex_redirect_valid_i (ex_redirect_valid),

    .fetch_rsp_valid_i   (fetch_rsp_valid),
    .fetch_rsp_ready_o   (fetch_rsp_ready),
    .fetch_rsp_i         (fetch_rsp),

    .rs1_data_i          (rf_rdata[0]),
    .rs2_data_i          (rf_rdata[1]),

    .exmem_valid_i       (ex_mem_valid),
    .exmem_i             (ex_mem),

    .memwb_pend_i        (mem_wb_pend),
    .memwb_rd_i          (mem_wb.rd),
    .memwb_rd_we_i       (mem_wb.rd_we),

    .downstream_busy_i   (downstream_busy),

    .ex_valid_o          (id_ex_valid),
    .ex_ready_i          (id_ex_ready),
    .ex_o                (id_ex),

    .perf_load_use_o     (perf_load_use_o),
    .perf_hazard_stall_o (perf_hazard_stall_o)
  );

  // The read is registered (meds_s1_sram, R-C5): fetch presents the addresses
  // of the instruction about to enter ID, and the data is there with it.
  // Port 0 is rs1, port 1 is rs2.
  assign rf_raddr[0] = rf_rs1_addr;
  assign rf_raddr[1] = rf_rs2_addr;

  s1_regfile #(
    .N_READ (RF_N_READ)
  ) u_regfile (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .raddr_i (rf_raddr),
    .rdata_o (rf_rdata),
    .we_i    (rf_wr.we),
    .waddr_i (rf_wr.addr),
    .wdata_i (rf_wr.data)
  );

  // ===========================================================================
  // EX -- ALU, branch resolution, AGU, CSR read-modify-write, RV64M
  // ===========================================================================
  s1_ex u_ex (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),

    .flush_i              (wb_flush),
    .priv_i               (priv_i),

    .ex_valid_i           (id_ex_valid),
    .ex_ready_o           (id_ex_ready),
    .ex_i                 (id_ex),

    .csr_addr_o           (csr_addr_o),
    .csr_re_o             (csr_re_o),
    .csr_we_o             (csr_we_o),
    .csr_rdata_i          (csr_rdata_i),
    .csr_illegal_i        (csr_illegal_i),

    .ex_redirect_valid_o  (ex_redirect_valid),
    .ex_redirect_pc_o     (ex_redirect_pc),

    .mem_valid_o          (ex_mem_valid),
    .mem_ready_i          (ex_mem_ready),
    .mem_o                (ex_mem),

    .md_start_o           (md_start_o),
    .md_op_o              (md_op_o),
    .md_a_o               (md_a_o),
    .md_b_o               (md_b_o),
    .md_flush_o           (md_flush_o),
    .md_done_i            (md_done_i),
    .md_result_i          (md_result_i),

    .perf_br_taken_o      (perf_br_taken_o),
    .perf_br_mispredict_o (perf_br_mispredict_o),
    .perf_muldiv_stall_o  (perf_muldiv_stall_o)
  );

  // ===========================================================================
  // MEM -- D$ access, PMA/PMP, store buffer, AMO and LR/SC
  // ===========================================================================

  // The flush reaches MEM one cycle late, and it has to.  WB is combinational
  // on MEM's output, so a flush wired straight back would close the loop
  //     MEM.wb_valid_o -> WB.trap -> WB.flush_o -> MEM.wb_valid_o
  // which is not a pipeline hazard but an actual combinational cycle.
  //
  // Delaying it is correct, not a patch.  The instruction MEM is presenting is
  // the one WB is committing -- flushing it would be flushing the trapping
  // instruction itself, and it leaves this cycle regardless.  What the flush
  // must kill is everything *younger*: the EX/MEM register (flushed
  // combinationally, no loop there, since its output to MEM is registered),
  // and any uncommitted store-buffer entry, which the delayed flush removes a
  // cycle later -- before any of it can reach architectural state, because
  // only WB commits and WB sees nothing in that cycle.
  logic mem_flush_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) mem_flush_q <= 1'b0;
    else         mem_flush_q <= wb_flush;
  end

  // The store commit reaches MEM one cycle after WB issues it.
  //
  // An AMO allocates its store-buffer entry at the moment it completes, which
  // is the same cycle WB commits it -- and MEM's commit sweep only visits
  // entries that already exist, so a commit arriving in the allocation cycle
  // would be dropped and the store would sit in the buffer for ever.  (With a
  // completion buffer this could not happen: the commit came from retire, a
  // cycle after WB had written the entry.)
  //
  // Delaying by one cycle is the fix that leaves MEM untouched -- it is the
  // module with 891k checks behind it, and this is a property of when WB runs,
  // not of how the store buffer works.  Nothing is at risk in the gap: a store
  // only reaches here having committed, so no trap can revoke it, and MEM's
  // flush keeps committed entries regardless.
  logic             sb_commit_q;
  logic [TAG_W-1:0] sb_commit_tag_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sb_commit_q     <= 1'b0;
      sb_commit_tag_q <= '0;
    end else begin
      sb_commit_q     <= sb_commit;
      sb_commit_tag_q <= sb_commit_tag;
    end
  end

  // The store buffer matches a committed store to its pending entry by tag.
  // The oldest in-flight tag is WB's if WB holds something, otherwise MEM's --
  // which in an in-order pipeline is just "the instruction nearest the end".
  logic [TAG_W-1:0] oldest_tag;
  assign oldest_tag = mem_wb_valid ? mem_wb.tag : ex_mem.tag;

  s1_mem u_mem (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),

    .flush_i          (mem_flush_q),
    .priv_i           (priv_data_i),

    .mem_valid_i      (ex_mem_valid),
    .mem_ready_o      (ex_mem_ready),
    .mem_i            (ex_mem),

    .wb_valid_o       (mem_wb_valid),
    .wb_o             (mem_wb),
    .wb_pend_o        (mem_wb_pend),

    .oldest_tag_i     (oldest_tag),
    .sb_commit_i      (sb_commit_q),
    .sb_commit_tag_i  (sb_commit_tag_q),

    .chk_addr_o       (chk_addr_o),
    .chk_size_o       (chk_size_o),
    .chk_rd_o         (chk_rd_o),
    .chk_wr_o         (chk_wr_o),
    .chk_priv_o       (chk_priv_o),
    .pma_i            (pma_i),
    .pma_fault_i      (pma_fault_i),
    .pmp_allow_i      (pmp_allow_i),

    .dmem_req_valid_o (dmem_req_valid_o),
    .dmem_req_ready_i (dmem_req_ready_i),
    .dmem_req_o       (dmem_req_o),
    .dmem_rsp_valid_i (dmem_rsp_valid_i),
    .dmem_rsp_ready_o (dmem_rsp_ready_o),
    .dmem_rsp_i       (dmem_rsp_i),

    .sb_empty_o       (sb_empty),
    .sb_full_o        (perf_sb_full_o),
    .store_err_o      (store_err_o),
    .store_err_addr_o (store_err_addr_o)
  );

  // The core never fetches through the check port today, so `ex` is tied low.
  // Closing that gap (docs/modules/s1_core.md) means giving s1_fetch its
  // own query rather than changing this one.
  assign chk_ex_o = 1'b0;

  // ===========================================================================
  // WB -- the architectural commit point
  // ===========================================================================
  s1_wb u_wb (
    .wb_valid_i           (mem_wb_valid),
    .wb_i                 (mem_wb),

    .irq_valid_i          (irq_valid_i),
    .irq_code_i           (irq_code_i),

    .sb_empty_i           (sb_empty),

    .rf_wr_o              (rf_wr),
    .csr_commit_o         (csr_commit_o),
    .instret_o            (instret_o),

    .sb_commit_o          (sb_commit),
    .sb_commit_tag_o      (sb_commit_tag),

    .flush_o              (wb_flush),
    .flush_cause_o        (wb_flush_cause),
    .redirect_valid_o     (wb_redirect_valid),
    .redirect_pc_o        (wb_redirect_pc),

    .trap_req_o           (trap_req_o),
    .mret_o               (mret_o),
    .trap_vec_i           (trap_vec_i),
    .mepc_i               (mepc_i),

    .busy_o               (wb_busy),

    .priv_i               (priv_i),
    .order_i              (order_q),
    .rvfi_o               (rvfi_o),

    .perf_load_retired_o  (perf_load_retired_o),
    .perf_store_retired_o (perf_store_retired_o)
  );

  // RVFI's instruction counter.  Kept here rather than in the combinational
  // WB stage, which holds no state of its own.  It counts every RVFI record,
  // trapped ones included, which is why it is not `instret`.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)             order_q <= '0;
    else if (rvfi_o.valid)   order_q <= order_q + 64'd1;
  end

  assign fence_i_o = (wb_flush_cause == FLUSH_FENCE_I);

endmodule
