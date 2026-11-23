#!/bin/bash
# Render every <evidence-dir>/*.txt as a terminal-style PNG screenshot next to it.
# The text is the real command output saved by macN.sh; this only turns it into an image.
# Usage: ./scripts/evidence-to-png.sh Evidence/phase2/mac2
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$REPO/${1:?usage: $0 Evidence/phase2/macN}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)

for txt in "$DIR"/*.txt; do
  [[ -e $txt ]] || { echo "no .txt files in $DIR"; exit 1; }
  name=$(basename "$txt" .txt)
  # count wrapped rows too: ~125 characters fit on one 1100px line
  lines=$(awk '{ n += (length($0) > 125) ? int((length($0) + 124) / 125) : 1 } END { print n + 1 }' "$txt")
  height=$(( lines * 19 + 90 + 120 ))  # headless Chrome loses ~100px of the window to browser UI
  (( height < 240 )) && height=240
  python3 - "$txt" "$TMP/$name.html" "$name" <<'PY'
import html, sys
src, out, name = sys.argv[1:4]
body = html.escape(open(src, encoding="utf-8", errors="replace").read())
lines = []
for line in body.splitlines():
    if line.startswith("# "):
        lines.append(f'<span class="c">{line}</span>')
    elif line.startswith("$ "):
        lines.append(f'<span class="p">{line}</span>')
    else:
        lines.append(line)
page = f"""<!doctype html><meta charset="utf-8"><style>
body{{margin:0;background:#1e1e1e;font:14px/19px Menlo,monospace;color:#d4d4d4}}
.bar{{background:#323233;color:#aaa;padding:8px 14px;font:12px -apple-system,sans-serif}}
.bar b{{color:#ff5f57}}.bar i{{color:#febc2e;font-style:normal}}.bar u{{color:#28c840;text-decoration:none}}
pre{{margin:0;padding:14px;white-space:pre-wrap;word-break:break-all}}
.c{{color:#6a9955}}.p{{color:#4fc1ff;font-weight:bold}}</style>
<div class="bar"><b>&#9679;</b> <i>&#9679;</i> <u>&#9679;</u> &nbsp; Terminal &mdash; {name}</div>
<pre>{chr(10).join(lines)}</pre>"""
open(out, "w", encoding="utf-8").write(page)
PY
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1100,"$height" \
    --screenshot="$DIR/$name.png" "file://$TMP/$name.html" >/dev/null 2>&1
  echo "saved $(basename "$DIR")/$name.png"
done
rm -rf "$TMP"
