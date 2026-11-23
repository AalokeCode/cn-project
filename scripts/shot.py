#!/usr/bin/env python3
"""Run a shell command and save its real output as a terminal-style PNG + .txt."""
import subprocess, sys, datetime, socket
from PIL import Image, ImageDraw, ImageFont
name, title, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
body = (res.stdout + res.stderr).rstrip()
ip = subprocess.run("ipconfig getifaddr en0", shell=True, capture_output=True, text=True).stdout.strip()
hdr = f"# {title}\n# {socket.gethostname()} ({ip})  {datetime.datetime.now():%Y-%m-%d %H:%M:%S}\n$ {cmd}\n"
text = (hdr + body + "\n").expandtabs(8)
d = "Evidence/phase2/mac1"
open(f"{d}/{name}.txt", "w").write(text)
try: font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
except Exception: font = ImageFont.load_default()
lines = text.splitlines() or [""]
w = max(font.getlength(l) for l in lines) + 40
h = len(lines) * 20 + 40
img = Image.new("RGB", (int(max(w, 600)), h), (30, 30, 30))
dr = ImageDraw.Draw(img)
for i, l in enumerate(lines):
    col = (120, 200, 255) if l.startswith("#") else (140, 230, 140) if l.startswith("$") else (230, 230, 230)
    dr.text((20, 20 + i * 20), l, font=font, fill=col)
img.save(f"{d}/{name}.png")
print(f"saved {d}/{name}.png")
