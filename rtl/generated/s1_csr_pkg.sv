// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// DO NOT EDIT -- generated from core_csr.yaml by gen/s1_csr_gen.py

package s1_csr_pkg;

  typedef enum logic [1:0] {
    CSR_CLASS_CORE,
    CSR_CLASS_COUNTER,
    CSR_CLASS_EXTERNAL
  } csr_class_e;

  typedef enum logic [1:0] {
    CSR_PRESENT_IMPL,
    CSR_PRESENT_RO_ZERO,
    CSR_PRESENT_ALIAS
  } csr_presence_e;

  typedef struct packed {
    logic [11:0]   addr;
    csr_class_e    cls;
    csr_presence_e presence;
    logic [1:0]    min_priv;       // addr[9:8] encoding: 0 U, 1 S, 3 M
    logic          read_only;
    logic          debug_only;
    logic          gate_u;         // exists only on configs with U-mode
    logic          gate_s;         // exists only on configs with S-mode
    logic          gate_pmp;       // exists only on configs with PMP regions
    logic          hw_write;       // written by trap entry, xRET or interrupt lines
    logic          has_warl;       // 1 => route through s1_csr_legalize
    logic [11:0]   view_addr;      // alias: the CSR that holds the state
    logic [63:0]   view_mask;      // alias: bits visible through the view
    logic [63:0]   reset_val;
    logic [63:0]   write_mask;     // WPRI: 0 = reserved, ignore write, read 0
    logic [63:0]   wmask_if_s;     // extra writable bits with S-mode
    logic [63:0]   ro_const;       // read-only bits that read as 1
    logic [63:0]   ro_const_if_u;
    logic [63:0]   ro_const_if_s;
  } csr_desc_t;

  // Every CSR in the table, decoded or not.
  localparam logic [11:0] CSR_MVENDORID       = 12'hf11;
  localparam logic [11:0] CSR_MARCHID         = 12'hf12;
  localparam logic [11:0] CSR_MIMPID          = 12'hf13;
  localparam logic [11:0] CSR_MHARTID         = 12'hf14;
  localparam logic [11:0] CSR_MSTATUS         = 12'h300;
  localparam logic [11:0] CSR_MISA            = 12'h301;
  localparam logic [11:0] CSR_MEDELEG         = 12'h302;
  localparam logic [11:0] CSR_MIDELEG         = 12'h303;
  localparam logic [11:0] CSR_MIE             = 12'h304;
  localparam logic [11:0] CSR_MTVEC           = 12'h305;
  localparam logic [11:0] CSR_MCOUNTEREN      = 12'h306;
  localparam logic [11:0] CSR_MENVCFG         = 12'h30a;
  localparam logic [11:0] CSR_MCOUNTINHIBIT   = 12'h320;
  localparam logic [11:0] CSR_MHPMEVENT3      = 12'h323;
  localparam logic [11:0] CSR_MHPMEVENT4      = 12'h324;
  localparam logic [11:0] CSR_MHPMEVENT5      = 12'h325;
  localparam logic [11:0] CSR_MHPMEVENT6      = 12'h326;
  localparam logic [11:0] CSR_MHPMEVENT7      = 12'h327;
  localparam logic [11:0] CSR_MHPMEVENT8      = 12'h328;
  localparam logic [11:0] CSR_MHPMEVENT9      = 12'h329;
  localparam logic [11:0] CSR_MHPMEVENT10     = 12'h32a;
  localparam logic [11:0] CSR_MHPMEVENT11     = 12'h32b;
  localparam logic [11:0] CSR_MHPMEVENT12     = 12'h32c;
  localparam logic [11:0] CSR_MHPMEVENT13     = 12'h32d;
  localparam logic [11:0] CSR_MHPMEVENT14     = 12'h32e;
  localparam logic [11:0] CSR_MHPMEVENT15     = 12'h32f;
  localparam logic [11:0] CSR_MSCRATCH        = 12'h340;
  localparam logic [11:0] CSR_MEPC            = 12'h341;
  localparam logic [11:0] CSR_MCAUSE          = 12'h342;
  localparam logic [11:0] CSR_MTVAL           = 12'h343;
  localparam logic [11:0] CSR_MIP             = 12'h344;
  localparam logic [11:0] CSR_PMPCFG0         = 12'h3a0;
  localparam logic [11:0] CSR_PMPCFG1         = 12'h3a1;
  localparam logic [11:0] CSR_PMPCFG2         = 12'h3a2;
  localparam logic [11:0] CSR_PMPCFG3         = 12'h3a3;
  localparam logic [11:0] CSR_PMPADDR0        = 12'h3b0;
  localparam logic [11:0] CSR_PMPADDR1        = 12'h3b1;
  localparam logic [11:0] CSR_PMPADDR2        = 12'h3b2;
  localparam logic [11:0] CSR_PMPADDR3        = 12'h3b3;
  localparam logic [11:0] CSR_PMPADDR4        = 12'h3b4;
  localparam logic [11:0] CSR_PMPADDR5        = 12'h3b5;
  localparam logic [11:0] CSR_PMPADDR6        = 12'h3b6;
  localparam logic [11:0] CSR_PMPADDR7        = 12'h3b7;
  localparam logic [11:0] CSR_PMPADDR8        = 12'h3b8;
  localparam logic [11:0] CSR_PMPADDR9        = 12'h3b9;
  localparam logic [11:0] CSR_PMPADDR10       = 12'h3ba;
  localparam logic [11:0] CSR_PMPADDR11       = 12'h3bb;
  localparam logic [11:0] CSR_PMPADDR12       = 12'h3bc;
  localparam logic [11:0] CSR_PMPADDR13       = 12'h3bd;
  localparam logic [11:0] CSR_PMPADDR14       = 12'h3be;
  localparam logic [11:0] CSR_PMPADDR15       = 12'h3bf;
  localparam logic [11:0] CSR_MCYCLE          = 12'hb00;
  localparam logic [11:0] CSR_MINSTRET        = 12'hb02;
  localparam logic [11:0] CSR_MHPMCOUNTER3    = 12'hb03;
  localparam logic [11:0] CSR_MHPMCOUNTER4    = 12'hb04;
  localparam logic [11:0] CSR_MHPMCOUNTER5    = 12'hb05;
  localparam logic [11:0] CSR_MHPMCOUNTER6    = 12'hb06;
  localparam logic [11:0] CSR_MHPMCOUNTER7    = 12'hb07;
  localparam logic [11:0] CSR_MHPMCOUNTER8    = 12'hb08;
  localparam logic [11:0] CSR_MHPMCOUNTER9    = 12'hb09;
  localparam logic [11:0] CSR_MHPMCOUNTER10   = 12'hb0a;
  localparam logic [11:0] CSR_MHPMCOUNTER11   = 12'hb0b;
  localparam logic [11:0] CSR_MHPMCOUNTER12   = 12'hb0c;
  localparam logic [11:0] CSR_MHPMCOUNTER13   = 12'hb0d;
  localparam logic [11:0] CSR_MHPMCOUNTER14   = 12'hb0e;
  localparam logic [11:0] CSR_MHPMCOUNTER15   = 12'hb0f;
  localparam logic [11:0] CSR_SSTATUS         = 12'h100;
  localparam logic [11:0] CSR_SIE             = 12'h104;
  localparam logic [11:0] CSR_STVEC           = 12'h105;
  localparam logic [11:0] CSR_SCOUNTEREN      = 12'h106;
  localparam logic [11:0] CSR_SSCRATCH        = 12'h140;
  localparam logic [11:0] CSR_SEPC            = 12'h141;
  localparam logic [11:0] CSR_SCAUSE          = 12'h142;
  localparam logic [11:0] CSR_STVAL           = 12'h143;
  localparam logic [11:0] CSR_SIP             = 12'h144;
  localparam logic [11:0] CSR_SATP            = 12'h180;
  localparam logic [11:0] CSR_CYCLE           = 12'hc00;
  localparam logic [11:0] CSR_TIME            = 12'hc01;
  localparam logic [11:0] CSR_INSTRET         = 12'hc02;
  localparam logic [11:0] CSR_HPMCOUNTER3     = 12'hc03;
  localparam logic [11:0] CSR_HPMCOUNTER4     = 12'hc04;
  localparam logic [11:0] CSR_HPMCOUNTER5     = 12'hc05;
  localparam logic [11:0] CSR_HPMCOUNTER6     = 12'hc06;
  localparam logic [11:0] CSR_HPMCOUNTER7     = 12'hc07;
  localparam logic [11:0] CSR_HPMCOUNTER8     = 12'hc08;
  localparam logic [11:0] CSR_HPMCOUNTER9     = 12'hc09;
  localparam logic [11:0] CSR_HPMCOUNTER10    = 12'hc0a;
  localparam logic [11:0] CSR_HPMCOUNTER11    = 12'hc0b;
  localparam logic [11:0] CSR_HPMCOUNTER12    = 12'hc0c;
  localparam logic [11:0] CSR_HPMCOUNTER13    = 12'hc0d;
  localparam logic [11:0] CSR_HPMCOUNTER14    = 12'hc0e;
  localparam logic [11:0] CSR_HPMCOUNTER15    = 12'hc0f;
  localparam logic [11:0] CSR_TSELECT         = 12'h7a0;
  localparam logic [11:0] CSR_TDATA1          = 12'h7a1;
  localparam logic [11:0] CSR_TDATA2          = 12'h7a2;
  localparam logic [11:0] CSR_TDATA3          = 12'h7a3;
  localparam logic [11:0] CSR_DCSR            = 12'h7b0;
  localparam logic [11:0] CSR_DPC             = 12'h7b1;
  localparam logic [11:0] CSR_DSCRATCH0       = 12'h7b2;
  localparam logic [11:0] CSR_DSCRATCH1       = 12'h7b3;
  localparam logic [11:0] CSR_MEDS_S1_VERSION = 12'h7c0;

  localparam int unsigned NUM_CSRS = 26;

  localparam csr_desc_t CSR_TABLE [NUM_CSRS] = '{
    // mvendorid
    '{addr: 12'hf11, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_RO_ZERO,
      min_priv: 2'd3, read_only: 1'b1, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // marchid
    '{addr: 12'hf12, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_RO_ZERO,
      min_priv: 2'd3, read_only: 1'b1, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mimpid
    '{addr: 12'hf13, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_RO_ZERO,
      min_priv: 2'd3, read_only: 1'b1, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mhartid
    '{addr: 12'hf14, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b1, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mstatus
    '{addr: 12'h300, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b1, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000021888,
      wmask_if_s:    64'h0000000000000122,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000200000000,
      ro_const_if_s: 64'h0000000800000000},
    // misa
    '{addr: 12'h301, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h8000000000001104,
      ro_const_if_u: 64'h0000000000100000,
      ro_const_if_s: 64'h0000000000000000},
    // medeleg
    '{addr: 12'h302, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h000000000000b3ff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mideleg
    '{addr: 12'h303, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000222,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mie
    '{addr: 12'h304, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000888,
      wmask_if_s:    64'h0000000000000222,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mtvec
    '{addr: 12'h305, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b1, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // menvcfg
    '{addr: 12'h30a, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_RO_ZERO,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b1, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mscratch
    '{addr: 12'h340, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mepc
    '{addr: 12'h341, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hfffffffffffffffe,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mcause
    '{addr: 12'h342, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mtval
    '{addr: 12'h343, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // mip
    '{addr: 12'h344, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000222,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // sstatus
    '{addr: 12'h100, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_ALIAS,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h300,
      view_mask:     64'h80000003000de762,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000122,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // sie
    '{addr: 12'h104, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_ALIAS,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h304,
      view_mask:     64'h0000000000000222,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000222,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // stvec
    '{addr: 12'h105, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b1, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // sscratch
    '{addr: 12'h140, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // sepc
    '{addr: 12'h141, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hfffffffffffffffe,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // scause
    '{addr: 12'h142, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // stval
    '{addr: 12'h143, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b1, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'hffffffffffffffff,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // sip
    '{addr: 12'h144, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_ALIAS,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h344,
      view_mask:     64'h0000000000000222,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000002,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // satp
    '{addr: 12'h180, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_RO_ZERO,
      min_priv: 2'd1, read_only: 1'b0, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b1, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000000,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000},
    // meds_s1_version
    '{addr: 12'h7c0, cls: CSR_CLASS_CORE, presence: CSR_PRESENT_IMPL,
      min_priv: 2'd3, read_only: 1'b1, debug_only: 1'b0,
      gate_u: 1'b0, gate_s: 1'b0, gate_pmp: 1'b0,
      hw_write: 1'b0, has_warl: 1'b0, view_addr: 12'h000,
      view_mask:     64'h0000000000000000,
      reset_val:     64'h0000000000000000,
      write_mask:    64'h0000000000000000,
      wmask_if_s:    64'h0000000000000000,
      ro_const:      64'h0000000000000100,
      ro_const_if_u: 64'h0000000000000000,
      ro_const_if_s: 64'h0000000000000000}
  };

endpackage
