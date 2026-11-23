#!/usr/bin/env python3
"""Team coordination board for the Phase 2 run. Runs on Mac 2 (the coordinator), port 8099.

The four Macs' agents talk through it over the LAN:
  POST /send    {"from": "mac3", "to": "mac2" | "all", "text": "..."}  -> {"id": N}
  GET  /read?me=mac3&since=N   messages with id > N addressed to me or "all" (and the ones I sent)
  GET  /board                  every message, plain text (for humans)

Messages are kept in memory and appended to coord/log.jsonl (not committed).
Usage: python3 scripts/coord-server.py
"""
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = 8099
NAMES = {"mac1", "mac2", "mac3", "mac4", "all"}
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "coord", "log.jsonl")

messages = []
lock = threading.Lock()

os.makedirs(os.path.dirname(LOG), exist_ok=True)
if os.path.exists(LOG):
    with open(LOG, encoding="utf-8") as f:
        messages = [json.loads(line) for line in f if line.strip()]


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if urlparse(self.path).path != "/send":
            return self._send(404, {"error": "use POST /send"})
        try:
            msg = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            src, dst, text = msg["from"].lower(), msg["to"].lower(), str(msg["text"]).strip()
        except (ValueError, KeyError, AttributeError):
            return self._send(400, {"error": 'body must be {"from","to","text"}'})
        if src not in NAMES - {"all"} or dst not in NAMES or not text:
            return self._send(400, {"error": "from: mac1-4, to: mac1-4 or all, text not empty"})
        with lock:
            entry = {"id": len(messages) + 1, "time": time.strftime("%H:%M:%S"), "from": src, "to": dst, "text": text}
            messages.append(entry)
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry) + "\n")
        print(f"#{entry['id']} {entry['time']} {src} -> {dst}: {text}", flush=True)
        self._send(200, {"id": entry["id"]})

    def do_GET(self):
        url = urlparse(self.path)
        q = parse_qs(url.query)
        with lock:
            snapshot = list(messages)
        if url.path == "/read":
            me = q.get("me", [""])[0].lower()
            since = int(q.get("since", ["0"])[0] or 0)
            out = [m for m in snapshot if m["id"] > since and (m["to"] in (me, "all") or m["from"] == me)]
            return self._send(200, out)
        if url.path == "/board":
            lines = [f"#{m['id']} {m['time']} {m['from']} -> {m['to']}: {m['text']}" for m in snapshot]
            return self._send(200, "\n".join(lines) + "\n", "text/plain")
        self._send(404, {"error": "use /read, /board or POST /send"})

    def log_message(self, *args):  # keep the terminal for messages only
        pass


if __name__ == "__main__":
    print(f"coordination board on :{PORT} ({len(messages)} earlier messages)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
