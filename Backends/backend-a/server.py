from http.server import BaseHTTPRequestHandler, HTTPServer
import hashlib
import json

BACKEND = "A"
PORT = 3001


class Handler(BaseHTTPRequestHandler):

    def route(self):
        if self.path == "/":
            return 200, {"backend": BACKEND, "status": "running"}
        if self.path == "/api/status":
            return 200, {"backend": BACKEND, "status": "ok"}
        return 404, {"error": "Not Found"}

    def respond(self, include_body):
        status, data = self.route()
        body = json.dumps(data).encode()

        # ETag = fingerprint of the response body, used for conditional requests
        etag = '"' + hashlib.sha1(body).hexdigest()[:16] + '"'

        # Client already has this exact version -> 304 Not Modified, no body
        if status == 200 and self.headers.get("If-None-Match") == etag:
            self.send_response(304)
            self.send_header("ETag", etag)
            self.send_header("X-Backend", BACKEND)
            self.send_header("Cache-Control", "max-age=60")
            self.end_headers()
            return

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend", BACKEND)
        self.send_header("Cache-Control", "max-age=60")
        if status == 200:
            self.send_header("ETag", etag)
        self.end_headers()

        if include_body:
            self.wfile.write(body)

    def do_GET(self):
        self.respond(include_body=True)

    # Needed for `curl -I` (HEAD request); without it Python returns 501
    def do_HEAD(self):
        self.respond(include_body=False)

    def log_message(self, format, *args):
        print(format % args)


server = HTTPServer(("0.0.0.0", PORT), Handler)

print(f"Backend {BACKEND} running on port {PORT}")

server.serve_forever()
