#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""
svgkit -- a small SVG drawing helper for MEDS-S1 specification figures.

Deliberately minimal: boxes, arrows, buses, pin rows, timing waveforms.  Enough
to draw block diagrams, module pin-outs and timing diagrams in a consistent
visual language, and nothing else.

Coordinates are in px with y increasing downwards.  Everything is emitted with a
viewBox so the figures scale cleanly into print at any size.

Usage:
    from svgkit import Canvas, P
    c = Canvas(900, 500)
    c.box(20, 20, 200, 60, "meds_s1_core", style="core")
    c.save("out.svg")
"""
from __future__ import annotations

import html
import math
import pathlib

# --------------------------------------------------------------------------
# Palette.  Matches the MEDS book house style: #b03a2e accent on a light page.
# --------------------------------------------------------------------------

P = {
    "accent":    "#b03a2e",
    "ink":       "#1a1a1a",
    "muted":     "#6b6b6b",
    "line":      "#555555",
    "faint":     "#bbbbbb",
    "page":      "#ffffff",
}

# Named block styles: (fill, stroke, text)
STYLES = {
    "core":    ("#eaf0f9", "#3b5b8c", "#16314f"),   # CPU / pipeline
    "mem":     ("#e9f4ea", "#3f7a45", "#1d4423"),   # memory, caches, DRAM
    "fabric":  ("#f1ecf8", "#6b4c9a", "#3a2559"),   # bus, crossbar
    "accel":   ("#fdf2e2", "#b5711f", "#6d4310"),   # accelerators, sockets
    "periph":  ("#f2f2ef", "#6f6f6f", "#333333"),   # peripherals
    "verif":   ("#fdeceb", "#b03a2e", "#6d211a"),   # verification, debug
    "sw":      ("#eaf3f6", "#3f7f95", "#1c4855"),   # software layers
    "plain":   ("#ffffff", "#555555", "#1a1a1a"),
    "ghost":   ("#fafafa", "#bbbbbb", "#888888"),   # present-but-tied-off
}

MONO = "DejaVu Sans Mono, Menlo, Consolas, monospace"
SANS = "DejaVu Sans, Helvetica, Arial, sans-serif"


def esc(s: str) -> str:
    return html.escape(str(s), quote=True)


def tw(s: str, size: float, family: str = SANS, bold: bool = False) -> float:
    """Approximate rendered text width in px."""
    k = 0.60 if family == MONO else (0.58 if bold else 0.53)
    return len(s) * size * k


class Canvas:
    def __init__(self, w: float, h: float, pad: float = 0):
        self.w = w + 2 * pad
        self.h = h + 2 * pad
        self.pad = pad
        self.parts: list[str] = []
        self._defs: list[str] = []
        self._arrow_ids: set[str] = set()

    # ---------------------------------------------------------------- defs
    def _marker(self, color: str, size: str = "m") -> str:
        mid = f"a{size}{color.lstrip('#')}"
        if mid not in self._arrow_ids:
            self._arrow_ids.add(mid)
            s = {"s": 5, "m": 7, "l": 9}[size]
            self._defs.append(
                f'<marker id="{mid}" viewBox="0 0 10 10" refX="9" refY="5" '
                f'markerWidth="{s}" markerHeight="{s}" orient="auto-start-reverse">'
                f'<path d="M0,1 L10,5 L0,9 z" fill="{color}"/></marker>'
            )
        return mid

    # --------------------------------------------------------------- prims
    def text(self, x, y, s, size=12, anchor="middle", family=SANS,
             weight="normal", color=None, italic=False, opacity=1.0):
        color = color or P["ink"]
        style = f'font-style:italic;' if italic else ''
        self.parts.append(
            f'<text x="{x:.1f}" y="{y:.1f}" font-family="{family}" '
            f'font-size="{size}" font-weight="{weight}" fill="{color}" '
            f'text-anchor="{anchor}" opacity="{opacity}" style="{style}">{esc(s)}</text>'
        )
        return self

    def lines(self, x, y, rows, size=11, anchor="middle", family=SANS,
              weight="normal", color=None, lh=1.35):
        """Multi-line text block, first baseline at y."""
        for i, r in enumerate(rows):
            self.text(x, y + i * size * lh, r, size, anchor, family, weight, color)
        return self

    def rect(self, x, y, w, h, fill="none", stroke=P["line"], sw=1.2, rx=3,
             dash=None, opacity=1.0):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.parts.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
            f'rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d} '
            f'opacity="{opacity}"/>'
        )
        return self

    def line(self, x1, y1, x2, y2, color=P["line"], sw=1.2, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.parts.append(
            f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{color}" stroke-width="{sw}"{d} stroke-linecap="round"/>'
        )
        return self

    def path(self, d, color=P["line"], sw=1.2, fill="none", dash=None,
             arrow=False, arrow_size="m", back_arrow=False):
        extra = f' stroke-dasharray="{dash}"' if dash else ""
        if arrow:
            extra += f' marker-end="url(#{self._marker(color, arrow_size)})"'
        if back_arrow:
            extra += f' marker-start="url(#{self._marker(color, arrow_size)})"'
        self.parts.append(
            f'<path d="{d}" fill="{fill}" stroke="{color}" stroke-width="{sw}" '
            f'stroke-linejoin="round" stroke-linecap="round"{extra}/>'
        )
        return self

    # --------------------------------------------------------------- boxes
    def box(self, x, y, w, h, label=None, sub=None, style="plain",
            size=12, sub_size=9.5, dash=None, sw=1.3, rx=4, label_dy=0):
        fill, stroke, tcol = STYLES[style]
        self.rect(x, y, w, h, fill, stroke, sw, rx, dash)
        cx = x + w / 2
        if label is not None and sub:
            self.text(cx, y + h / 2 - 3 + label_dy, label, size, color=tcol, weight="bold")
            for i, s in enumerate(sub if isinstance(sub, (list, tuple)) else [sub]):
                self.text(cx, y + h / 2 + 11 + i * (sub_size * 1.3) + label_dy,
                          s, sub_size, color=tcol, opacity=0.85)
        elif label is not None:
            rows = label if isinstance(label, (list, tuple)) else [label]
            y0 = y + h / 2 - (len(rows) - 1) * size * 0.62 + size * 0.34 + label_dy
            for i, r in enumerate(rows):
                self.text(cx, y0 + i * size * 1.25, r, size, color=tcol, weight="bold")
        return self

    def group(self, x, y, w, h, title=None, style="plain", dash="5 3",
              title_size=10.5, sw=1.1):
        """A labelled container drawn behind its children."""
        fill, stroke, tcol = STYLES[style]
        self.rect(x, y, w, h, fill, stroke, sw, 6, dash)
        if title:
            self.text(x + 10, y + 15, title, title_size, anchor="start",
                      color=tcol, weight="bold")
        return self

    # -------------------------------------------------------------- arrows
    def arrow(self, x1, y1, x2, y2, label=None, color=P["line"], sw=1.3,
              dash=None, label_size=9, label_pos=0.5, label_dy=-4,
              label_anchor="middle", both=False, size="m"):
        self.path(f"M{x1:.1f},{y1:.1f} L{x2:.1f},{y2:.1f}", color, sw,
                  dash=dash, arrow=True, back_arrow=both, arrow_size=size)
        if label:
            lx = x1 + (x2 - x1) * label_pos
            ly = y1 + (y2 - y1) * label_pos + label_dy
            self.text(lx, ly, label, label_size, label_anchor, color=color)
        return self

    def elbow(self, x1, y1, x2, y2, label=None, color=P["line"], sw=1.3,
              first="h", dash=None, both=False, label_size=9, label_dy=-5,
              label_anchor="middle", size="m"):
        """Right-angled connector.  first='h' goes horizontal then vertical."""
        if first == "h":
            d = f"M{x1:.1f},{y1:.1f} L{x2:.1f},{y1:.1f} L{x2:.1f},{y2:.1f}"
            lx, ly = (x1 + x2) / 2, y1 + label_dy
        else:
            d = f"M{x1:.1f},{y1:.1f} L{x1:.1f},{y2:.1f} L{x2:.1f},{y2:.1f}"
            lx, ly = (x1 + x2) / 2, y2 + label_dy
        self.path(d, color, sw, dash=dash, arrow=True, back_arrow=both, arrow_size=size)
        if label:
            self.text(lx, ly, label, label_size, label_anchor, color=color)
        return self

    def bus(self, x1, y1, x2, y2, width_label=None, color="#6b4c9a", sw=4.0,
            label=None, label_dy=-8, both=False):
        """A thick line denoting a wide data path."""
        self.path(f"M{x1:.1f},{y1:.1f} L{x2:.1f},{y2:.1f}", color, sw,
                  arrow=True, back_arrow=both, arrow_size="l")
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        if width_label:
            # slash-and-number bus width annotation
            ang = math.degrees(math.atan2(y2 - y1, x2 - x1))
            self.parts.append(
                f'<g transform="translate({mx:.1f},{my:.1f}) rotate({ang:.1f})">'
                f'<line x1="-5" y1="7" x2="5" y2="-7" stroke="{color}" stroke-width="1.6"/>'
                f'</g>'
            )
            self.text(mx + 12, my - 6, width_label, 8.5, "start", MONO, color=color)
        if label:
            self.text(mx, my + label_dy, label, 9, color=color)
        return self

    # ----------------------------------------------------------- pin-outs
    def pinout(self, x, y, w, h, name, left=None, right=None, top=None,
               bottom=None, style="core", stub=34, pitch=17, name_size=13,
               pin_size=8.6, sub=None):
        """
        Draw a module pin-out diagram.

        left/right/top/bottom are lists of groups:
            (group_label, [(signal, dir), ...])
        where dir is 'in', 'out' or 'io'.  Signals are drawn as stubs with
        direction arrows, bracketed and labelled by group.
        """
        fill, stroke, tcol = STYLES[style]
        self.rect(x, y, w, h, fill, stroke, 1.6, 5)
        self.text(x + w / 2, y + h / 2 + (0 if not sub else -6), name,
                  name_size, family=MONO, color=tcol, weight="bold")
        if sub:
            for i, s in enumerate(sub if isinstance(sub, (list, tuple)) else [sub]):
                self.text(x + w / 2, y + h / 2 + 12 + i * 12, s, 9, color=tcol,
                          opacity=0.8)

        def side(groups, is_left):
            if not groups:
                return
            n = sum(len(g[1]) for g in groups) + (len(groups) - 1)
            total = (n - 1) * pitch
            cy = y + h / 2 - total / 2
            row = 0
            for gi, (glabel, sigs) in enumerate(groups):
                g_first = row
                for sig, d in sigs:
                    yy = cy + row * pitch
                    if is_left:
                        sx, ex = x - stub, x
                    else:
                        sx, ex = x + w, x + w + stub
                    # direction: arrow points into the module for inputs
                    if d == "in":
                        a1, a2 = (sx, ex) if is_left else (ex, sx)
                    elif d == "out":
                        a1, a2 = (ex, sx) if is_left else (sx, ex)
                    else:
                        a1, a2 = (sx, ex)
                    col = {"in": "#3b5b8c", "out": "#b5711f", "io": "#6b4c9a"}[d]
                    self.path(f"M{a1:.1f},{yy:.1f} L{a2:.1f},{yy:.1f}", col, 1.25,
                              arrow=True, arrow_size="s",
                              back_arrow=(d == "io"))
                    tx = sx - 6 if is_left else ex + 6
                    self.text(tx, yy + 3, sig, pin_size, "end" if is_left else "start",
                              MONO, color=P["ink"])
                    row += 1
                # group heading: horizontal, above the group's first pin, with a
                # rule spanning the label column.  Rotated labels clip badly on
                # short groups and collide with anything placed alongside.
                if glabel:
                    gy = cy + g_first * pitch - 13
                    gw = self._maxw(sigs, pin_size)
                    if is_left:
                        lx, anchor = x - stub - 6, "end"
                        r0, r1 = lx - gw, lx
                    else:
                        lx, anchor = x + w + stub + 6, "start"
                        r0, r1 = lx, lx + gw
                    self.text(lx, gy, glabel.upper(), 8.2, anchor, SANS,
                              weight="bold", color=P["muted"])
                    self.line(r0, gy + 3.5, r1, gy + 3.5, P["faint"], 0.7)
                row += 1  # gap between groups

        side(left, True)
        side(right, False)

        for groups, is_top in ((top, True), (bottom, False)):
            if not groups:
                continue
            sigs = [s for _, ss in groups for s in ss]
            n = len(sigs)
            xpitch = w / (n + 1)
            for i, (sig, d) in enumerate(sigs):
                xx = x + (i + 1) * xpitch
                if is_top:
                    sy, ey = y - stub, y
                else:
                    sy, ey = y + h, y + h + stub
                if d == "in":
                    a1, a2 = (sy, ey) if is_top else (ey, sy)
                elif d == "out":
                    a1, a2 = (ey, sy) if is_top else (sy, ey)
                else:
                    a1, a2 = (sy, ey)
                col = {"in": "#3b5b8c", "out": "#b5711f", "io": "#6b4c9a"}[d]
                self.path(f"M{xx:.1f},{a1:.1f} L{xx:.1f},{a2:.1f}", col, 1.25,
                          arrow=True, arrow_size="s", back_arrow=(d == "io"))
                ty = sy - 6 if is_top else ey + 12
                self.text(xx, ty, sig, pin_size, "middle", MONO)
        return self

    @staticmethod
    def _maxw(sigs, size):
        return max((tw(s, size, MONO) for s, _ in sigs), default=0)

    def legend(self, x, y, items, size=9, gap=15, swatch=11):
        """items: [(label, style_or_color), ...]"""
        for i, (label, st) in enumerate(items):
            yy = y + i * gap
            if st in STYLES:
                fill, stroke, _ = STYLES[st]
            else:
                fill, stroke = st, st
            self.rect(x, yy - swatch + 3, swatch, swatch, fill, stroke, 1.0, 2)
            self.text(x + swatch + 6, yy, label, size, "start", color=P["muted"])
        return self

    # -------------------------------------------------------------- timing
    def timing(self, x, y, signals, cycles, cw=34, rh=26, label_w=140,
               title=None, marks=None, notes=None):
        """
        Draw a timing diagram.

        signals: [(name, pattern)] where pattern is a string with one char per
                 cycle:  '_' low, '-' high, 'X' don't-care/busy, '.' omitted
        marks:   [(cycle, text, colour)] vertical annotation lines
        notes:   [(cycle, row, text)] callouts anchored to a cell
        """
        x0 = x + label_w
        if title:
            self.text(x, y - 26, title, 10.5, "start", weight="bold", color=P["ink"])
        # cycle ruler
        for c in range(cycles + 1):
            xx = x0 + c * cw
            self.line(xx, y - 6, xx, y + len(signals) * rh + 4, P["faint"], 0.7,
                      dash="2 3")
        for c in range(cycles):
            self.text(x0 + c * cw + cw / 2, y - 9, str(c), 8, color=P["muted"],
                      family=MONO)

        for r, (name, pat) in enumerate(signals):
            yy = y + r * rh
            top, bot = yy + 5, yy + rh - 7
            self.text(x0 - 10, (top + bot) / 2 + 3, name, 9, "end", MONO,
                      color=P["ink"])
            prev = None
            for c in range(min(cycles, len(pat))):
                ch = pat[c]
                cx0, cx1 = x0 + c * cw, x0 + (c + 1) * cw
                if ch == ".":
                    prev = None
                    continue
                lvl = bot if ch == "_" else top
                if ch == "X":
                    self.rect(cx0, top, cw, bot - top, "#f0e7d6", "#b5711f", 1.0, 2)
                else:
                    self.line(cx0, lvl, cx1, lvl, P["accent"] if ch == "-" else P["line"],
                              1.9 if ch == "-" else 1.4)
                if prev is not None and prev != ch and ch in "-_" and prev in "-_":
                    self.line(cx0, top, cx0, bot,
                              P["accent"] if ch == "-" else P["line"], 1.5)
                prev = ch

        # marks: (cycle, text, colour[, stagger_row]).  Text may contain newlines.
        base = y + len(signals) * rh
        for mk in (marks or []):
            c_, text, col = mk[0], mk[1], mk[2]
            srow = mk[3] if len(mk) > 3 else 0
            xx = x0 + c_ * cw
            drop = 12 + srow * 30
            self.line(xx, y - 4, xx, base + drop, col, 1.4, dash="4 3")
            for i, ln in enumerate(str(text).split("\n")):
                self.text(xx, base + drop + 12 + i * 11, ln, 8.4, "middle",
                          color=col, weight="bold")

        for (c, r, text, *rest) in (notes or []):
            anchor = rest[0] if rest else "start"
            xx = x0 + c * cw + cw / 2
            yy = y + r * rh + rh / 2
            self.text(xx + (8 if anchor == "start" else -8), yy + 3, text, 8.4,
                      anchor, color=P["muted"], italic=True)
        return self

    # ---------------------------------------------------------------- out
    def caption(self, text, y=None):
        self.text(self.w / 2, y or (self.h - 8), text, 9.5, color=P["muted"],
                  italic=True)
        return self

    def to_svg(self) -> str:
        defs = f"<defs>{''.join(self._defs)}</defs>" if self._defs else ""
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w:.0f}" '
            f'height="{self.h:.0f}" viewBox="0 0 {self.w:.0f} {self.h:.0f}">'
            f'<rect width="100%" height="100%" fill="{P["page"]}"/>'
            f'{defs}{"".join(self.parts)}</svg>'
        )

    def save(self, path):
        p = pathlib.Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(self.to_svg(), encoding="utf-8")
        return p
