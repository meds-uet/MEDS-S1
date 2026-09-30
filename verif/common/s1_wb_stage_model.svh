// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Eman Nasar (fatehulnasareman@gmail.com) (Sep 2026)
// Modified By  :
//
// s1_wb_stage_model.svh : reference models for tb_s1_wb_stage       [WIP -- T-02]
// Description  :
// Included inside tb_s1_wb_stage.  The point of this file is that the expected
// outputs are never derived from the DUT's inputs.  A test case is an `ins_t`,
// an abstract statement of what the instruction did -- "wrote x7 with this
// value", "trapped with this code", "was never offered to a coprocessor".  It
// is rendered twice and independently:
//
//   render_wb()  -> mem_wb_t, the MEM/WB bundle s1_mem_stage would have built
//   expect()     -> exp_t,    the completion-buffer write and bypass the spec
//                             says must follow, read out of SPEC 9.1 and 9.2
//
// The two renderings share no code.  A transcription mistake in one of them
// shows up as a mismatch, which is the property a model copied out of the RTL
// cannot give you.
// =============================================================================

  localparam int unsigned NB = XLEN / 8;          // RVFI mask width

  // Instruction classes the main pipe can hand to WB.  They differ only in
  // which fields are meaningful, which is exactly what makes them worth
  // separating: most WB bugs are a field used on the wrong class.
  localparam int K_ALU    = 0,   // register result, no memory, no CSR
                 K_LOAD   = 1,   // register result from memory, rmask set
                 K_STORE  = 2,   // no register result, wmask set, owns an SB entry
                 K_BRANCH = 3,   // no register result, next_pc is the taken target
                 K_JAL    = 4,   // link register, next_pc is the target
                 K_CSR    = 5,   // register result and a pending CSR write
                 K_MXIF   = 6,   // candidate placeholder: complete = 0
                 K_NONE   = 7;   // fence, nop to x0, anything writing nothing

  typedef struct {
    int                    kind;
    logic [CB_IDX_W-1:0]   idx;
    bit                    complete;
    logic [REG_ADDR_W-1:0] rd;
    bit                    rd_we;
    logic [XLEN-1:0]       result;
    logic [XLEN-1:0]       next_pc;
    bit                    csr_we;
    logic [11:0]           csr_addr;
    logic [XLEN-1:0]       csr_wdata;
    bit                    sb_alloc;
    bit                    exc;
    logic [5:0]            exccode;
    logic [XLEN-1:0]       exctval;
    logic [XLEN-1:0]       maddr;
    logic [NB-1:0]         rmask;
    logic [NB-1:0]         wmask;
    logic [XLEN-1:0]       mrdata;
    logic [XLEN-1:0]       mwdata;
  } ins_t;

  // What the DUT must produce for one presented instruction.
  typedef struct {
    bit                    cb_we;
    logic [CB_IDX_W-1:0]   cb_idx;
    wb_upd_t               upd;
  } exp_t;

  // ---------------------------------------------------------------------------
  // Rendering 1: the MEM/WB bundle
  // ---------------------------------------------------------------------------
  function automatic mem_wb_t render_wb(ins_t n);
    mem_wb_t w;
    w           = '0;
    w.cb_idx    = n.idx;
    w.complete  = n.complete;
    w.rd        = n.rd;
    w.rd_we     = n.rd_we;
    w.result    = n.result;
    w.next_pc   = n.next_pc;
    w.csr_we    = n.csr_we;
    w.csr_addr  = n.csr_addr;
    w.csr_wdata = n.csr_wdata;
    w.sb_alloc  = n.sb_alloc;
    w.exc       = n.exc;
    w.exccode   = n.exccode;
    w.exctval   = n.exctval;
    w.mem_addr  = n.maddr;
    w.mem_rmask = n.rmask;
    w.mem_wmask = n.wmask;
    w.mem_rdata = n.mrdata;
    w.mem_wdata = n.mwdata;
    return w;
  endfunction

  // ---------------------------------------------------------------------------
  // Rendering 2: what the spec requires, from the rules rather than the bundle
  // ---------------------------------------------------------------------------

  // SPEC 9.2 step 1 writes the register file "if rd_we", step 6 skips steps 1-3
  // on a trap, and x0 is not architectural state in RV64I.  Three independent
  // reasons an instruction may update no register.
  function automatic bit arch_reg_write(ins_t n);
    if (!n.rd_we)   return 0;            // the instruction has no destination
    if (n.exc)      return 0;            // SPEC 9.2 step 6
    if (n.rd == '0) return 0;            // x0 reads as zero, always
    return 1;
  endfunction

  // Whose completion-buffer entry is this?
  //
  // INTERFACES.md 1.4a: an MXIF candidate's entry belongs to the MXIF port from
  // the moment it is offloaded, and it is offloaded at the head -- after WB.
  // A candidate that trapped on its way down is never offered to anyone, so it
  // stays the main pipe's.  Stated as the two reasons rather than as one
  // expression, because they are two different rules from two different specs.
  function automatic bit main_pipe_owns(ins_t n);
    if (n.complete) return 1;   // the main pipe produced this instruction's result
    if (n.exc)      return 1;   // it trapped, so nobody else will ever claim it
    return 0;                   // MXIF candidate: the port owns the entry
  endfunction

  function automatic exp_t golden(ins_t n, bit valid, bit flushed);
    exp_t e;
    bit   owns, writes;

    owns   = main_pipe_owns(n);
    writes = arch_reg_write(n);

    e        = '{default: '0};
    e.cb_we  = valid && owns && !flushed;
    e.cb_idx = n.idx;

    // An entry WB does not own keeps whatever ID put in it; the DUT's payload
    // is then don't-care and the testbench does not look at it.
    if (!owns) return e;

    e.upd.done       = 1'b1;             // resolved, by definition of `owns`
    e.upd.norollback = 1'b1;             // SPEC 9.1: always 1 for the main pipe
    e.upd.from_main  = 1'b1;

    e.upd.rd         = writes ? n.rd     : '0;
    e.upd.rd_we      = writes;
    e.upd.result     = writes ? n.result : '0;
    e.upd.next_pc    = n.next_pc;

    e.upd.exc        = n.exc;
    e.upd.exccode    = n.exccode;
    e.upd.exctval    = n.exctval;

    e.upd.csr.we     = n.csr_we && !n.exc;    // SPEC 9.2 step 6 again, step 2
    e.upd.csr.addr   = n.csr_addr;
    e.upd.csr.wdata  = n.csr_wdata;

    e.upd.sb_alloc   = n.sb_alloc;            // not gated: see the module header

    e.upd.rvfi.addr  = n.maddr;
    e.upd.rvfi.rmask = n.rmask;
    e.upd.rvfi.wmask = n.wmask;
    e.upd.rvfi.rdata = n.mrdata;
    e.upd.rvfi.wdata = n.mwdata;

    return e;
  endfunction

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  function automatic ins_t blank_ins();
    ins_t n;
    n = '{default: '0};
    n.kind     = K_NONE;
    n.complete = 1;
    return n;
  endfunction

  // A completion of the given class, with every meaningful field randomised and
  // every field the class does not use left at zero -- so a DUT that reads a
  // field it should not is caught by the field it should have read instead.
  function automatic ins_t make_ins(int kind, bit exc = 0);
    ins_t n;
    n          = blank_ins();
    n.kind     = kind;
    n.idx      = CB_IDX_W'($urandom);
    n.complete = (kind != K_MXIF);
    n.next_pc  = {$urandom, $urandom} & ~64'h1;
    n.exc      = exc;

    if (exc) begin
      // MEM never reports an exception and a store-buffer allocation together,
      // so the legal stimulus does not either.  The illegal combination is
      // driven deliberately, once, by the directed test that pins the
      // documented pass-through.
      n.exccode = 6'($urandom % 16);
      n.exctval = {$urandom, $urandom};
    end

    unique case (kind)
      K_ALU: begin
        n.rd_we  = 1;
        n.rd     = REG_ADDR_W'($urandom);
        n.result = {$urandom, $urandom};
      end
      K_LOAD: begin
        n.rd_we  = 1;
        n.rd     = REG_ADDR_W'($urandom);
        n.result = {$urandom, $urandom};
        n.maddr  = {$urandom, $urandom};
        n.rmask  = NB'($urandom) | NB'(1);
        n.mrdata = {$urandom, $urandom};
      end
      K_STORE: begin
        n.maddr    = {$urandom, $urandom};
        n.wmask    = NB'($urandom) | NB'(1);
        n.mwdata   = {$urandom, $urandom};
        n.sb_alloc = ~exc;
      end
      K_BRANCH: begin
        n.next_pc = {$urandom, $urandom} & ~64'h1;
      end
      K_JAL: begin
        n.rd_we   = 1;
        n.rd      = REG_ADDR_W'($urandom);
        n.result  = {$urandom, $urandom};    // the link address
        n.next_pc = {$urandom, $urandom} & ~64'h1;
      end
      K_CSR: begin
        n.rd_we     = 1;
        n.rd        = REG_ADDR_W'($urandom);
        n.result    = {$urandom, $urandom};  // the old CSR value
        n.csr_we    = 1;
        n.csr_addr  = 12'($urandom);
        n.csr_wdata = {$urandom, $urandom};
      end
      K_MXIF: begin
        // The placeholder carries the decoder's guess at a destination.  If WB
        // writes it into the entry, the coprocessor's real rd is lost -- so the
        // stimulus always sets one, and it is always wrong to use.
        n.rd_we  = 1'($urandom);
        n.rd     = REG_ADDR_W'($urandom);
        n.result = {$urandom, $urandom};
      end
      default: ;                             // K_NONE writes nothing at all
    endcase
    return n;
  endfunction

  function automatic ins_t rand_ins();
    int  k;
    bit  e;
    ins_t n;
    k = $urandom % 100;
    e = (($urandom % 100) < 12);
    if      (k < 34) n = make_ins(K_ALU,    e);
    else if (k < 54) n = make_ins(K_LOAD,   e);
    else if (k < 70) n = make_ins(K_STORE,  e);
    else if (k < 78) n = make_ins(K_BRANCH, e);
    else if (k < 84) n = make_ins(K_JAL,    e);
    else if (k < 90) n = make_ins(K_CSR,    e);
    else if (k < 96) n = make_ins(K_MXIF,   e);
    else             n = make_ins(K_NONE,   e);
    // x0 as a destination is rare in real code and is the case the bypass must
    // not answer, so the stimulus forces it far more often than a compiler would.
    if (n.rd_we && ($urandom % 100) < 15) n.rd = '0;
    return n;
  endfunction

  // ---------------------------------------------------------------------------
  // Multi-cycle channels
  //
  // The model keeps its own rotation pointer per configuration and advances it
  // by the rule the module documents -- past whichever channel was granted --
  // rather than by watching the DUT's.  A pointer copied from the RTL would
  // agree with any arbiter, including a broken one.
  // ---------------------------------------------------------------------------
  localparam int UC_MAX = 3;

  int m_rr [UC_MAX+1];            // indexed by N_UC, so m_rr[2] is the N_UC=2 instance

  function automatic int golden_grant(bit uv [UC_MAX], int n, int rr, bit port_free);
    if (!port_free) return -1;
    for (int i = 0; i < n; i++) begin
      int k;
      k = (rr + i) % n;
      if (uv[k]) return k;
    end
    return -1;
  endfunction

  // A multi-cycle result: an entry index, a register and a value.  It carries
  // nothing about the instruction, which is the whole point of `from_main`, and
  // no rd_we, because #15's md_req_t has none to mirror.
  function automatic md_rsp_t make_uc();
    md_rsp_t r;
    int      z;
    r        = '0;
    r.cb_idx = CB_IDX_W'($urandom);
    z        = $urandom % 100;
    r.rd     = (z < 15) ? REG_ADDR_W'(0) : REG_ADDR_W'($urandom);
    r.result = {$urandom, $urandom};
    return r;
  endfunction

  function automatic exp_t golden_uc(md_rsp_t u);
    exp_t e;
    bit   writes;
    // RV64M raises no exceptions and every multiply and divide writes its
    // destination, so naming x0 is the only way a unit result writes nothing.
    writes           = (u.rd != '0);
    e                = '{default: '0};
    e.cb_we          = 1'b1;
    e.cb_idx         = u.cb_idx;
    e.upd.done       = 1'b1;
    e.upd.norollback = 1'b1;
    e.upd.from_main  = 1'b0;
    e.upd.rd         = writes ? u.rd     : '0;
    e.upd.rd_we      = writes;
    e.upd.result     = writes ? u.result : '0;
    return e;
  endfunction
