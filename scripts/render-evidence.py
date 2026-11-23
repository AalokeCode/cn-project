#!/usr/bin/env python3
"""Render every evidence .txt in a folder (real command + real output, saved by the
mac4 scripts) into a terminal-style .png beside it. Same look as scripts/shot.py.

Usage: python3 scripts/render-evidence.py [evidence-dir]     (needs: pip install pillow)
"""
import pathlib
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
EVID = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Evidence/phase2/mac4"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
WRAP = 130  # characters per line before wrapping
HIGHLIGHT = re.compile(r"X-Backend: B|304 Not Modified|\b30\s+IN\s+A\b|Status: \w+|block return|pass in")

try:
    FONT = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
    BOLD = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15, index=1)
except OSError:
    FONT = BOLD = ImageFont.load_default()


def wrap(line: str):
    line = line.expandtabs(8)
    return [line[i:i + WRAP] for i in range(0, max(len(line), 1), WRAP)] or [""]


def render(txt: pathlib.Path) -> None:
    raw = ANSI.sub("", txt.read_text(errors="replace")).rstrip().splitlines()
    rows = []  # (text, kind)
    for l in raw:
        kind = "head" if l.startswith("#") else "cmd" if l.startswith("$ ") else (
            "hl" if HIGHLIGHT.search(l) else "out")
        rows += [(w, kind) for w in wrap(l)]
    lh = 20
    w = max(FONT.getlength(t) for t, _ in rows) + 40
    img = Image.new("RGB", (int(max(w, 700)), len(rows) * lh + 40), (30, 30, 30))
    dr = ImageDraw.Draw(img)
    colors = {"head": (120, 200, 255), "cmd": (140, 230, 140), "hl": (255, 216, 102), "out": (230, 230, 230)}
    for i, (t, kind) in enumerate(rows):
        dr.text((20, 20 + i * lh), t, font=BOLD if kind == "cmd" else FONT, fill=colors[kind])
    out = txt.with_suffix(".png")
    img.save(out)
    print("rendered", out.name)


if __name__ == "__main__":
    for t in sorted(EVID.glob("*.txt")):
        render(t)
