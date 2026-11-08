// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_core : S1-Core, classic 5-stage in-order pipeline            [WIP -- T-02]
// Description  :
// IF -> ID -> EX -> MEM -> WB.  In-order completion, WB is the commit point.
// RV64IAC_Zicsr_Zifencei, M and U mode; RV64M, the CSR file and PMP are outside.
// Memory ports speak MEM-REQ (INTERFACES.md I2).  Port groups below; design
// notes and departures from the SPEC: docs/modules/s1_core.md.
//
// Reference: SPEC 6, 7, 8, 10-12; INTERFACES.md I1, I2, I6, I7.
// =============================================================================

module s1_core
  import s1_pkg::*;
#(
  parameter logic [XLEN-1:0] RESET_PC    = BOOT_ADDR,
  // SPEC 7.2: decode an unrecognised encoding as an MXIF candidate, not illegal.
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

  // ---- MXIF-1.0 coprocessor port (INTERFACES.md I1) -----------------------
  // Offload happens at WB (R1.1).  Tied off until a coprocessor is attached:
  // x_issue_valid_o is 0, so nothing is ever offloaded.
  output logic                x_issue_valid_o,
  input  logic                x_issue_ready_i,
  output logic [31:0]         x_issue_instr_o,
  output logic [1:0]          x_issue_mode_o,
  output logic [3:0]          x_issue_id_o,
  output logic [63:0]         x_issue_pc_o,
  output logic [2:0][63:0]    x_issue_rs_o,
  output logic [2:0]          x_issue_rs_valid_o,
  input  logic                x_issue_accept_i,
  input  logic                x_issue_writeback_i,
  input  logic                x_issue_dualwrite_i,
  input  logic                x_issue_loadstore_i,
  output logic                x_commit_valid_o,
  output logic [3:0]          x_commit_id_o,
  output logic                x_commit_kill_o,
  input  logic                x_norollback_i,
  input  logic [3:0]          x_norollback_id_i,
  input  logic                x_result_valid_i,
  output logic                x_result_ready_o,
  input  logic [3:0]          x_result_id_i,
  input  logic [4:0]          x_result_rd_i,
  input  logic [63:0]         x_result_data_i,
  input  logic                x_result_we_i,
  input  logic                x_result_exc_i,
  input  logic [5:0]          x_result_exccode_i,
  input  logic                x_idle_i,

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
  s1_execute u_ex (
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

  // registered: MEM.wb_valid -> WB.flush -> MEM is a comb loop
  logic mem_flush_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) mem_flush_q <= 1'b0;
    else         mem_flush_q <= wb_flush;
  end

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

    .sb_commit_i      (sb_commit),

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

  // Instruction fetch does not use the check port.
  assign chk_ex_o = 1'b0;

  // ===========================================================================
  // WB -- the architectural commit point
  // ===========================================================================
  s1_wb u_wb (
    .wb_valid_i           (mem_wb_valid),
    .wb_i                 (mem_wb),

    .irq_valid_i          (irq_valid_i),
    .irq_code_i           (irq_code_i),

    .rf_wr_o              (rf_wr),
    .csr_commit_o         (csr_commit_o),
    .instret_o            (instret_o),

    .sb_commit_o          (sb_commit),

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

  // MXIF tie-off (no coprocessor yet).
  assign x_issue_valid_o    = 1'b0;
  assign x_issue_instr_o    = '0;
  assign x_issue_mode_o     = '0;
  assign x_issue_id_o       = '0;
  assign x_issue_pc_o       = '0;
  assign x_issue_rs_o       = '0;
  assign x_issue_rs_valid_o = '0;
  assign x_commit_valid_o   = 1'b0;
  assign x_commit_id_o      = '0;
  assign x_commit_kill_o    = 1'b0;
  assign x_result_ready_o   = 1'b0;

  logic unused_mxif;
  assign unused_mxif = ^{x_issue_ready_i, x_issue_accept_i, x_issue_writeback_i,
                         x_issue_dualwrite_i, x_issue_loadstore_i, x_norollback_i,
                         x_norollback_id_i, x_result_valid_i, x_result_id_i,
                         x_result_rd_i, x_result_data_i, x_result_we_i,
                         x_result_exc_i, x_result_exccode_i, x_idle_i};

endmodule
