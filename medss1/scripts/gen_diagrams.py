#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""
Generate the MEDS-S1 specification figures as SVG.

Every figure in the specification PDF is produced here, from code, so that a
change to the design is a change to one file and not a hunt through a drawing
tool.  Run:

    python3 scripts/gen_diagrams.py           # -> docs/figures/*.svg
"""
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from svgkit import Canvas, P, MONO, SANS  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent.parent / "docs" / "figures"

FIGS = {}


def fig(name):
    def deco(fn):
        FIGS[name] = fn
        return fn
    return deco


# ===========================================================================
# 1. Top-level SoC block diagram
# ===========================================================================
@fig("fig01-soc-toplevel")
def _():
    c = Canvas(1180, 792)
    c.text(590, 26, "MEDS-S1 platform — S1-AI configuration", 15, weight="bold")
    c.text(590, 44, "green = memory · blue = core · purple = fabric · orange = accelerator",
           9.5, color=P["muted"], italic=True)

    # --- debug chain -------------------------------------------------------
    c.box(28, 62, 120, 40, "JTAG", "TCK/TMS/TDI/TDO", "verif", 11)
    c.box(168, 62, 140, 40, "DTM", "debug transport", "verif", 11)
    c.box(328, 62, 170, 40, "Debug Module", "halt · step · sysbus", "verif", 11)
    c.arrow(148, 82, 168, 82)
    c.arrow(308, 82, 328, 82)

    # --- core --------------------------------------------------------------
    c.group(28, 128, 640, 300, "S1-Core   (RV64IMAC_Zicsr_Zifencei_Zicbom_Zicboz)", "core")
    st = ["IF", "ID", "EX", "MEM", "WB"]
    for i, s in enumerate(st):
        c.box(46 + i * 74, 156, 62, 40, s, style="core", size=12)
        if i:
            c.arrow(40 + i * 74, 176, 46 + i * 74, 176, size="s")
    c.box(422, 156, 216, 40, "COMPLETION BUFFER", "8 entries · in-order retire", "core", 11)
    c.arrow(410, 176, 422, 176, size="s")

    c.box(46, 216, 180, 46, "CSR file + traps", "M/S/U · perf counters", "core", 11)
    c.box(238, 216, 180, 46, "PMP (16) + PMA", "parallel with D$ tag", "core", 11)
    c.box(430, 216, 208, 46, "MUL · DIV · MXIF port", "multi-cycle units", "core", 11)
    c.box(46, 282, 180, 46, "LSU + store buffer", "Zicbom engine", "core", 11)
    c.box(238, 282, 180, 46, "MMU / PTW", "Sv39 · 2 ports (P5)", "ghost", 11)
    c.box(430, 282, 208, 46, "RVFI + RVFI-V", "trace port → cosim", "verif", 11)

    c.box(46, 348, 180, 56, "I$", "8–16 KB · 2-way", "mem", 12)
    c.box(238, 348, 180, 56, "D$", "write-back · 64 B", "mem", 12)

    c.arrow(340, 102, 340, 128, size="s")          # DM -> core halt
    c.text(352, 120, "halt / resume", 8.5, "start", color=P["muted"])

    # --- MXIF coprocessor ---------------------------------------------------
    c.box(700, 208, 200, 78, "MEDS-V", ["vector coprocessor", "VLEN 128–512"], "accel", 13)
    c.arrow(638, 247, 700, 247, color="#b5711f", sw=1.7, both=True, size="s")
    c.text(669, 240, "MXIF", 8.6, color="#b5711f", weight="bold")
    c.text(800, 300, "issue · commit · norollback · result · idle", 8, color="#b5711f")

    # --- backbone -----------------------------------------------------------
    by = 470
    c.rect(28, by, 1120, 46, "#f1ecf8", "#6b4c9a", 1.6, 5)
    c.text(588, by + 20, "AXI4 BACKBONE CROSSBAR", 13, weight="bold", color="#3a2559")
    c.text(588, by + 36, "256-bit data · 40-bit address · 6-bit ID", 9, color="#6b4c9a")

    c.bus(136, 404, 136, by, "64", color="#6b4c9a")
    c.bus(328, 404, 328, by, "64", color="#6b4c9a")
    c.bus(800, 286, 800, by, "256", color="#b5711f")
    # debug system-bus master, routed clear of the core and the coprocessor
    c.path(f"M498,82 L1060,82 L1060,{by}", "#6b4c9a", 2.5, arrow=True)
    c.text(1052, 300, "DM sysbus", 8, "end", color="#6b4c9a")

    # --- slaves --------------------------------------------------------------
    sl = [("Boot ROM", "32 KB", "mem"), ("On-chip SRAM", "256 KB", "mem"),
          ("DDR3 via MIG", "1 GB", "mem"), ("Socket 0", "accel + DMA", "accel"),
          ("Socket 1", "accel + DMA", "accel"), ("AXI4-Lite bridge", "→ periph", "fabric")]
    for i, (n, s, st_) in enumerate(sl):
        x = 34 + i * 186
        c.box(x, 566, 168, 50, n, s, st_, 11)
        c.bus(x + 84, by + 46, x + 84, 566, color="#6b4c9a", sw=2.2)

    # --- accelerators sit directly under their sockets -------------------------
    c.box(578, 636, 168, 44, "DL accelerator", "thesis IP", "accel", 11)
    c.box(764, 636, 168, 44, "MEDS-X-*", "any accelerator", "accel", 11)
    c.arrow(662, 616, 662, 636, color="#b5711f", size="s")
    c.arrow(848, 616, 848, 636, color="#b5711f", size="s")

    # --- peripheral subtree ----------------------------------------------------
    c.line(1048, 616, 1048, 706, "#6b4c9a", 2.2)
    c.line(90, 706, 1048, 706, "#6b4c9a", 2.2)
    c.text(300, 699, "AXI4-Lite peripheral subtree — 32-bit", 9.5, color="#6b4c9a")
    per = ["CLINT", "PLIC", "UART", "SPI", "GPIO", "Timer", "Accel MMIO"]
    for i, p_ in enumerate(per):
        x = 34 + i * 160
        c.box(x, 734, 142, 40, p_, style="periph", size=11)
        c.line(x + 71, 706, x + 71, 734, "#6b4c9a", 1.4)

    return c


# ===========================================================================
# 2. Pipeline datapath
# ===========================================================================
@fig("fig02-pipeline")
def _():
    c = Canvas(1120, 600)
    c.text(560, 26, "S1-Core pipeline — five stages, decoupled completion", 15, weight="bold")

    stages = [("IF", ["PC gen · BTFN", "I$ access", "C-expansion"]),
              ("ID", ["decode", "regfile read", "hazard · CB alloc"]),
              ("EX", ["ALU", "branch resolve", "AGU"]),
              ("MEM", ["D$ access", "PMP + PMA", "store buffer"]),
              ("WB", ["regfile write", "RVFI out"])]
    for i, (n, rows) in enumerate(stages):
        x = 40 + i * 178
        c.box(x, 74, 150, 96, n, rows, "core", 14, 9)
        if i:
            c.arrow(x - 28, 122, x, 122, size="s")

    # multi-cycle units
    c.group(330, 216, 480, 112, "MULTI-CYCLE UNITS  (variable latency)", "core")
    c.box(352, 246, 130, 62, "MUL", "3-cycle pipelined", "core", 12)
    c.box(496, 246, 130, 62, "DIV", "iterative", "core", 12)
    c.box(640, 246, 150, 62, "MXIF port", "→ coprocessor", "accel", 12)
    c.arrow(470, 170, 420, 216, size="s")
    c.text(408, 200, "dispatch from EX", 8.5, "end", color=P["muted"])

    # completion buffer
    c.box(230, 380, 660, 66, "COMPLETION BUFFER — 8 entries",
          "in-order allocate · out-of-order complete · in-order retire", "core", 14, 10)
    for x in (417, 561, 715):
        c.arrow(x, 328, x, 380, size="s")
    c.arrow(890, 122, 940, 122, size="s")
    c.path("M940,122 L980,122 L980,413 L890,413", P["line"], 1.3, arrow=True)
    c.text(996, 268, "WB result", 8.5, "start", color=P["muted"])

    # retire outputs
    outs = ["architectural regfile commit", "CSR commit", "store buffer commit",
            "RVFI valid", "trap taken here", "MXIF offload happens here"]
    for i, o in enumerate(outs):
        yy = 476 + i * 21
        col = P["accent"] if i >= 4 else P["line"]
        c.arrow(560, 446, 560, 468, color=P["line"], size="s") if i == 0 else None
        c.line(560, 468, 596, 468, P["line"], 1.2) if i == 0 else None
        c.arrow(600, yy, 636, yy, color=col, size="s")
        c.text(644, yy + 3, o, 9.5, "start", color=col,
               weight="bold" if i == 5 else "normal")
    c.line(600, 468, 600, 476 + 5 * 21, P["line"], 1.2)
    c.text(556, 462, "retire pointer", 9, "end", color=P["accent"], weight="bold")

    # frontend interface note
    c.rect(40, 528, 500, 56, "#fdeceb", "#b03a2e", 1.2, 4, dash="4 3")
    c.text(56, 548, "fetch_req / fetch_rsp interface", 10.5, "start", MONO,
           weight="bold", color="#6d211a")
    c.text(56, 566, "the branch predictor and I$ sit behind this — swappable without touching decode",
           8.8, "start", color="#6d211a")
    c.arrow(115, 528, 115, 172, color="#b03a2e", sw=1.1, dash="4 3", size="s")

    return c


# ===========================================================================
# 3. PIN-OUT: S1-Core top level
# ===========================================================================
@fig("fig03-pinout-core")
def _():
    c = Canvas(1080, 622)
    c.text(540, 26, "Pin-out — s1_core top level", 15, weight="bold")
    c.text(540, 44, "blue = input · orange = output · purple = bidirectional bundle",
           9, color=P["muted"], italic=True)

    c.pinout(
        392, 74, 300, 436, "s1_core",
        sub=["#(XLEN=64, PMP_N=16,", "  MXIF_EN=1, DW=64)"],
        left=[
            ("clock / reset", [("clk_i", "in"), ("rst_ni", "in"),
                               ("boot_addr_i[63:0]", "in"), ("hart_id_i[63:0]", "in")]),
            ("interrupts", [("irq_software_i", "in"), ("irq_timer_i", "in"),
                            ("irq_external_i", "in")]),
            ("debug", [("debug_req_i", "in"), ("debug_halted_o", "out"),
                       ("debug_running_o", "out")]),
            ("mxif — see fig. 4", [("x_issue_*", "io"), ("x_commit_*", "out"),
                                   ("x_norollback_*", "in"), ("x_result_*", "in"),
                                   ("x_idle", "in")]),
        ],
        right=[
            ("instruction memory", [("instr_req_o", "out"), ("instr_gnt_i", "in"),
                                    ("instr_addr_o[63:0]", "out"),
                                    ("instr_rdata_i[63:0]", "in"),
                                    ("instr_rvalid_i", "in"), ("instr_err_i", "in")]),
            ("data memory", [("data_req_o", "out"), ("data_gnt_i", "in"),
                             ("data_we_o", "out"), ("data_be_o[7:0]", "out"),
                             ("data_addr_o[63:0]", "out"), ("data_wdata_o[63:0]", "out"),
                             ("data_rdata_i[63:0]", "in"), ("data_rvalid_i", "in"),
                             ("data_err_i", "in")]),
            ("trace", [("rvfi_*", "out")]),
        ],
        style="core", stub=42, pitch=18,
    )

    c.rect(40, 500, 300, 100, "#eaf0f9", "#3b5b8c", 1.2, 4)
    c.text(54, 520, "THE MEMORY PORTS ARE NOT AXI", 9.4, "start", weight="bold",
           color="#16314f")
    c.lines(54, 538, [
        "instr_* and data_* speak MEM-REQ",
        "(INTERFACES §2).  The pipeline never speaks",
        "AXI directly — that would couple pipeline",
        "timing to bus latency permanently, and every",
        "future bus change would touch the core.",
    ], 8.3, "start", color="#16314f", lh=1.4)

    return c


# ===========================================================================
# 4. PIN-OUT + structure: MXIF
# ===========================================================================
@fig("fig04-pinout-mxif")
def _():
    c = Canvas(1180, 636)
    c.text(590, 26, "Pin-out — MXIF-1.0 coprocessor interface", 15, weight="bold")
    c.text(590, 44, "a profile of OpenHW CV-X-IF · signals marked * are MEDS extensions",
           9, color=P["muted"], italic=True)

    c.pinout(
        470, 86, 250, 462, "MXIF coprocessor",
        sub=["e.g. meds_v_top"],
        left=[
            ("issue channel", [("x_issue_valid", "in"), ("x_issue_ready", "out"),
                               ("x_issue_instr[31:0]", "in"), ("x_issue_mode[1:0]", "in"),
                               ("x_issue_id[3:0]", "in"), ("x_issue_pc[63:0] *", "in"),
                               ("x_issue_rs[2:0][63:0]", "in"),
                               ("x_issue_rs_valid[2:0]", "in"),
                               ("x_issue_accept", "out"), ("x_issue_writeback", "out"),
                               ("x_issue_dualwrite", "out"),
                               ("x_issue_loadstore", "out")]),
            ("commit channel", [("x_commit_valid", "in"), ("x_commit_id[3:0]", "in"),
                                ("x_commit_kill", "in")]),
        ],
        right=[
            ("retire permission *", [("x_norollback", "out"),
                                     ("x_norollback_id[3:0]", "out")]),
            ("result channel", [("x_result_valid", "out"), ("x_result_ready", "in"),
                                ("x_result_id[3:0]", "out"), ("x_result_rd[4:0]", "out"),
                                ("x_result_data[63:0]", "out"), ("x_result_we", "out"),
                                ("x_result_exc", "out"),
                                ("x_result_exccode[5:0]", "out")]),
            ("status *", [("x_idle", "out")]),
            ("external csr", [("csr_addr[11:0]", "in"), ("csr_wdata[63:0]", "in"),
                              ("csr_rdata[63:0]", "out")]),
            ("own memory port", [("mem_req_*", "out"), ("mem_rsp_*", "in")]),
        ],
        style="accel", stub=40, pitch=17.5,
    )

    # normative callouts, clear of the pin-label columns
    c.rect(28, 578, 556, 44, "#fdeceb", "#b03a2e", 1.2, 4)
    c.text(42, 597, "R1.1  NON-SPECULATIVE ISSUE", 9.4, "start", weight="bold",
           color="#6d211a")
    c.text(42, 613, "x_issue_valid asserts only at the retire pointer, so no kill is ever "
                    "needed.  x_commit_kill is tied 0; the wire exists for MXIF-1.1.",
           8.3, "start", color="#6d211a")

    c.rect(604, 578, 548, 44, "#fdeceb", "#b03a2e", 1.2, 4)
    c.text(618, 597, "R1.9  TWO-PHASE COMPLETION", 9.4, "start", weight="bold",
           color="#6d211a")
    c.text(618, 613, "x_norollback = \"I can no longer fault, retire me\".  Only it gates "
                     "retire, so a 300-cycle op retires in two cycles and keeps running.",
           8.3, "start", color="#6d211a")

    c.rect(28, 96, 190, 122, "#eaf0f9", "#3b5b8c", 1.2, 4)
    c.text(40, 116, "WHY A PROFILE?", 9.4, "start", weight="bold", color="#16314f")
    c.lines(40, 134, [
        "MEDS-V's published",
        "interface has no commit/",
        "kill channel.  Profiling",
        "CV-X-IF keeps standard",
        "names and the upgrade path",
        "while making the existing",
        "MEDS-V design legal.",
    ], 8.2, "start", color="#16314f", lh=1.38)

    return c


# ===========================================================================
# 5. TIMING: MXIF two-phase completion
# ===========================================================================
@fig("fig05-timing-mxif")
def _():
    c = Canvas(1040, 712)
    c.text(520, 26, "MXIF two-phase completion — why decoupling survives in-order retire",
           15, weight="bold")

    def pulse(n, *hi):
        return "".join("-" if i in hi else "_" for i in range(n))

    N = 20
    c.timing(
        40, 100,
        [("clk", "_-" * (N // 2)),
         ("x_issue_valid", pulse(N, 2)),
         ("x_issue_ready", pulse(N, 2)),
         ("x_issue_accept", pulse(N, 2)),
         ("x_commit_valid", pulse(N, 3)),
         ("x_norollback", pulse(N, 5)),
         ("coproc busy", "__" + "X" * 16 + "__"),
         ("retire ptr adv", pulse(N, 6)),
         ("scalar pipeline", "XX____" + "X" * 14),
         ("x_idle", "--" + "_" * 16 + "--")],
        cycles=N, cw=40, rh=26, label_w=132,
        title="vle32.v v1,(a0)   —   no scalar writeback, so retire needs only x_norollback",
        marks=[(5, "address range checked\nagainst PMA / PMP", "#3b5b8c", 0),
               (6, "RETIRES HERE", "#b03a2e", 1)],
    )
    c.text(40, 430, "The vector load is architecturally retired at cycle 6 and is still "
                    "fetching data until cycle 18.", 9.4, "start", color="#b03a2e",
           weight="bold")
    c.text(40, 447, "The scalar pipeline runs unrelated work throughout — this is the entire "
                    "argument for decoupling, and it is only legal because of R1.9.",
           9, "start", color=P["muted"])

    M = 12
    c.timing(
        40, 528,
        [("x_issue_valid", pulse(M, 2)),
         ("x_norollback", pulse(M, 2)),
         ("x_result_valid", pulse(M, 6)),
         ("retire ptr adv", pulse(M, 7)),
         ("scalar pipeline", "__" + "X" * 5 + "_____")],
        cycles=M, cw=40, rh=26, label_w=132,
        title="vsetvli a0, a1, e32, m1   —   writes a scalar register, so retire needs both",
        marks=[(2, "STALLED", "#b5711f", 0), (7, "resumes", "#b5711f", 0)],
    )
    c.text(660, 552, "rd_we = 1, so §9.2 requires", 8.8, "start", color="#b5711f",
           weight="bold")
    c.text(660, 567, "norollback AND result.", 8.8, "start", color="#b5711f", weight="bold")
    c.text(660, 586, "Inherent; happens once per", 8.8, "start", color=P["muted"])
    c.text(660, 601, "strip-mine pass.  Measure it;", 8.8, "start", color=P["muted"])
    c.text(660, 616, "do not optimise it away in v1.", 8.8, "start", color=P["muted"])

    return c


# ===========================================================================
# 6. PIN-OUT: accelerator socket
# ===========================================================================
@fig("fig06-pinout-socket")
def _():
    c = Canvas(1160, 616)
    c.text(580, 26, "Pin-out — meds_s1_accel_socket", 15, weight="bold")
    c.text(580, 44, "the frozen attachment point for every loosely-coupled accelerator",
           9, color=P["muted"], italic=True)

    c.pinout(
        360, 80, 300, 400, "meds_s1_accel_socket",
        sub=["#(AXI_DW=256, LITE_DW=32,", "  ASYNC=0|1)"],
        left=[
            ("fabric side", [("clk_i", "in"), ("rst_ni", "in"),
                             ("cfg_axil (slave)", "io"), ("dma_axi (master)", "io")]),
            ("interrupt", [("irq_o", "out")]),
        ],
        right=[
            ("accel clock", [("accel_clk_i", "in"), ("accel_rst_ni", "in")]),
            ("accel side", [("acc_cfg (slave)", "io"), ("acc_dma (master)", "io"),
                            ("acc_irq_i", "in")]),
        ],
        style="accel", stub=44, pitch=22,
    )

    # mandatory register map, clear of the right-hand pin-label column
    c.text(820, 96, "Mandatory register map", 11, "start", weight="bold")
    regs = [("0x00", "ID", "RO"), ("0x04", "VERSION", "RO"), ("0x08", "CTRL", "RW"),
            ("0x0C", "STATUS", "RO"), ("0x10", "IRQ_STATUS", "W1C"),
            ("0x14", "CAPABILITY", "RO"), ("0x18", "PERF_CYCLES", "RO"),
            ("0x1C", "PERF_STALLS", "RO"), ("0x20+", "accel-specific", "\u2014")]
    for i, (off, nm, acc) in enumerate(regs):
        yy = 116 + i * 25
        c.box(820, yy, 300, 22, None, style="accel" if i in (6, 7) else "periph", rx=2)
        c.text(832, yy + 16, off, 8.8, "start", MONO)
        c.text(896, yy + 16, nm, 8.8, "start", MONO, weight="bold")
        c.text(1110, yy + 16, acc, 8.4, "end", color=P["muted"])
    c.text(820, 366, "PERF_CYCLES / PERF_STALLS at fixed offsets are what let SPEC \u00a734",
           8.3, "start", color=P["muted"], italic=True)
    c.text(820, 379, "compare accelerators written years apart.", 8.3, "start",
           color=P["muted"], italic=True)

    # CDC note, full width along the bottom
    c.rect(40, 512, 1080, 76, "#eaf0f9", "#3b5b8c", 1.2, 4)
    c.text(56, 534, "CDC LIVES IN THE SOCKET, NOT IN THE ACCELERATOR", 10, "start",
           weight="bold", color="#16314f")
    c.text(56, 554, "With ASYNC=1 the socket instantiates AXI clock-domain-crossing bridges. "
                    "An accelerator author sets a parameter, supplies a clock,", 8.6, "start",
           color="#16314f")
    c.text(56, 570, "and writes purely synchronous logic. Per NFR-6 they may not write "
                    "synchroniser logic at all.", 8.6, "start", color="#16314f")

    return c


# ===========================================================================
# 7. Bus fabric topology
# ===========================================================================
@fig("fig07-fabric")
def _():
    c = Canvas(1120, 600)
    c.text(560, 26, "AXI4 fabric topology and bandwidth budget", 15, weight="bold")

    masters = [("I$", "64b", "core"), ("D$", "64b", "core"),
               ("MXIF coproc", "256b", "accel"), ("Socket 0 DMA", "256b", "accel"),
               ("Socket 1 DMA", "256b", "accel"), ("Debug DM", "64b", "verif")]
    for i, (n, w, st) in enumerate(masters):
        y = 76 + i * 62
        c.box(40, y, 168, 46, n, w, st, 11.5)
        if w == "64b":
            c.box(230, y + 6, 96, 34, "upsize", None, "fabric", 9.5)
            c.arrow(208, y + 23, 230, y + 23, size="s")
            c.arrow(326, y + 23, 396, y + 23, size="s")
        else:
            c.bus(208, y + 23, 396, y + 23, "256", color="#6b4c9a", sw=3)

    c.rect(400, 76, 200, 402, "#f1ecf8", "#6b4c9a", 1.6, 5)
    c.text(500, 250, "AXI4", 17, weight="bold", color="#3a2559")
    c.text(500, 274, "CROSSBAR", 17, weight="bold", color="#3a2559")
    c.text(500, 302, "256-bit data", 9.5, color="#6b4c9a")
    c.text(500, 318, "40-bit address", 9.5, color="#6b4c9a")
    c.text(500, 334, "6-bit ID", 9.5, color="#6b4c9a")
    c.text(500, 360, "decode + PMA from", 8.6, color="#6b4c9a", italic=True)
    c.text(500, 374, "soc.yaml", 8.6, color="#6b4c9a", italic=True)

    slaves = [("Boot ROM", "32 KB", "mem"), ("SRAM", "256 KB", "mem"),
              ("DDR3 / MIG", "1 GB", "mem"), ("Socket 0 MMIO", "64 KB", "accel"),
              ("Socket 1 MMIO", "64 KB", "accel"), ("AXI4-Lite bridge", "32b", "fabric")]
    for i, (n, s, st) in enumerate(slaves):
        y = 76 + i * 62
        c.box(700, y, 176, 46, n, s, st, 11.5)
        c.bus(600, y + 23, 700, y + 23, color="#6b4c9a", sw=3)

    # budget panel
    c.rect(910, 76, 190, 300, "#ffffff", "#b03a2e", 1.3, 4)
    c.text(1005, 98, "BANDWIDTH BUDGET", 9.6, weight="bold", color="#6d211a")
    c.text(1005, 112, "at 100 MHz, 256-bit", 8.2, color=P["muted"], italic=True)
    rows = [("I$ + D$", "0.3 GB/s"), ("MEDS-V 128b/1L", "1.6 GB/s"),
            ("MEDS-V 512b/4L", "6.4 GB/s"), ("Socket 0", "≤3.2 GB/s"),
            ("Socket 1", "≤3.2 GB/s"), ("per-port limit", "3.2 GB/s")]
    for i, (a, b) in enumerate(rows):
        yy = 138 + i * 22
        col = "#b03a2e" if i == 2 else P["ink"]
        c.text(922, yy, a, 8.6, "start", color=col,
               weight="bold" if i in (2, 5) else "normal")
        c.text(1092, yy, b, 8.6, "end", MONO, color=col,
               weight="bold" if i in (2, 5) else "normal")
    c.line(920, 268, 1090, 268, P["faint"], 0.8)
    c.lines(922, 286, ["MEDS-V at VLEN=512", "exceeds one master", "port. Known; routed",
                       "direct to the DDR", "path in Phase 5."], 8.0, "start",
            color="#b03a2e", lh=1.35)

    # peripheral subtree
    c.line(788, 478, 788, 512, "#6b4c9a", 2)
    c.line(90, 512, 788, 512, "#6b4c9a", 2)
    per = ["CLINT", "PLIC", "UART", "SPI", "GPIO", "Timer"]
    for i, p_ in enumerate(per):
        x = 40 + i * 128
        c.box(x, 540, 112, 38, p_, style="periph", size=10.5)
        c.line(x + 56, 512, x + 56, 540, "#6b4c9a", 1.3)
    c.text(400, 506, "AXI4-Lite subtree — 32-bit, no bursts", 9, "start", color="#6b4c9a")

    return c


# ===========================================================================
# 8. Coupling comparison
# ===========================================================================
@fig("fig08-coupling")
def _():
    c = Canvas(1080, 520)
    c.text(540, 26, "The two attachment mechanisms", 15, weight="bold")
    c.text(540, 44, "tightly-coupled units are given instructions; loosely-coupled units are given work",
           9.5, color=P["muted"], italic=True)

    # left: tight
    c.group(36, 76, 480, 380, "TIGHT — MXIF   (SPEC §19)", "core")
    c.box(70, 116, 180, 54, "S1-Core", "pipeline + CB", "core", 12)
    c.box(300, 116, 180, 54, "coprocessor", "MEDS-V, crypto", "accel", 12)
    c.arrow(250, 132, 300, 132, "instruction", color="#b5711f", label_size=8.4)
    c.arrow(300, 156, 250, 156, "result", color="#b5711f", label_size=8.4)
    c.box(300, 208, 180, 44, "own memory port", None, "mem", 10.5)
    c.arrow(390, 170, 390, 208, size="s")
    facts = ["invoked by an instruction", "operands from scalar registers",
             "~2–5 cycle invocation overhead", "good for 1–100 cycles of work",
             "needs the 7-item toolchain checklist"]
    for i, f in enumerate(facts):
        c.text(70, 288 + i * 20, "•  " + f, 9.2, "start", color="#16314f")
    c.rect(62, 396, 424, 42, "#eaf0f9", "#3b5b8c", 1.0, 3)
    c.text(274, 414, "MEDS-V · crypto rounds · activations · posit ALU", 9.2,
           weight="bold", color="#16314f")
    c.text(274, 430, "examples", 8, color=P["muted"], italic=True)

    # right: loose
    c.group(564, 76, 480, 380, "LOOSE — accelerator socket   (SPEC §20)", "accel")
    c.box(598, 116, 180, 54, "S1-Core", "MMIO writes", "core", 12)
    c.box(828, 116, 180, 54, "accelerator", "conv, systolic", "accel", 12)
    c.arrow(778, 132, 828, 132, "descriptor + go", color="#b5711f", label_size=8.4)
    c.arrow(828, 156, 778, 156, "irq", color="#b5711f", label_size=8.4)
    c.box(828, 208, 180, 44, "DMA master", None, "mem", 10.5)
    c.arrow(918, 170, 918, 208, size="s")
    facts2 = ["invoked by an MMIO write", "operands from memory via DMA",
              "~50–200 cycle invocation overhead", "good for 1000+ cycles of work",
              "no toolchain work — it is just a driver"]
    for i, f in enumerate(facts2):
        c.text(598, 288 + i * 20, "•  " + f, 9.2, "start", color="#6d4310")
    c.rect(590, 396, 424, 42, "#fdf2e2", "#b5711f", 1.0, 3)
    c.text(802, 414, "conv engines · systolic arrays · FFT · DL accelerators", 9.2,
           weight="bold", color="#6d4310")
    c.text(802, 430, "recommended for most DL/ML theses", 8, color=P["muted"], italic=True)

    c.text(540, 486, "The common mistake: attaching a convolution engine over MXIF because "
                     "instructions feel elegant.", 9.4, weight="bold", color="#b03a2e")
    c.text(540, 502, "A convolution runs for thousands of cycles and streams megabytes. "
                     "It does not want to be an instruction.", 9, color=P["muted"])
    return c


# ===========================================================================
# 9. Accelerator invocation + double buffering
# ===========================================================================
@fig("fig09-dataflow")
def _():
    c = Canvas(1080, 560)
    c.text(540, 26, "Accelerator data movement", 15, weight="bold")

    # -- double buffering timeline
    c.text(40, 70, "Double buffering — the baseline every accelerator should implement",
           11, "start", weight="bold")
    def tl(y, label, blocks, color):
        c.text(40, y + 15, label, 9, "start", MONO)
        for (s, w, t) in blocks:
            c.rect(160 + s * 58, y, w * 58 - 4, 22, color, "#666", 0.9, 2)
            c.text(160 + s * 58 + (w * 58 - 4) / 2, y + 15, t, 8.2, family=MONO)

    c.text(40, 96, "without:", 9, "start", weight="bold", color=P["muted"])
    tl(104, "  DMA in ", [(0, 1, "L0"), (3, 1, "L1"), (6, 1, "L2")], "#dbe6f5")
    tl(130, "  compute", [(1, 1, "C0"), (4, 1, "C1"), (7, 1, "C2")], "#f5e6cf")
    tl(156, "  DMA out", [(2, 1, "S0"), (5, 1, "S1"), (8, 1, "S2")], "#d9ecdb")
    c.line(160, 184, 160 + 9 * 58, 184, P["accent"], 1.4)
    c.text(160 + 4.5 * 58, 198, "3N cycles for N tiles", 9, color=P["accent"], weight="bold")

    c.text(40, 232, "with:", 9, "start", weight="bold", color=P["muted"])
    tl(240, "  DMA in ", [(0, 1, "L0"), (1, 1, "L1"), (2, 1, "L2"), (3, 1, "L3")], "#dbe6f5")
    tl(266, "  compute", [(1, 1, "C0"), (2, 1, "C1"), (3, 1, "C2")], "#f5e6cf")
    tl(292, "  DMA out", [(2, 1, "S0"), (3, 1, "S1")], "#d9ecdb")
    c.line(160, 320, 160 + 4 * 58, 320, "#3f7a45", 1.4)
    c.text(160 + 2 * 58, 334, "~N cycles", 9, color="#3f7a45", weight="bold")
    c.text(160 + 5.4 * 58, 320, "2× buffer, almost always worth it.  If PERF_STALLS / PERF_CYCLES > 0.2,",
           8.6, "start", color=P["muted"])
    c.text(160 + 5.4 * 58, 334, "double buffering is the first thing to check.", 8.6, "start",
           color=P["muted"])

    # -- invocation flow
    c.text(40, 386, "Invocation flow", 11, "start", weight="bold")
    steps = [("write tensor\n+ descriptor", "sw"), ("cbo.clean\ninput buffer", "verif"),
             ("MMIO descriptor\naddress", "sw"), ("MMIO\nCTRL.start=1", "accel"),
             ("DMA + compute\n(tiled)", "accel"), ("irq → PLIC", "periph"),
             ("cbo.inval\noutput buffer", "verif"), ("read result", "sw")]
    for i, (t, st) in enumerate(steps):
        x = 40 + i * 129
        rows = t.split("\n")
        c.box(x, 410, 112, 52, rows, style=st, size=8.8)
        if i:
            c.arrow(x - 15, 436, x, 436, size="s")
    c.text(40, 494, "Steps 2 and 7 are the ones students forget; the symptom is stale data that "
                    "looks like an accelerator bug.", 9, "start", color="#b03a2e")
    c.text(40, 510, "The driver template ships with them already written.", 9, "start",
           color="#b03a2e", weight="bold")
    c.text(40, 534, "PMA order:strong (P2) guarantees the descriptor lands before CTRL.start — "
                    "no fence required.", 8.8, "start", color=P["muted"], italic=True)
    return c


# ===========================================================================
# 10. Memory map + PMA
# ===========================================================================
@fig("fig10-memorymap")
def _():
    c = Canvas(1000, 700)
    c.text(500, 26, "Physical memory map and attributes", 15, weight="bold")
    c.text(500, 44, "generated from soc.yaml into the decoder, linker script, device tree and C headers",
           9, color=P["muted"], italic=True)

    regions = [
        ("0x1_0000_0000", "DRAM uncached alias", "1 GB", "no", "strong", "accel"),
        ("0x8000_0000", "DRAM (cached)", "1 GB", "yes", "rvwmo", "mem"),
        ("0x4000_0000", "On-chip SRAM", "256 KB", "yes", "rvwmo", "mem"),
        ("0x2001_0000", "Socket 1 MMIO", "64 KB", "no", "strong", "accel"),
        ("0x2000_0000", "Socket 0 MMIO", "64 KB", "no", "strong", "accel"),
        ("0x1000_0000", "Peripherals", "256 MB", "no", "strong", "periph"),
        ("0x0C00_0000", "PLIC", "4 MB", "no", "strong", "periph"),
        ("0x0200_0000", "CLINT", "64 KB", "no", "strong", "periph"),
        ("0x0000_1000", "Boot ROM", "32 KB", "I-only", "rvwmo", "mem"),
        ("0x0000_0000", "Debug ROM", "4 KB", "no", "rvwmo", "verif"),
    ]
    c.text(150, 86, "base", 9, "end", weight="bold", color=P["muted"])
    c.text(300, 86, "region", 9, weight="bold", color=P["muted"])
    c.text(590, 86, "size", 9, weight="bold", color=P["muted"])
    c.text(700, 86, "cacheable", 9, weight="bold", color=P["muted"])
    c.text(820, 86, "ordering", 9, weight="bold", color=P["muted"])

    for i, (base, name, size, cach, order, st) in enumerate(regions):
        y = 100 + i * 46
        c.text(150, y + 26, base, 9.4, "end", MONO)
        c.box(170, y, 260, 38, name, style=st, size=10.5)
        c.text(590, y + 26, size, 9.4, MONO)
        c.text(700, y + 26, cach, 9.4, MONO,
               color="#b03a2e" if cach == "no" else "#3f7a45")
        c.text(820, y + 26, order, 9.4, MONO,
               color="#b03a2e" if order == "strong" else P["ink"])

    # highlight the alias
    c.rect(166, 96, 700, 46, "none", "#b03a2e", 1.6, 4, dash="5 3")
    c.arrow(880, 119, 940, 119, color="#b03a2e", size="s")
    c.rect(600, 566, 380, 96, "#fdeceb", "#b03a2e", 1.2, 4)
    c.text(614, 586, "THE UNCACHED ALIAS", 9.6, "start", weight="bold", color="#6d211a")
    c.lines(614, 604, [
        "The same physical DRAM, mapped twice.  Costs one",
        "address-decode bit and gives every accelerator author",
        "a correct shared-buffer story on day one, before Zicbom",
        "is implemented or trusted.  Keep it afterwards — it is the",
        "fastest way to bisect a suspected coherence bug.",
    ], 8.3, "start", color="#6d211a", lh=1.4)

    c.rect(40, 566, 530, 96, "#ffffff", "#6f6f6f", 1.1, 4)
    c.text(54, 586, "PMA ATTRIBUTES CARRIED PER REGION", 9.6, "start", weight="bold")
    c.lines(54, 604, [
        "cacheable · idempotent · ordering · atomicity · alignment · widths",
        "",
        "P1  a non-idempotent region is never speculated, prefetched or replayed",
        "P2  order:strong regions are accessed in program order without a fence",
        "P3  an alignment or width violation faults, never truncates silently",
    ], 8.4, "start", color=P["ink"], lh=1.45)
    return c


# ===========================================================================
# 11. Verification architecture
# ===========================================================================
@fig("fig11-verification")
def _():
    c = Canvas(1020, 560)
    c.text(510, 26, "Verification architecture — five layers, all in CI", 15, weight="bold")

    layers = [
        ("LAYER 4", "Constrained random + functional coverage",
         "random instruction generator · SV coverage model", "nightly", "verif"),
        ("LAYER 3", "Architectural compliance",
         "RISCOF + riscv-arch-test vs Sail", "every merge", "verif"),
        ("LAYER 2", "Trace co-simulation   ← the backbone",
         "every retired instruction vs Spike, over RVFI", "every merge", "accel"),
        ("LAYER 1", "Unit tests",
         "per-module SystemVerilog testbenches", "every merge", "core"),
        ("LAYER 0", "Lint + elaboration",
         "Verible · all four configs elaborate", "every push", "periph"),
    ]
    for i, (tag, title, sub, when, st) in enumerate(layers):
        y = 70 + i * 76
        c.box(40, y, 700, 62, None, style=st)
        c.text(60, y + 26, tag, 10, "start", weight="bold", color=P["muted"])
        c.text(60, y + 44, title, 12, "start", weight="bold")
        c.text(400, y + 44, sub, 9, "start", color=P["muted"])
        c.box(756, y + 12, 120, 38, when, style="plain", size=9.5)

    c.rect(40, 456, 836, 62, "#fdeceb", "#b03a2e", 1.3, 4, dash="5 3")
    c.text(60, 478, "ORTHOGONAL — FORMAL", 10, "start", weight="bold", color="#6d211a")
    c.text(60, 496, "riscv-formal on the core · SVA for completion-buffer liveness · "
                    "MXIF and socket conformance properties", 9, "start", color="#6d211a")

    c.text(40, 540, "Layer 2 is built before the datapath exists.  A directed test costs 20 minutes "
                    "and covers one case; the harness covers every case, forever.",
           9, "start", color=P["muted"], italic=True)
    return c


# ===========================================================================
# 12. Software stack
# ===========================================================================
@fig("fig12-software")
def _():
    c = Canvas(900, 540)
    c.text(450, 26, "Software stack and the host toolchain", 15, weight="bold")

    layers = [
        ("APPLICATION", "ecg_cnn · eeg_seizure · kws · benchmarks", "sw"),
        ("LIBRARIES", "libs1_perf · accelerator drivers · tiny NN kernels", "sw"),
        ("HAL", "uart spi gpio timer plic clint · accel_open/start/wait · Zicbom", "sw"),
        ("C RUNTIME", "newlib · crt0.S · syscalls (UART | semihosting) · malloc", "core"),
        ("BOOT", "boot ROM → second stage (UART | SD | QSPI)", "core"),
        ("HARDWARE", "MEDS-S1", "mem"),
    ]
    for i, (n, s, st) in enumerate(layers):
        y = 66 + i * 62
        c.box(40, y, 520, 50, None, style=st)
        c.text(58, y + 22, n, 11, "start", weight="bold")
        c.text(58, y + 38, s, 8.8, "start", color=P["muted"])

    c.text(700, 86, "Host side", 12, weight="bold")
    hosts = ["openocd", "riscv64-…-gdb", "make run", "semihosting file I/O"]
    for i, h in enumerate(hosts):
        c.box(620, 106 + i * 52, 240, 40, h, style="verif", size=11)
        if i:
            c.arrow(740, 98 + i * 52, 740, 106 + i * 52, size="s")

    c.rect(620, 330, 240, 96, "#eaf3f6", "#3f7f95", 1.2, 4)
    c.text(740, 350, "THE make run CONTRACT", 9.4, weight="bold", color="#1c4855")
    c.lines(632, 368, [
        "make run BOARD=verilator PROG=x.elf",
        "make run BOARD=kc705     PROG=x.elf",
        "make debug BOARD=kc705   PROG=x.elf",
    ], 8.0, "start", MONO, color="#1c4855", lh=1.5)
    c.text(740, 416, "identical across boards", 8.2, color=P["muted"], italic=True)

    c.arrow(560, 400, 620, 400, size="s")
    c.text(590, 392, "JTAG", 8.4, color=P["muted"])

    c.text(40, 466, "Semihosting is the single feature that will make students believe the platform is real:",
           9.4, "start", weight="bold")
    c.text(40, 484, "it is how a 10 MB weight file reaches the FPGA without an SD card, and how printf "
                    "works before UART is trusted.", 9, "start", color=P["muted"])
    c.text(40, 508, "The Verilator target is not a lesser mode — it is where most development happens, "
                    "and it needs no board.", 9, "start", color=P["muted"], italic=True)
    return c


# ===========================================================================
# 13. Research measurement / attribution
# ===========================================================================
@fig("fig13-measurement")
def _():
    c = Canvas(1000, 520)
    c.text(500, 26, "Measurement infrastructure — why a speedup number is not enough",
           15, weight="bold")

    tiers = [("APPLICATION", "libs1_perf · PERF_BEGIN/END",
              "end-to-end latency, throughput", "sw"),
             ("SYSTEM", "mhpmcounter events",
              "where the cycles went: memory vs compute vs offload", "core"),
             ("ACCELERATOR", "socket PERF_CYCLES / PERF_STALLS",
              "accelerator utilisation and its own stalls", "accel")]
    for i, (n, m, a, st) in enumerate(tiers):
        y = 70 + i * 62
        c.box(40, y, 210, 48, n, style=st, size=11.5)
        c.box(266, y, 250, 48, m, style="plain", size=9.5)
        c.text(536, y + 29, a, 9.2, "start", color=P["muted"])

    c.text(40, 292, "Attribution — the table that turns a number into a finding", 11.5,
           "start", weight="bold")
    rows = [
        ("mxif_busy_cycles low, total high", "the accelerator is idle — software or offload path", "#6f6f6f"),
        ("mxif_issue_stall_cycles high", "the core cannot feed it — consider loose coupling", "#6f6f6f"),
        ("axi_read_latency / beats high", "memory-bound — look at tiling and double buffering", "#6f6f6f"),
        ("axi_arb_stall_cycles high", "bus contention — check the bandwidth budget", "#6f6f6f"),
        ("busy high, speedup still low", "genuinely compute-bound — the honest bottleneck", "#b03a2e"),
    ]
    for i, (sym, att, col) in enumerate(rows):
        y = 314 + i * 30
        c.rect(40, y, 400, 25, "#f7f7f5" if i % 2 == 0 else "#ffffff", "#dcdcd6", 0.8, 2)
        c.text(52, y + 17, sym, 9, "start", MONO, color=col)
        c.arrow(444, y + 12, 470, y + 12, color=col, size="s")
        c.text(478, y + 17, att, 9, "start", color=col,
               weight="bold" if i == 4 else "normal")

    c.rect(40, 470, 920, 34, "#fdeceb", "#b03a2e", 1.2, 4)
    c.text(500, 492, "Only the last row is about the accelerator's design.  A thesis that cannot "
                     "rule out the other four has not measured anything.",
           9.6, weight="bold", color="#6d211a")
    return c


# ===========================================================================
# 14. Cache block diagram
# ===========================================================================
@fig("fig14-dcache")
def _():
    c = Canvas(940, 492)
    c.text(470, 26, "D$ organisation — 8–16 KB, 2-way, 64 B lines, write-back", 15, weight="bold")

    c.text(60, 74, "addr[63:0]", 10, "start", MONO)
    for i, (lbl, w) in enumerate((("tag", 200), ("index", 130), ("offset", 100))):
        x = 160 + sum([0, 200, 130][:i])
        c.rect(x, 62, w, 26, "#f2f2ef", "#6f6f6f", 1.0, 2)
        c.text(x + w / 2, 79, lbl, 9.5, family=MONO)

    c.box(90, 130, 220, 76, "TAG ARRAY", ["meds_sram_wrapper", "way0 | way1"], "mem", 12, 9)
    c.box(360, 130, 220, 76, "DATA ARRAY", ["meds_sram_wrapper", "way0 | way1"], "mem", 12, 9)
    c.arrow(230, 88, 200, 130, size="s")
    c.arrow(290, 88, 470, 130, size="s")

    c.box(90, 236, 490, 48, "hit logic · way select · byte select", style="core", size=12)
    c.arrow(200, 206, 200, 236, "hit / way", size="s", label_size=8.4)
    c.arrow(470, 206, 470, 236, size="s")

    c.box(90, 320, 200, 62, "MISS FSM", ["evict → refill", "dirty writeback"], "core", 12, 9)
    c.box(330, 320, 250, 62, "Zicbom engine", ["cbo.clean / flush / inval"], "verif", 12, 9)
    c.arrow(190, 284, 190, 320, "miss", size="s", label_size=8.4)
    c.arrow(455, 284, 455, 320, size="s")

    c.box(90, 420, 200, 48, "AXI4 adapter", "upsizer 64 → 256", "fabric", 11)
    c.arrow(190, 382, 190, 420, size="s")

    c.box(660, 236, 240, 48, "PMA: cacheable?", style="verif", size=11)
    c.arrow(660, 260, 580, 260, "bypass", color="#b03a2e", size="s", label_size=8.4)
    c.rect(660, 300, 240, 110, "#fdeceb", "#b03a2e", 1.2, 4)
    c.text(780, 320, "BYPASS IS CORRECTNESS,", 9.2, weight="bold", color="#6d211a")
    c.text(780, 334, "NOT AN OPTIMISATION", 9.2, weight="bold", color="#6d211a")
    c.lines(672, 354, [
        "It is how the uncached DRAM",
        "alias works, and therefore how",
        "accelerator-shared buffers work",
        "before Zicbom is trustworthy.",
    ], 8.3, "start", color="#6d211a", lh=1.42)

    return c


# ===========================================================================
# 15. PTW two-port
# ===========================================================================
@fig("fig15-ptw")
def _():
    c = Canvas(900, 340)
    c.text(450, 26, "Page-table walker — the second port that must exist in v1.0",
           15, weight="bold")

    c.box(50, 90, 190, 52, "Core LSU", "port 0", "core", 12)
    c.box(50, 180, 190, 52, "Coprocessor TLB", "port 1 — TIED OFF in v1.0", "ghost", 12, 8.6)
    c.box(320, 120, 150, 72, "ARBITER", None, "fabric", 12)
    c.box(530, 120, 190, 72, "WALK FSM", "L2 → L1 → L0", "core", 12)
    c.box(770, 132, 100, 48, "MEM-REQ", None, "mem", 10.5)

    c.arrow(240, 116, 320, 140, size="s")
    c.arrow(240, 206, 320, 172, size="s", dash="4 3", color=P["muted"])
    c.arrow(470, 156, 530, 156, size="s")
    c.arrow(720, 156, 770, 156, size="s")

    c.rect(50, 254, 820, 58, "#fdeceb", "#b03a2e", 1.3, 4)
    c.text(64, 275, "R1.7 — WHY THIS FIGURE IS IN A v1.0 SPECIFICATION", 9.6, "start",
           weight="bold", color="#6d211a")
    c.text(64, 293, "A PTW with an unused second port costs an arbiter.  A PTW without one costs "
                    "an MMU rewrite during Linux bring-up, when MEDS-V's vector loads suddenly "
                    "need translated addresses.", 8.8, "start", color="#6d211a")
    return c


# ===========================================================================
# 16. Clock and reset domains
# ===========================================================================
@fig("fig16-clocks")
def _():
    c = Canvas(900, 400)
    c.text(450, 26, "Clock domains and reset policy", 15, weight="bold")

    c.box(40, 80, 140, 46, "ext_clk", style="periph", size=12)
    c.box(220, 80, 130, 46, "PLL / MMCM", style="fabric", size=11)
    c.arrow(180, 103, 220, 103, size="s")

    doms = [("clk_core", "100 MHz", "core"), ("clk_ddr", "MIG UI", "mem"),
            ("clk_accel0", "150 MHz", "accel"), ("clk_accel1", "optional", "accel")]
    for i, (n, f, st) in enumerate(doms):
        y = 70 + i * 62
        c.box(430, y, 170, 46, n, f, st, 11.5)
        c.arrow(350, 103, 430, y + 23, size="s")

    c.text(660, 90, "CDC — confined to named modules", 10.5, "start", weight="bold")
    cdcs = [("clk_core ↔ clk_ddr", "MIG adapter"),
            ("clk_core ↔ clk_accelN", "meds_s1_accel_socket"),
            ("clk_core ↔ jtag_tck", "riscv-dbg DTM")]
    for i, (a, b) in enumerate(cdcs):
        y = 112 + i * 40
        c.text(660, y, a, 9, "start", MONO)
        c.text(660, y + 14, "→ " + b, 8.6, "start", color=P["muted"], italic=True)

    c.rect(40, 300, 820, 72, "#eaf0f9", "#3b5b8c", 1.3, 4)
    c.text(54, 322, "RESET POLICY — STATED ONCE, ENFORCED EVERYWHERE", 9.8, "start",
           weight="bold", color="#16314f")
    c.text(54, 342, "Asynchronous assert, synchronous de-assert, active-low (rst_ni).  "
                    "One reset per clock domain.", 9, "start", color="#16314f")
    c.text(54, 358, "No local resets.  No reset generation inside leaf modules.  "
                    "No CDC outside a named synchroniser module.", 9, "start", color="#16314f")
    return c


# ===========================================================================
# 17. Generator flow
# ===========================================================================
@fig("fig17-generator")
def _():
    c = Canvas(980, 400)
    c.text(490, 26, "The SoC generator — one source of truth", 15, weight="bold")

    ins = [("soc.yaml", "memory map, PMAs,\ncore config"), ("board.yaml", "clocks, pins,\nmemory size"),
           ("accel.yaml × N", "IDs, register maps,\nbandwidth demand")]
    for i, (n, s) in enumerate(ins):
        y = 76 + i * 84
        c.box(40, y, 190, 62, n, s.split("\n"), "sw", 11.5, 8.6)
        c.arrow(230, y + 31, 330, 190, size="s")

    c.box(330, 150, 190, 84, "meds_s1_gen", "Python", "accent" if False else "fabric", 14)
    c.text(425, 246, "validates before it emits:", 8.6, color=P["muted"], italic=True)
    c.text(425, 259, "overlaps · IRQ collisions · budget", 8.4, color=P["muted"], italic=True)
    c.text(425, 272, "overruns · missing PMAs", 8.4, color=P["muted"], italic=True)

    outs = ["meds_s1_soc_top.sv", "pma_decode.sv", "link.ld", "meds_s1_soc.h",
            "meds_s1.dtsi", "memory_map.md", "tb_soc_top.sv", "openocd.cfg",
            "platform.lock"]
    for i, o in enumerate(outs):
        col, row = i % 2, i // 2
        x = 600 + col * 190
        y = 70 + row * 46
        c.box(x, y, 176, 34, o, style="mem", size=9.6)
        if i == 0:
            c.arrow(520, 190, 600, 190, size="s")

    c.rect(600, 296, 366, 74, "#fdeceb", "#b03a2e", 1.2, 4)
    c.text(614, 316, "GENERATED FILES ARE CHECKED IN", 9.4, "start", weight="bold",
           color="#6d211a")
    c.lines(614, 334, [
        "CI regenerates and fails on any difference.",
        "That single job stops the memory map from being",
        "right in the RTL and wrong in the device tree.",
    ], 8.4, "start", color="#6d211a", lh=1.4)
    return c


# ===========================================================================
# 18. Roadmap / phases
# ===========================================================================
@fig("fig18-roadmap")
def _():
    c = Canvas(1080, 412)
    c.text(530, 26, "Phase plan — each phase ends with something that runs", 15, weight="bold")

    phases = [
        ("0", "Foundations", "6 wk", "specs frozen, CI green\non an empty core", "periph"),
        ("1", "Core", "1 sem", "arch-tests green\nvs Sail", "core"),
        ("2", "SoC in sim", "1 sem", "Hello World from C\non Verilator", "core"),
        ("3", "Real hardware", "1 sem", "load any ELF over JTAG,\nno resynthesis", "verif"),
        ("4", "Extensibility", "1 sem", "two accelerators, zero\ncore RTL changes", "accel"),
        ("5", "Linux", "2 sem", "shell prompt\non the board", "mem"),
    ]
    for i, (n, name, dur, exit_, st) in enumerate(phases):
        x = 30 + i * 172
        c.box(x, 80, 154, 116, None, style=st)
        c.text(x + 77, 106, "PHASE " + n, 9.5, weight="bold", color=P["muted"])
        c.text(x + 77, 126, name, 12.5, weight="bold")
        c.text(x + 77, 143, dur, 9, color=P["muted"], italic=True)
        for j, r in enumerate(exit_.split("\n")):
            c.text(x + 77, 164 + j * 13, r, 8.3, color=P["ink"])
        if i:
            c.arrow(x - 16, 138, x, 138, size="s")

    c.rect(374, 232, 328, 44, "#fdeceb", "#b03a2e", 1.3, 4)
    c.text(538, 250, "PHASE 3 UNLOCKS THE WHOLE LAB", 9.8, weight="bold", color="#6d211a")
    c.text(538, 266, "until it lands, every software change costs a bitstream", 8.6,
           color="#6d211a")
    c.arrow(538, 232, 538, 200, color="#b03a2e", size="s")

    c.rect(718, 300, 328, 44, "#fdf2e2", "#b5711f", 1.3, 4)
    c.text(882, 318, "PHASE 4 PROVES IT IS A PLATFORM", 9.8, weight="bold", color="#6d4310")
    c.text(882, 334, "and not merely a processor", 8.6, color="#6d4310")
    c.arrow(882, 300, 882, 200, color="#b5711f", size="s", dash="4 3")

    c.text(30, 386, "Critical path: WP0 → WP3 → WP5 (completion buffer + MXIF) → WP15 (debug).  "
                    "WP5 is both on the critical path and the hardest package.",
           9, "start", color=P["muted"], italic=True)
    return c


# ===========================================================================
def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in FIGS.items():
        path = OUT / f"{name}.svg"
        fn().save(path)
        print(f"  {path.relative_to(OUT.parent.parent)}")
    print(f"\n{len(FIGS)} figures written to {OUT}")


if __name__ == "__main__":
    main()
