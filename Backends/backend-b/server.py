# Backend B — Mac D (Hemanth), 10.7.20.219
# Run: python3 server.py
# Listens on 0.0.0.0:3002 (LAN-reachable, not just localhost)

from http.server import BaseHTTPRequestHandler, HTTPServer
import json


class Handler(BaseHTTPRequestHandler):
    def sendJson(self, data):
        body = json.dumps(data).encode()

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend", "B")
        self.send_header("Cache-Control", "max-age=60")
        self.end_headers()

        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/" or self.path == "/api/status":
            self.sendJson({
                "backend": "B",
                "status": "ok"
            })
        else:
            self.send_error(404)


server = HTTPServer(("0.0.0.0", 3002), Handler)

print("Backend B running on port 3002")
server.serve_forever()
