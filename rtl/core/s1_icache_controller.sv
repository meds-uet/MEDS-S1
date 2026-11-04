// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_icache_controller : I$ controller FSM                       [COMPLETE]
//
// Drives the passive datapath: IDLE → LOOKUP → (HIT | MISS → REFILL →
// WAIT → LOOKUP). Talks to memory on a miss, hands the fetched
// instruction back to the CPU.
//
// Spec:      SPEC §15
// Testbench: tb_s1_icache_controller.sv
// =============================================================================

module s1_icache_controller #(
    parameter int unsigned ADDR_WIDTH      = 40,
    parameter int unsigned LINE_SIZE_BYTES = 64,
    parameter int unsigned ASSOCIATIVITY   = 2,
    localparam int unsigned WAY_IDX_W      = (ASSOCIATIVITY > 1) ? $clog2(ASSOCIATIVITY) : 1
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,

    // === CPU Interface ===
    input  logic                         req_valid_i,
    input  logic [ADDR_WIDTH-1:0]        req_addr_i,
    output logic                         rsp_valid_o,
    output logic [31:0]                  rsp_data_o,
    output logic                         rsp_error_o,   // tied 0 in v1.0 (no PMA/PMP)

    // === From Datapath ===
    input  logic                         hit_i,
    input  logic [ASSOCIATIVITY-1:0]     hit_way_i,      // observability only
    input  logic [WAY_IDX_W-1:0]         lru_way_i,      // victim way for refill
    input  logic [31:0]                  dp_data_i,

    // === To Datapath ===
    output logic                         refill_sel_o,
    output logic [ADDR_WIDTH-1:0]        refill_addr_o,  // line-aligned
    output logic                         refill_we_o,
    output logic                         refill_valid_o,
    output logic [WAY_IDX_W-1:0]         refill_way_sel_o,

    // === Memory Interface (control only) ===
    // NOTE: mem_data_i is NOT routed through this controller — it wires
    // directly to the datapath's refill_data_i at the top level.
    output logic                         mem_req_o,
    output logic [ADDR_WIDTH-1:0]        mem_addr_o,
    input  logic                         mem_valid_i
);

    localparam int unsigned OFFSET_BITS = $clog2(LINE_SIZE_BYTES);

    // -------------------------------------------------------------------------
    // FSM State Encoding
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WAIT,
        ST_LOOKUP,
        ST_HIT,
        ST_MISS,
        ST_REFILL
    } state_t;

    state_t state_q, state_d;

    // -------------------------------------------------------------------------
    // Latched State
    // -------------------------------------------------------------------------
    // Instruction captured when LOOKUP detects a hit.
    logic [31:0] rsp_data_q;

    // LRU victim way, captured during LOOKUP on the miss branch. Using a
    // flop here breaks a combinational loop between this controller's
    // refill_way_sel_o and the datapath's write-forwarded lru_way_o (which
    // is derived combinationally from refill_way_sel_i while refill_we_i
    // is asserted).
    logic [WAY_IDX_W-1:0] refill_way_q;

    // -------------------------------------------------------------------------
    // Refill Address Alignment
    //   Memory returns a full 64-byte line, so offset bits are dropped.
    // -------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] aligned_addr;
    assign aligned_addr = {req_addr_i[ADDR_WIDTH-1:OFFSET_BITS],
                           {OFFSET_BITS{1'b0}}};

    // -------------------------------------------------------------------------
    // FSM Next-State Logic
    // -------------------------------------------------------------------------
    always_comb begin
        state_d = state_q;
        unique case (state_q)
            ST_IDLE:   if (req_valid_i) state_d = ST_LOOKUP;
            ST_WAIT:   state_d = ST_LOOKUP;
            ST_LOOKUP: state_d = (hit_i === 1'b1) ? ST_HIT : ST_MISS;
            ST_HIT:    state_d = ST_IDLE;
            ST_MISS:   if (mem_valid_i) state_d = ST_REFILL;
            ST_REFILL: state_d = ST_WAIT;
            default:   state_d = ST_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // State Register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state_q <= ST_IDLE;
        else         state_q <= state_d;
    end

    // -------------------------------------------------------------------------
    // Latched Instruction (on hit)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) rsp_data_q <= '0;
        else if (state_q == ST_LOOKUP && hit_i) rsp_data_q <= dp_data_i;
    end

    // -------------------------------------------------------------------------
    // Latched LRU Victim Way (on miss)
    //   lru_way_i is only valid when no refill write is in flight, i.e.
    //   during LOOKUP — capture it there and hold through MISS/REFILL.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            refill_way_q <= '0;
        end else if (state_q == ST_LOOKUP && (hit_i !== 1'b1)) begin
            refill_way_q <= (lru_way_i === 1'b1) ? 1'b1 : 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Output Logic (combinational, default-first)
    // -------------------------------------------------------------------------
    always_comb begin
        refill_sel_o     = 1'b0;
        refill_addr_o    = '0;
        refill_we_o      = 1'b0;
        refill_valid_o   = 1'b1;   // default: refills write valid lines
        refill_way_sel_o = '0;

        mem_req_o        = 1'b0;
        mem_addr_o       = '0;

        rsp_valid_o      = 1'b0;
        rsp_data_o       = '0;
        rsp_error_o      = 1'b0;

        unique case (state_q)
            ST_IDLE:   ;
            ST_LOOKUP: ;
            ST_HIT: begin
                rsp_valid_o = 1'b1;
                rsp_data_o  = rsp_data_q;
            end
            ST_MISS: begin
                mem_req_o  = 1'b1;
                mem_addr_o = aligned_addr;
            end
            ST_REFILL: begin
                refill_sel_o     = 1'b1;
                refill_addr_o    = aligned_addr;
                refill_we_o      = 1'b1;
                refill_valid_o   = 1'b1;
                refill_way_sel_o = refill_way_q;   // latched, breaks loop
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // Simulation-Only Assertion
    //   hit_way_i is not consumed by the FSM (the datapath owns LRU updates
    //   and produces the victim way for the next refill). It is retained as
    //   an observability port and to enforce the one-hot contract of the
    //   datapath's hit indicator.
    // -------------------------------------------------------------------------
`ifndef SYNTHESIS
    always_ff @(posedge clk_i) begin
        if (state_q == ST_LOOKUP && hit_i)
            assert ($onehot(hit_way_i))
                else $error("controller: hit_i=1 but hit_way_i not one-hot: %b",
                            hit_way_i);
    end
`endif

endmodule
