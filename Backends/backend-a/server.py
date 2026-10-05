# Backend A — Mac C (Arina), 10.7.13.142
# Run: python3 server.py
# Listens on 0.0.0.0:3001 (LAN-reachable, not just localhost)

from http.server import BaseHTTPRequestHandler, HTTPServer
import json


class Handler(BaseHTTPRequestHandler):
    def sendJson(self, data):
        body = json.dumps(data).encode()

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend", "A")
        self.send_header("Cache-Control", "max-age=60")
        self.end_headers()

        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/" or self.path == "/api/status":
            self.sendJson({
                "backend": "A",
                "status": "ok"
            })
        else:
            self.send_error(404)


server = HTTPServer(("0.0.0.0", 3001), Handler)

print("Backend A running on port 3001")
server.serve_forever()
