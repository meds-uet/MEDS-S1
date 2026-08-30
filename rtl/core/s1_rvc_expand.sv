// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
// Written by : Ayesha Anwar, ayesha.anwaar2005@gmail.com
// =============================================================================

module s1_rvc_expand
  import s1_pkg::*;
(
  input  logic              clk_i,
  input  logic              rst_ni,

  // One 32-bit-aligned fetch word from the I$, via s1_fetch. fetch_pc_i is
  // always 4-byte aligned; it is NOT necessarily the PC of the first
  // instruction produced (a carried-over instruction from the previous word
  // may be completed first -- see carry_q below).
  input  logic               fetch_valid_i,
  input  logic [XLEN-1:0]    fetch_pc_i,
  input  logic [31:0]        fetch_data_i,
  input  logic               fetch_err_i,      // instr_err_i for this word

  input  logic               stall_i,

  // A redirect landed (branch mispredict or retire redirect). Clears the
  // skid buffer, the stall-capture buffer, and the realign carry
  // immediately -- all three may hold state belonging to the stale
  // instruction stream (SPEC 8.2: "Branch mispredict: EX flush IF, ID").
  input  logic               flush_i,

  // One instruction per cycle to ID.
  output logic [XLEN-1:0]    instr_pc_o,
  output logic [ILEN-1:0]    instr_o,
  output logic               instr_valid_o,
  output logic               illegal_o,        // reserved/unallocated 16b encoding
  output logic               err_o,            // bus/access fault, see header
  output logic               is_compressed_o,
  output logic               fetch_ready_o
);

  function automatic logic [ILEN:0] rvc_expand(input logic [15:0] c);
    logic [31:0] instr;
    logic        illegal;
    logic [4:0]  rd, rs1, rs2, rdp, rs1p, rs2p;
    logic [11:0] imm12;
    logic [19:0] imm20;
    logic [20:0] jimm21;
    logic [12:0] bimm13;
    logic [9:0]  addi16sp10;
    logic [9:0]  addi4spn10;
    logic [7:0]  ldsd_off;
    logic [6:0]  lwsw_off;     // C.LW / C.SW offset -- offset[6:0], 7 bits
    logic [7:0]  lwswsp_off;   // C.LWSP / C.SWSP offset -- offset[7:0], 8 bits
                                // (sp-relative loads get one extra bit of
                                // reach than register-relative ones; this
                                // is why it is NOT the same width as
                                // lwsw_off -- conflating the two silently
                                // truncated bit 7 for LWSP/SWSP).
    logic [5:0]  shamt6;

    instr   = 32'h0000_0013; // safe default: addi x0,x0,0 -- overwritten below
    illegal = 1'b0;

    rdp  = {2'b01, c[4:2]};
    rs1p = {2'b01, c[9:7]};
    rs2p = {2'b01, c[4:2]};
    rd   = c[11:7];
    rs1  = c[11:7];
    rs2  = c[6:2];

    unique case (c[1:0])
      2'b00: begin
        unique case (c[15:13])
          3'b000: begin // C.ADDI4SPN
            addi4spn10 = {c[10:7], c[12:11], c[5], c[6], 2'b00};
            illegal    = (addi4spn10 == '0);
            instr      = {2'b00, addi4spn10, 5'b00010, 3'b000, rdp, 7'b0010011};
          end
          3'b010: begin // C.LW
            lwsw_off = {c[5], c[12:10], c[6], 2'b00};
            instr    = {5'b0, lwsw_off, rs1p, 3'b010, rdp, 7'b0000011};
          end
          3'b011: begin // C.LD (RV64)
            ldsd_off = {c[6:5], c[12:10], 3'b000};
            instr    = {4'b0, ldsd_off, rs1p, 3'b011, rdp, 7'b0000011};
          end
          3'b110: begin // C.SW
            lwsw_off = {c[5], c[12:10], c[6], 2'b00};
            imm12    = {5'b0, lwsw_off};
            instr    = {imm12[11:5], rs2p, rs1p, 3'b010, imm12[4:0], 7'b0100011};
          end
          3'b111: begin // C.SD (RV64)
            ldsd_off = {c[6:5], c[12:10], 3'b000};
            imm12    = {4'b0, ldsd_off};
            instr    = {imm12[11:5], rs2p, rs1p, 3'b011, imm12[4:0], 7'b0100011};
          end
          default: illegal = 1'b1; // 001/101 = C.FLD/C.FSD (no D); 100 reserved
        endcase
      end

      2'b01: begin
        unique case (c[15:13])
          3'b000: begin // C.ADDI (incl. C.NOP when rd=0, imm=0)
            imm12 = {{6{c[12]}}, c[12], c[6:2]};
            instr = {imm12, rd, 3'b000, rd, 7'b0010011};
          end
          3'b001: begin // C.ADDIW (RV64)
            imm12   = {{6{c[12]}}, c[12], c[6:2]};
            illegal = (rd == '0);
            instr   = {imm12, rd, 3'b000, rd, 7'b0011011};
          end
          3'b010: begin // C.LI (rd=0 is a HINT, not illegal)
            imm12 = {{6{c[12]}}, c[12], c[6:2]};
            instr = {imm12, 5'b00000, 3'b000, rd, 7'b0010011};
          end
          3'b011: begin
            if (rd == 5'd2) begin // C.ADDI16SP
              addi16sp10 = {c[12], c[4:3], c[5], c[2], c[6], 4'b0000};
              illegal    = (addi16sp10 == '0);
              imm12      = {{2{addi16sp10[9]}}, addi16sp10};
              instr      = {imm12, 5'b00010, 3'b000, 5'b00010, 7'b0010011};
            end else begin // C.LUI
              imm20   = {{14{c[12]}}, c[12], c[6:2]};
              illegal = (rd == '0) || (imm20 == '0);
              instr   = {imm20, rd, 7'b0110111};
            end
          end
          3'b100: begin
            unique case (c[11:10])
              2'b00: begin // C.SRLI (RV64: full 6b shamt)
                shamt6 = {c[12], c[6:2]};
                instr  = {6'b000000, shamt6, rs1p, 3'b101, rdp, 7'b0010011};
              end
              2'b01: begin // C.SRAI
                shamt6 = {c[12], c[6:2]};
                instr  = {6'b010000, shamt6, rs1p, 3'b101, rdp, 7'b0010011};
              end
              2'b10: begin // C.ANDI
                imm12 = {{6{c[12]}}, c[12], c[6:2]};
                instr = {imm12, rs1p, 3'b111, rdp, 7'b0010011};
              end
              2'b11: begin
                unique case ({c[12], c[6:5]})
                  3'b000:  instr = {7'b0100000, rs2p, rs1p, 3'b000, rdp, 7'b0110011}; // C.SUB
                  3'b001:  instr = {7'b0000000, rs2p, rs1p, 3'b100, rdp, 7'b0110011}; // C.XOR
                  3'b010:  instr = {7'b0000000, rs2p, rs1p, 3'b110, rdp, 7'b0110011}; // C.OR
                  3'b011:  instr = {7'b0000000, rs2p, rs1p, 3'b111, rdp, 7'b0110011}; // C.AND
                  3'b100:  instr = {7'b0100000, rs2p, rs1p, 3'b000, rdp, 7'b0111011}; // C.SUBW
                  3'b101:  instr = {7'b0000000, rs2p, rs1p, 3'b000, rdp, 7'b0111011}; // C.ADDW
                  default: illegal = 1'b1;                                            // reserved
                endcase
              end
            endcase
          end
          3'b101: begin // C.J
            jimm21 = {{9{c[12]}},
                      c[12], c[8], c[10], c[9], c[6], c[7], c[2], c[11], c[5], c[4], c[3], 1'b0};
            instr  = {jimm21[20], jimm21[10:1], jimm21[11], jimm21[19:12], 5'b00000, 7'b1101111};
          end
          3'b110, 3'b111: begin // C.BEQZ / C.BNEZ
            bimm13 = {{4{c[12]}}, c[12], c[6], c[5], c[2], c[11], c[10], c[4], c[3], 1'b0};
            instr  = {bimm13[12], bimm13[10:5], 5'b00000, rs1p,
                      (c[13] ? 3'b001 : 3'b000), bimm13[4:1], bimm13[11], 7'b1100011};
          end
          default: illegal = 1'b1;
        endcase
      end

      2'b10: begin
        unique case (c[15:13])
          3'b000: begin // C.SLLI (rd=0 / shamt=0 are HINTs, not illegal)
            shamt6 = {c[12], c[6:2]};
            instr  = {6'b000000, shamt6, rd, 3'b001, rd, 7'b0010011};
          end
          3'b010: begin // C.LWSP
            lwswsp_off = {c[3:2], c[12], c[6:4], 2'b00};
            illegal    = (rd == '0);
            imm12      = {4'b0, lwswsp_off};
            instr      = {imm12, 5'b00010, 3'b010, rd, 7'b0000011};
          end
          3'b011: begin // C.LDSP (RV64)
            ldsd_off = {c[4:2], c[12], c[6:5], 3'b000};
            illegal  = (rd == '0);
            imm12    = {3'b0, ldsd_off};
            instr    = {imm12, 5'b00010, 3'b011, rd, 7'b0000011};
          end
          3'b100: begin
            if (!c[12]) begin
              if (rs2 == '0) begin // C.JR
                illegal = (rd == '0);
                instr   = {12'b0, rd, 3'b000, 5'b00000, 7'b1100111};
              end else begin // C.MV
                instr = {7'b0000000, rs2, 5'b00000, 3'b000, rd, 7'b0110011};
              end
            end else begin
              if (rd == '0 && rs2 == '0) begin
                instr = 32'h0010_0073; // C.EBREAK
              end else if (rs2 == '0) begin // C.JALR
                instr = {12'b0, rd, 3'b000, 5'b00001, 7'b1100111};
              end else begin // C.ADD (incl. rd=0 hint)
                instr = {7'b0000000, rs2, rd, 3'b000, rd, 7'b0110011};
              end
            end
          end
          3'b110: begin // C.SWSP
            lwswsp_off = {c[8:7], c[12:9], 2'b00};
            imm12      = {4'b0, lwswsp_off};
            instr      = {imm12[11:5], rs2, 5'b00010, 3'b010, imm12[4:0], 7'b0100011};
          end
          3'b111: begin // C.SDSP (RV64)
            ldsd_off = {c[9:7], c[12:10], 3'b000};
            imm12    = {3'b0, ldsd_off};
            instr    = {imm12[11:5], rs2, 5'b00010, 3'b011, imm12[4:0], 7'b0100011};
          end
          default: illegal = 1'b1; // 001/101 = C.FLDSP/C.FSDSP (no D)
        endcase
      end

      default: illegal = 1'b1; // c[1:0]==11 must never reach this function --
                                // caller treats that word as already 32-bit.
    endcase

    return {illegal, instr};
  endfunction
  logic            carry_valid_q;
  logic [15:0]     carry_half_q;
  logic [XLEN-1:0] carry_pc_q;
  logic            carry_err_q;

  logic            skid_valid_q;
  logic [ILEN-1:0] skid_instr_q;
  logic [XLEN-1:0] skid_pc_q;
  logic            skid_illegal_q;
  logic            skid_err_q;
  logic            skid_compressed_q;

  logic            stall_cap_valid_q;
  logic [XLEN-1:0] stall_cap_pc_q;
  logic [31:0]     stall_cap_data_q;
  logic            stall_cap_err_q;

  // ---------------------------------------------------------------------------
  // Effective fetch -- the word actually processed this cycle. Either the
  // live MEM-REQ response, or (if one arrived during a stall and was
  // captured) the previously-captured word, replayed once unstalled. Never
  // both, and never valid while still stalled -- see fetch_ready_o note and
  // header: single-outstanding upstream means at most one of these is ever
  // pending at a time.
  // ---------------------------------------------------------------------------
  logic            eff_fetch_valid;
  logic [XLEN-1:0] eff_fetch_pc;
  logic [31:0]     eff_fetch_data;
  logic            eff_fetch_err;

  assign eff_fetch_valid = !stall_i && (stall_cap_valid_q || fetch_valid_i);
  assign eff_fetch_pc    = stall_cap_valid_q ? stall_cap_pc_q   : fetch_pc_i;
  assign eff_fetch_data  = stall_cap_valid_q ? stall_cap_data_q : fetch_data_i;
  assign eff_fetch_err   = stall_cap_valid_q ? stall_cap_err_q  : fetch_err_i;

  logic [15:0] h_lo, h_hi;
  assign h_lo = eff_fetch_data[15:0];
  assign h_hi = eff_fetch_data[31:16];

  logic [ILEN:0]   exp_lo, exp_hi;
  assign exp_lo = rvc_expand(h_lo);
  assign exp_hi = rvc_expand(h_hi);

  logic            first_valid, first_illegal, first_err, first_compressed;
  logic [XLEN-1:0] first_pc;
  logic [ILEN-1:0] first_instr;

  logic            second_valid, second_illegal, second_err, second_compressed;
  logic [XLEN-1:0] second_pc;
  logic [ILEN-1:0] second_instr;

  logic            next_carry_valid;
  logic [15:0]     next_carry_half;
  logic [XLEN-1:0] next_carry_pc;
  logic            next_carry_err;

  always_comb begin
    // Pre-assigned defaults (R-C3) -- no output path may fall through unset.
    first_valid       = eff_fetch_valid;
    first_illegal     = 1'b0;
    first_err         = eff_fetch_err;
    first_compressed  = 1'b0;
    first_pc          = eff_fetch_pc;
    first_instr       = eff_fetch_data;
    second_valid      = 1'b0;
    second_illegal    = 1'b0;
    second_err        = 1'b0;
    second_compressed = 1'b0;
    second_pc         = '0;
    second_instr      = '0;
    next_carry_valid  = 1'b0;
    next_carry_half   = '0;
    next_carry_pc     = '0;
    next_carry_err    = 1'b0;

    if (carry_valid_q) begin
      // Completes the instruction that started in the previous fetch word.
      // Faulted if either half's beat faulted.
      first_instr      = {h_lo, carry_half_q};
      first_pc         = carry_pc_q;
      first_compressed = 1'b0;
      first_err        = carry_err_q || eff_fetch_err;

      // What's left in this word is h_hi alone, starting right after.
      if (h_hi[1:0] != 2'b11) begin
        second_valid      = eff_fetch_valid;
        second_illegal    = exp_hi[ILEN];
        second_err        = eff_fetch_err;
        second_instr      = exp_hi[ILEN-1:0];
        second_pc         = carry_pc_q + XLEN'(4);
        second_compressed = 1'b1;
      end else begin
        next_carry_valid = eff_fetch_valid;
        next_carry_half  = h_hi;
        next_carry_pc    = carry_pc_q + XLEN'(4);
        next_carry_err   = eff_fetch_err;
      end
    end else if (h_lo[1:0] != 2'b11) begin
      // First instruction is compressed, at the start of this word.
      first_illegal    = exp_lo[ILEN];
      first_instr      = exp_lo[ILEN-1:0];
      first_compressed = 1'b1;

      if (h_hi[1:0] != 2'b11) begin
        second_valid      = eff_fetch_valid;
        second_illegal    = exp_hi[ILEN];
        second_err        = eff_fetch_err;
        second_instr      = exp_hi[ILEN-1:0];
        second_pc         = eff_fetch_pc + XLEN'(2);
        second_compressed = 1'b1;
      end else begin
        next_carry_valid = eff_fetch_valid;
        next_carry_half  = h_hi;
        next_carry_pc    = eff_fetch_pc + XLEN'(2);
        next_carry_err   = eff_fetch_err;
      end
    end
    // else: h_lo[1:0]==11 and no carry -- the whole word is one 32-bit
    // instruction. Defaults already cover this case exactly.
  end

  // ---------------------------------------------------------------------------
  // Stall-capture update. Independent of the main !stall_i-gated block below
  // because capture must happen PRECISELY when stall_i=1 -- that is the
  // whole point.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stall_cap_valid_q <= 1'b0;
      stall_cap_pc_q    <= '0;
      stall_cap_data_q  <= '0;
      stall_cap_err_q   <= 1'b0;
    end else if (flush_i) begin
      stall_cap_valid_q <= 1'b0;
    end else if (stall_i && fetch_valid_i && !stall_cap_valid_q) begin
      stall_cap_valid_q <= 1'b1;
      stall_cap_pc_q    <= fetch_pc_i;
      stall_cap_data_q  <= fetch_data_i;
      stall_cap_err_q   <= fetch_err_i;
    end else if (!stall_i && stall_cap_valid_q) begin
      stall_cap_valid_q <= 1'b0; // consumed this cycle via eff_fetch_*
    end
  end

  // ---------------------------------------------------------------------------
  // Main state update -- carry and skid. Gated on !stall_i: draining skid_q
  // also requires ID to be able to accept it this cycle.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      carry_valid_q     <= 1'b0;
      carry_half_q      <= '0;
      carry_pc_q        <= '0;
      carry_err_q       <= 1'b0;
      skid_valid_q       <= 1'b0;
      skid_instr_q       <= '0;
      skid_pc_q          <= '0;
      skid_illegal_q      <= 1'b0;
      skid_err_q          <= 1'b0;
      skid_compressed_q   <= 1'b0;
    end else if (flush_i) begin
      carry_valid_q <= 1'b0;
      skid_valid_q  <= 1'b0;
    end else if (!stall_i) begin
      if (skid_valid_q) begin
        // Draining the skid buffer this cycle; fetch_ready_o was low, so
        // no new word was accepted and carry_q cannot change.
        skid_valid_q <= 1'b0;
      end else if (eff_fetch_valid) begin
        carry_valid_q <= next_carry_valid;
        carry_half_q  <= next_carry_half;
        carry_pc_q    <= next_carry_pc;
        carry_err_q   <= next_carry_err;

        skid_valid_q      <= second_valid;
        skid_instr_q      <= second_instr;
        skid_pc_q         <= second_pc;
        skid_illegal_q    <= second_illegal;
        skid_err_q        <= second_err;
        skid_compressed_q <= second_compressed;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Output mux -- skid buffer drains first, ahead of anything new.
  // ---------------------------------------------------------------------------
  assign instr_valid_o   = flush_i ? 1'b0 : (skid_valid_q ? 1'b1 : first_valid);
  assign instr_pc_o      = skid_valid_q ? skid_pc_q : first_pc;
  assign instr_o         = skid_valid_q ? skid_instr_q : first_instr;
  assign illegal_o       = skid_valid_q ? skid_illegal_q : first_illegal;
  assign err_o           = skid_valid_q ? skid_err_q : first_err;
  assign is_compressed_o = skid_valid_q ? skid_compressed_q : first_compressed;

  assign fetch_ready_o = !skid_valid_q && !stall_i;

endmodule
