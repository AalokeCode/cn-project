#!/usr/bin/env python3
"""Build Reports/Phase2-Final-Report.pdf from the Markdown sources and the evidence screenshots.

Needs: pip install markdown, and Google Chrome (used headless to print the PDF).
Usage: python3 Reports/build_pdf.py
"""
import pathlib
import re
import subprocess

import markdown

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_HTML = ROOT / "Reports" / "build" / "report.html"
OUT_PDF = ROOT / "Reports" / "Phase2-Final-Report.pdf"
REPO_URL = "https://github.com/AalokeCode/cn-project"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Key screenshots per extension (path, caption)
APPENDIX = [
    ("Ext A — backup DNS", [
        ("Evidence/phase2/mac1/extA-3-primary-down.png", "Mac 1: primary DNS stopped, dig to 10.7.5.108 times out"),
        ("Evidence/phase2/mac1/extA-4-still-resolves.png", "Mac 1: name still resolves, answered by the backup 10.7.2.47"),
        ("Evidence/phase2/mac1/extA-5-app-still-works.png", "Mac 1: app still HTTP/2 200 by name"),
    ]),
    ("Ext B — TTL and controlled record change", [
        ("Evidence/phase2/mac1/extB-4-client-still-old.png", "Record changed on both servers, client still uses the cached answer"),
        ("Evidence/phase2/mac1/extB-5-client-new-after-ttl.png", "Client switches about 43 s after caching (TTL 30 s)"),
        ("Evidence/phase2/mac1/extB-7-after-flush.png", "Manual flush: change visible immediately"),
    ]),
    ("Ext C — service isolation (partial)", [
        ("Evidence/phase2/mac4/extC-2-rules-on.png", "Mac 4: pf allows only the edge 10.7.22.206 to :3002"),
        ("Evidence/phase2/mac1/16-extC-mac4-isolated.png", "Mac 1: direct connection to Backend B refused"),
        ("Evidence/phase2/mac2/extC-1-edge-allowed.png", "Mac 2: the edge still reaches both backends"),
    ]),
    ("Ext D — HA failover", [
        ("Evidence/phase2/mac1/extD-2-a-down.png", "Mac 1: Backend A down, 6/6 requests served by B"),
        ("Evidence/phase2/mac2/extD-1-error-log.png", "Mac 2: nginx logs connect() refused to Backend A"),
        ("Evidence/phase2/mac2/extD-2-access-log.png", "Mac 2: the same requests still got 200"),
        ("Evidence/phase2/mac1/extD-3-a-back.png", "Mac 1: Backend A back, balancing resumes"),
    ]),
    ("Ext E — DNS-based edge migration", [
        ("Evidence/phase2/mac3/extE-2-standby-works.png", "Mac 3: standby edge serves x-edge: mac3"),
        ("Evidence/phase2/mac1/extE-2-cached-client.png", "Mac 1: right after the cutover, cached client still on mac2"),
        ("Evidence/phase2/mac1/extE-3-after-ttl.png", "Mac 1: after the TTL, served by mac3"),
        ("Evidence/phase2/mac4/extE-1-fresh-client.png", "Mac 4: fresh client goes straight to the standby"),
    ]),
    ("Edge (Mac 2) configuration", [
        ("Evidence/phase2/mac2/p1-04-upstream.png", "nginx upstream, TLS, HTTP/2 and failover settings"),
        ("Evidence/phase2/mac2/p1-08-load-balancing.png", "Round-robin across Backend A and B"),
        ("Evidence/phase2/mac1/p1-06-tls.png", "Certificate verified by the team CA, no -k"),
    ]),
]

CSS = """
@page { size: A4; margin: 16mm 15mm 18mm 15mm; }
* { box-sizing: border-box; }
body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; color: #0f172a; font-size: 10.5pt; line-height: 1.45; margin: 0; }
h1 { font-size: 20pt; margin: 0 0 4pt; }
h2 { font-size: 14pt; margin: 18pt 0 6pt; padding-bottom: 3pt; border-bottom: 1.5px solid #e2e8f0; break-after: avoid; }
h3 { font-size: 12pt; margin: 12pt 0 4pt; break-after: avoid; }
p { margin: 4pt 0 6pt; }
a { color: #1d4ed8; text-decoration: none; }
code { font-family: Menlo, monospace; font-size: 8.8pt; background: #f1f5f9; padding: 0 2pt; border-radius: 2pt; }
pre { background: #f1f5f9; padding: 6pt 8pt; border-radius: 4pt; font-size: 8.5pt; white-space: pre-wrap; break-inside: avoid; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 6pt 0 10pt; font-size: 8.8pt; break-inside: auto; }
th, td { border: 1px solid #cbd5e1; padding: 3.5pt 5pt; vertical-align: top; text-align: left; }
th { background: #f1f5f9; }
tr { break-inside: avoid; }
ul { margin: 4pt 0 6pt 14pt; padding: 0; }
li { margin: 2pt 0; }
.cover { height: 250mm; display: flex; flex-direction: column; justify-content: center; break-after: page; }
.cover .kicker { color: #64748b; font-size: 12pt; letter-spacing: .04em; text-transform: uppercase; }
.cover h1 { font-size: 30pt; margin: 6pt 0; }
.cover .sub { font-size: 15pt; color: #334155; margin-bottom: 22pt; }
.cover table { width: 75%; font-size: 10.5pt; }
.cover .meta { margin-top: 18pt; color: #475569; }
.fig { break-inside: avoid; margin: 8pt 0 14pt; text-align: center; }
.fig img { width: 100%; border: 1px solid #e2e8f0; border-radius: 4pt; }
.fig .cap { font-size: 8.8pt; color: #475569; margin-top: 3pt; }
.pagebreak { break-before: page; }
.shot { break-inside: avoid; margin: 6pt 0 10pt; }
.shot img { width: 100%; border-radius: 3pt; }
.shot .cap { font-size: 8.8pt; color: #334155; margin-top: 2pt; }
.shot .src { font-family: Menlo, monospace; font-size: 7.5pt; color: #64748b; }
"""


def md(path):
    text = (ROOT / path).read_text(encoding="utf-8")
    html = markdown.markdown(text, extensions=["tables", "fenced_code"])
    # make relative links absolute file links so they resolve from Reports/build/
    base = (ROOT / path).parent
    def fix(m):
        attr, url = m.group(1), m.group(2)
        if re.match(r"^(https?:|#|mailto:)", url):
            return m.group(0)
        target = (base / url).resolve()
        if attr == "href":  # links open the file on GitHub, so they work from any computer
            return f'href="{REPO_URL}/blob/main/{target.relative_to(ROOT).as_posix()}"'
        return f'{attr}="{target.as_uri()}"'
    return re.sub(r'(href|src)="([^"]+)"', fix, html)


def strip_first_h1(html):
    return re.sub(r"<h1>.*?</h1>", "", html, count=1, flags=re.S)


def main():
    uri = lambda p: (ROOT / p).resolve().as_uri()
    parts = [f"""<div class="cover">
  <div class="kicker">Computer Networks · Course Project</div>
  <h1>Private Network Service Platform</h1>
  <div class="sub">Phase 2 Final Report — Harden, Recover &amp; Troubleshoot · Team 1</div>
  <table>
    <tr><th>Mac</th><th>Member</th><th>Role</th><th>IP</th></tr>
    <tr><td>1</td><td>Krishna</td><td>Primary DNS + test client</td><td>10.7.5.108</td></tr>
    <tr><td>2</td><td>Aaloke</td><td>Edge nginx: TLS, HTTP/2, load balancer</td><td>10.7.22.206</td></tr>
    <tr><td>3</td><td>Arina</td><td>Backend A + standby edge</td><td>10.7.17.193</td></tr>
    <tr><td>4</td><td>Hemanth</td><td>Backend B + backup DNS</td><td>10.7.2.47</td></tr>
  </table>
  <div class="meta">Domain <code>app.team1.test</code> · run on 2026-11-23 · repository: github.com/AalokeCode/cn-project</div>
</div>"""]

    parts.append("<h1>Part 1 — Architecture</h1>")
    parts.append(f'<div class="fig"><img src="{uri("Architecture/topology-phase2.png")}"><div class="cap">Figure 1 — Phase 2 topology</div></div>')
    parts.append(f'<div class="fig pagebreak"><img src="{uri("Architecture/request-flow-phase2.png")}"><div class="cap">Figure 2 — Request flow for one HTTPS request, with the Ext D failover path</div></div>')
    arch = strip_first_h1(md("Architecture/phase2.md"))
    arch = re.sub(r"<h2>Topology</h2>.*?(?=<h2>)", "", arch, flags=re.S)  # ASCII art replaced by Figure 1
    parts.append(f'<div class="pagebreak"><h2>Network details</h2>{arch}</div>')

    report = strip_first_h1(md("Reports/Phase2-Final-Report.md"))
    report = re.sub(r"<p>Krishna \(Mac 1\).*?</p>", "", report, count=1, flags=re.S)
    parts.append(f'<div class="pagebreak"><h1>Part 2 — Final report</h1>{report}</div>')

    parts.append('<div class="pagebreak"><h1>Part 3 — Evidence highlights</h1>'
                 '<p>Selected screenshots. Every item is also in the repository as a <code>.txt</code> with the raw command output; '
                 'the full index is <code>SUBMISSION.md</code>.</p>')
    for title, shots in APPENDIX:
        parts.append(f"<h2>{title}</h2>")
        for path, cap in shots:
            parts.append(f'<div class="shot"><img src="{uri(path)}"><div class="cap">{cap}</div><div class="src">{path}</div></div>')
    parts.append("</div>")

    OUT_HTML.parent.mkdir(parents=True, exist_ok=True)
    OUT_HTML.write_text(f'<!doctype html><html><head><meta charset="utf-8"><title>Phase 2 Final Report — Team 1</title>'
                        f'<style>{CSS}</style></head><body>{"".join(parts)}</body></html>', encoding="utf-8")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    "--allow-file-access-from-files", f"--print-to-pdf={OUT_PDF}", OUT_HTML.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"wrote {OUT_PDF.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
