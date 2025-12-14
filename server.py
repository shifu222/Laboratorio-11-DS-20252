import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "8000"))
NAME = os.environ.get("SERVICE_NAME", "service")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200); self.end_headers()
            self.wfile.write(b"OK")
            return
        self.send_response(200); self.end_headers()
        self.wfile.write(f"Hola desde {NAME} on {PORT}\n".encode())

    def log_message(self, fmt, *args):
        # reduce ruido en logs
        pass

if __name__ == "__main__":
    HTTPServer(("", PORT), Handler).serve_forever()
