#!/usr/bin/env python3
"""
Dynamic registry server.

Serves index.json with download_url values derived from the incoming request's
Host header — no BASE_URL needed.

GET /index.json  → catalog of all apps with absolute download URLs
GET /*.tpapp     → serve the package file
"""

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS_DIR = os.path.join(ROOT, "apps")
TPAPP_DIR = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", 9090))


def build_index(base_url: str) -> list:
    base_url = base_url.rstrip("/")
    entries = []
    for name in sorted(os.listdir(APPS_DIR)):
        manifest_path = os.path.join(APPS_DIR, name, "manifest.yaml")
        if not os.path.exists(manifest_path):
            continue
        with open(manifest_path) as f:
            manifest = yaml.safe_load(f)
        tpapp = os.path.join(TPAPP_DIR, f"{name}.tpapp")
        if not os.path.exists(tpapp):
            continue
        manifest["download_url"] = f"{base_url}/{name}.tpapp"
        entries.append(manifest)
    return entries


class RegistryHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/index.json":
            host = self.headers.get("Host", f"localhost:{PORT}")
            scheme = "http"
            base_url = f"{scheme}://{host}"
            entries = build_index(base_url)
            body = json.dumps(entries, indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path.endswith(".tpapp"):
            filename = os.path.basename(path)
            filepath = os.path.join(TPAPP_DIR, filename)
            if os.path.exists(filepath):
                with open(filepath, "rb") as f:
                    body = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

        self.send_response(404)
        self.end_headers()


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), RegistryHandler)
    print(f"Registry server listening on port {PORT}")
    server.serve_forever()
