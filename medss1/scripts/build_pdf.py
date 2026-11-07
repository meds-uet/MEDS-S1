#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""Build the MEDS-S1 specification PDF.

Pipeline:  markdown -> (figures injected, mermaid rendered) -> pandoc -> HTML
           -> headless Chrome -> PDF

There is no LaTeX engine here, so Chrome's print-to-PDF does the rendering.  As
in the MEDS-V book build, that suits this document: it is full of box-drawing
diagrams that need a monospace font with good U+2500 coverage and absolutely no
line wrapping, which is easier to guarantee with CSS than with LaTeX verbatim.

Unlike the MEDS-V build, this one does *not* discard mermaid blocks -- it renders
them with mmdc and inlines the SVG.

Requires: pandoc, google-chrome/chromium, and (optionally) mmdc for mermaid.
Run scripts/gen_diagrams.py first, or pass --gen.

Usage:
    python3 scripts/build_pdf.py
    python3 scripts/build_pdf.py --gen --keep-html
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIGDIR = ROOT / "docs" / "figures"
SRC = ROOT / "specs" / "MEDS-S1-SPECIFICATION.md"
OUT = ROOT / "docs" / "MEDS-S1-Specification.pdf"

# ---------------------------------------------------------------------------
# Figure placement.  Each entry: anchor (a literal line in the markdown, matched
# exactly) -> (figure stem, caption, replace_next_code_block?)
#
# Where a generated figure supersedes an ASCII diagram, replace=True drops the
# following fenced block.  Where the ASCII block says something the figure does
# not, replace=False keeps both.
# ---------------------------------------------------------------------------
FIGURES = [
    ("### 4.1 Top-level block diagram — S1-AI configuration",
     "fig01-soc-toplevel", "MEDS-S1 top-level block diagram, S1-AI configuration.", True),
    ("### 4.2 Where the two attachment mechanisms sit",
     "fig08-coupling", "The two attachment mechanisms compared.", False),
    ("## 6. Pipeline organisation",
     "fig02-pipeline", "S1-Core pipeline organisation and the completion buffer.", True),
    ("## 10. Privilege, CSRs and traps",
     "fig16-clocks", "Clock domains and reset policy (§25), shown here because the "
                     "privilege FSM and debug entry are clock-domain sensitive.", False),
    ("## 11. PMP and PMA checking",
     "fig10-memorymap", "Physical memory map and attributes.", False),
    ("## 15. Caches",
     "fig14-dcache", "D$ organisation.", True),
    ("## 16. MMU and page-table walker",
     "fig15-ptw", "Page-table walker with the reserved second port.", True),
    ("## 18. Bus fabric",
     "fig07-fabric", "AXI4 fabric topology and the bandwidth budget.", True),
    ("## 19. Tight coupling — MXIF",
     "fig04-pinout-mxif", "MXIF-1.0 coprocessor interface pin-out.", False),
    ("### 19.2 Timing — a vector load, the decoupled case",
     "fig05-timing-mxif", "MXIF two-phase completion timing.", False),
    ("## 20. Loose coupling — the accelerator socket",
     "fig06-pinout-socket", "Accelerator socket pin-out and mandatory register map.", True),
    ("## 22. Data movement patterns for ML workloads",
     "fig09-dataflow", "Accelerator data movement: double buffering and invocation flow.", False),
    ("## 26. The SoC generator",
     "fig17-generator", "The SoC generator: one source of truth.", True),
    ("## 27. Software stack",
     "fig12-software", "Software stack and host toolchain.", True),
    ("## 28. Verification architecture",
     "fig11-verification", "Verification architecture: five layers, all in CI.", True),
    ("## 31. Measurement infrastructure",
     "fig13-measurement", "Measurement infrastructure and the attribution table.", True),
]

# Extra figures with no natural anchor, appended to a section.
EXTRA_AFTER = [
    ("## 7. Stage by stage", "fig03-pinout-core", "s1_core top-level pin-out."),
    ("## 5. Naming, versions and configurations", "fig18-roadmap",
     "Phase plan: each phase ends with something that runs."),
]

TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>$title$</title>
  <style>
$style-inline$
  </style>
</head>
<body>

<div class="titlepage">
  <div class="tp-kicker">Maktab-e-Digital Systems &middot; Lahore</div>
  <div class="tp-title">MEDS-S1</div>
  <div class="tp-sub">An open RISC-V SoC platform for accelerator research</div>
  <div class="tp-rule"></div>
  <div class="tp-meta">
    Platform Specification &nbsp;&middot;&nbsp; Version 0.2 &nbsp;&middot;&nbsp; DRAFT<br>
    Architecture, attachment interfaces, verification, and research methodology
  </div>
  <div class="tp-foot">
    Apache License 2.0 &nbsp;&middot;&nbsp; Pre-RTL. Nothing herein is frozen until the
    Phase&nbsp;0 design review.<br>
    Companion documents: INTERFACES (normative) &middot; SCOPE CONTRACT &middot;
    EXECUTION PLAN &middot; GITHUB WORKFLOW
  </div>
</div>

$if(toc)$
<h1 class="toc-title">Contents</h1>
<nav id="TOC" role="doc-toc">
$table-of-contents$
</nav>
$endif$

$body$
</body>
</html>
"""

CSS = r"""
@page {
  size: A4;
  margin: 18mm 16mm 20mm 16mm;
  @bottom-center { content: counter(page); }
}
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body {
  font-family: "DejaVu Serif", Georgia, serif;
  font-size: 9.7pt; line-height: 1.48; color: #1a1a1a; margin: 0;
}

/* ---------- title page ---------- */
.titlepage { text-align: center; padding-top: 52mm; }
.tp-kicker { font-family: "DejaVu Sans", sans-serif; font-size: 10pt;
  letter-spacing: 0.22em; text-transform: uppercase; color: #6b6b6b; }
.tp-title { font-family: "DejaVu Sans", sans-serif; font-size: 52pt; font-weight: 700;
  line-height: 1.1; margin: 12mm 0 4mm 0; color: #111; letter-spacing: 0.02em; }
.tp-sub { font-size: 13pt; font-style: italic; color: #444; }
.tp-rule { width: 60mm; height: 2px; background: #b03a2e; margin: 12mm auto; }
.tp-meta { font-size: 10.5pt; color: #333; line-height: 1.7; }
.tp-foot { margin-top: 28mm; font-size: 8.5pt; color: #777; line-height: 1.6; }

/* ---------- headings ---------- */
h1, h2, h3, h4 { font-family: "DejaVu Sans", sans-serif; color: #111; line-height: 1.25; }
h1 { font-size: 19pt; page-break-before: always; padding-bottom: 3mm;
  border-bottom: 2px solid #b03a2e; margin: 0 0 6mm 0; }
h2 { font-size: 12.5pt; margin: 7mm 0 3mm 0; page-break-after: avoid;
  border-bottom: 0.5pt solid #ddd; padding-bottom: 1.4mm; }
h3 { font-size: 10.8pt; margin: 5mm 0 2mm 0; page-break-after: avoid; }
h4 { font-size: 9.8pt; margin: 4mm 0 2mm 0; page-break-after: avoid; }
p { margin: 0 0 2.4mm 0; orphans: 3; widows: 3; }

/* ---------- code ---------- */
code { font-family: "DejaVu Sans Mono", monospace; font-size: 0.86em;
  background: #f2f2f0; padding: 0.5pt 2pt; border-radius: 2px; }
pre { font-family: "DejaVu Sans Mono", monospace; font-size: 6.9pt; line-height: 1.26;
  background: #f7f7f5; border: 0.6pt solid #dcdcd6; border-left: 2.5pt solid #b03a2e;
  padding: 2.4mm 3mm; margin: 3mm 0; white-space: pre; overflow: visible;
  page-break-inside: avoid; }
pre code { background: none; padding: 0; font-size: inherit; }
pre.tall { page-break-inside: auto; }

/* ---------- figures ---------- */
figure { margin: 5mm 0; page-break-inside: avoid; text-align: center; }
figure img, figure svg { max-width: 100%; height: auto; }
figcaption { font-family: "DejaVu Sans", sans-serif; font-size: 8.2pt; color: #6b6b6b;
  margin-top: 2mm; text-align: center; font-style: italic; }
figcaption .fignum { font-style: normal; font-weight: 700; color: #b03a2e; }

/* ---------- tables ---------- */
table { border-collapse: collapse; width: 100%; margin: 3mm 0; font-size: 8.1pt;
  page-break-inside: avoid; }
th, td { border: 0.5pt solid #ccc; padding: 1.1mm 1.8mm; text-align: left;
  vertical-align: top; }
th { background: #efefec; font-family: "DejaVu Sans", sans-serif; font-weight: 700; }
tr:nth-child(even) td { background: #fafaf8; }
td code, th code { font-size: 0.92em; }

/* ---------- callouts ---------- */
blockquote { margin: 3.5mm 0; padding: 2.4mm 3.4mm; background: #f6f6fb;
  border-left: 2.5pt solid #5566aa; page-break-inside: avoid; font-size: 0.97em; }
blockquote p:last-child { margin-bottom: 0; }

ul, ol { margin: 0 0 2.4mm 0; padding-left: 6mm; }
li { margin-bottom: 0.7mm; }
hr { border: none; border-top: 0.5pt solid #ddd; margin: 5mm 0; }
a { color: #1a4f8a; text-decoration: none; }

/* ---------- contents ---------- */
h1.toc-title { page-break-before: always; font-size: 19pt;
  border-bottom: 2px solid #b03a2e; padding-bottom: 3mm; margin: 0 0 6mm 0; }
#TOC { page-break-after: always; }
#TOC > ul { list-style: none; padding-left: 0; font-family: "DejaVu Sans", sans-serif; }
#TOC > ul > li { margin: 1.5mm 0; font-weight: 700; font-size: 9.6pt; }
#TOC ul ul { list-style: none; padding-left: 5mm; font-weight: 400; font-size: 8.4pt; }
#TOC ul ul ul { display: none; }
#TOC a { color: #222; }
"""


# ---------------------------------------------------------------------------
def find_chrome() -> str:
    for c in ("google-chrome", "chromium", "chromium-browser", "chrome"):
        p = shutil.which(c)
        if p:
            return p
    sys.exit("error: no chrome/chromium found")


def svg_data_uri(path: pathlib.Path) -> str:
    b = base64.b64encode(path.read_bytes()).decode()
    return f"data:image/svg+xml;base64,{b}"


def render_mermaid(md: str, tmp: pathlib.Path) -> str:
    """Render ```mermaid blocks with mmdc; drop them if mmdc is unavailable."""
    mmdc = shutil.which("mmdc")
    blocks = re.findall(r"```mermaid\n(.*?)\n```", md, flags=re.S)
    if not blocks:
        return md
    if not mmdc:
        print("  ! mmdc not found -- mermaid diagrams omitted")
        return re.sub(r"```mermaid\n.*?\n```\n?", "", md, flags=re.S)

    cfg = tmp / "mmdc.json"
    cfg.write_text(json.dumps({
        "theme": "neutral",
        "themeVariables": {
            "fontFamily": "DejaVu Sans, Helvetica, sans-serif",
            "fontSize": "15px",
            "primaryColor": "#eaf0f9",
            "primaryBorderColor": "#3b5b8c",
            "primaryTextColor": "#16314f",
            "lineColor": "#555555",
            "secondaryColor": "#fdf2e2",
            "tertiaryColor": "#e9f4ea",
            # the neutral theme's default note is dark grey on white text, which
            # reads as an error next to the rest of the palette
            "noteBkgColor": "#fdf2e2",
            "noteTextColor": "#6d4310",
            "noteBorderColor": "#b5711f",
        },
    }))
    # mmdc drives puppeteer, which by default looks for its own bundled Chrome.
    # Point it at the system browser we already located.
    pup = tmp / "pup.json"
    pup.write_text(json.dumps({
        "executablePath": find_chrome(),
        "args": ["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"],
    }))

    print(f"  rendering {len(blocks)} mermaid diagram(s)")
    ok = 0

    def repl(m):
        nonlocal ok
        src = m.group(1)
        h = hashlib.sha1(src.encode()).hexdigest()[:10]
        inp, outp = tmp / f"mm{h}.mmd", tmp / f"mm{h}.svg"
        inp.write_text(src)
        r = subprocess.run([mmdc, "-i", str(inp), "-o", str(outp), "-c", str(cfg),
                            "-p", str(pup), "-b", "white"],
                           capture_output=True, text=True)
        if r.returncode != 0 or not outp.exists():
            print(f"    ! mermaid block {h} failed: {r.stderr.strip()[:160]}")
            return ""
        ok += 1
        return (f'<figure><img src="{svg_data_uri(outp)}" alt="diagram"/></figure>\n')

    out = re.sub(r"```mermaid\n(.*?)\n```", repl, md, flags=re.S)
    print(f"    {ok}/{len(blocks)} rendered")
    return out


def inject_figures(md: str) -> str:
    """Insert generated SVGs at their anchors, numbering them in document order."""
    lines = md.split("\n")
    out: list[str] = []
    n = 0
    missing = []

    plan: dict[str, list[tuple[str, str, bool]]] = {}
    for anchor, stem, cap, repl in FIGURES:
        plan.setdefault(anchor, []).append((stem, cap, repl))
    for anchor, stem, cap in EXTRA_AFTER:
        plan.setdefault(anchor, []).append((stem, cap, False))

    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        if line.strip() not in plan:
            continue
        for stem, cap, repl in plan[line.strip()]:
            p = FIGDIR / f"{stem}.svg"
            if not p.exists():
                missing.append(stem)
                continue
            # carry the intervening prose across, up to the next fenced block
            buf = []
            j = i
            while j < len(lines) and not lines[j].startswith("```"):
                if lines[j].startswith("#"):
                    break
                buf.append(lines[j])
                j += 1
            hit_fence = j < len(lines) and lines[j].startswith("```")
            out.extend(buf)
            i = j
            if repl and hit_fence:                      # drop the ASCII original
                k = j + 1
                while k < len(lines) and not lines[k].startswith("```"):
                    k += 1
                i = k + 1
            n += 1
            out.append("")
            out.append(
                f'<figure><img src="{svg_data_uri(p)}" alt="{cap}"/>'
                f'<figcaption><span class="fignum">Figure {n}</span> — {cap}</figcaption>'
                f'</figure>'
            )
            out.append("")
    if missing:
        print(f"  ! missing figures: {', '.join(missing)}")
    print(f"  injected {n} generated figures")
    return "\n".join(out)


def preprocess(md: str) -> str:
    # The in-document contents block duplicates the generated TOC.
    md = re.sub(r"^## Contents\n.*?(?=^---$)", "", md, flags=re.S | re.M)
    # Horizontal-rule pairs used as part separators produce empty pages.
    md = md.replace("\n---\n---\n", "\n---\n")
    # Tag very tall ASCII blocks so they may break across pages.
    def tall(m):
        body = m.group(0)
        return body if body.count("\n") < 46 else body.replace("```\n", "```{.tall}\n", 1)
    md = re.sub(r"```[a-z]*\n.*?\n```", tall, md, flags=re.S)
    return md


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep-html", action="store_true")
    ap.add_argument("--gen", action="store_true", help="regenerate figures first")
    ap.add_argument("-o", "--output", default=str(OUT))
    args = ap.parse_args()

    if not shutil.which("pandoc"):
        sys.exit("error: pandoc not found")
    chrome = find_chrome()

    if args.gen:
        print("generating figures")
        subprocess.run([sys.executable, str(ROOT / "scripts" / "gen_diagrams.py")],
                       check=True, capture_output=True)

    md = SRC.read_text(encoding="utf-8")
    print(f"source: {SRC.name}  ({len(md.splitlines())} lines)")

    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        md = preprocess(md)
        md = inject_figures(md)
        md = render_mermaid(md, tmp)

        (tmp / "spec.md").write_text(md, encoding="utf-8")
        (tmp / "tpl.html").write_text(TEMPLATE, encoding="utf-8")
        (tmp / "style.css").write_text(CSS, encoding="utf-8")

        html_path = tmp / "spec.html"
        r = subprocess.run([
            "pandoc", str(tmp / "spec.md"),
            "-f", "markdown+pipe_tables+backtick_code_blocks+raw_html+"
                  "fenced_code_attributes+auto_identifiers",
            "-t", "html5", "--standalone",
            "--template", str(tmp / "tpl.html"),
            "--metadata", "title=MEDS-S1 Platform Specification",
            "--metadata", f"style-inline={CSS}",
            "--toc", "--toc-depth=2",
            "-o", str(html_path),
        ], capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"pandoc failed:\n{r.stderr}")

        # pandoc puts $style-inline$ through as metadata; make sure it landed
        h = html_path.read_text(encoding="utf-8")
        if "@page" not in h:
            h = h.replace("</head>", f"<style>{CSS}</style></head>")
            html_path.write_text(h, encoding="utf-8")

        outp = pathlib.Path(args.output).resolve()
        outp.parent.mkdir(parents=True, exist_ok=True)
        print("rendering PDF via headless Chrome")
        r = subprocess.run([
            chrome, "--headless", "--disable-gpu", "--no-sandbox",
            "--no-pdf-header-footer", "--run-all-compositor-stages-before-draw",
            "--virtual-time-budget=30000",
            f"--print-to-pdf={outp}", html_path.as_uri(),
        ], capture_output=True, text=True)
        if not outp.exists():
            sys.exit(f"chrome failed:\n{r.stderr[-2000:]}")

        if args.keep_html:
            keep = outp.with_suffix(".html")
            shutil.copy(html_path, keep)
            print(f"  html: {keep}")

    size = outp.stat().st_size / 1024
    print(f"\n  {outp}  ({size:.0f} KB)")


if __name__ == "__main__":
    main()
