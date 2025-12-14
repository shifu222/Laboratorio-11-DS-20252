# healthcheck.py
import os, sys, urllib.request, urllib.error, socket
socket.setdefaulttimeout(2)
port = os.environ.get("PORT", "8000")
url = f"http://127.0.0.1:{port}/health"
try:
    with urllib.request.urlopen(url, timeout=2) as r:
        sys.exit(0 if r.getcode() == 200 else 1)
except Exception:
    sys.exit(1)
