"""Serves Design/Animations on localhost and saves the loader designer's choices.

    python3 Design/Animations/serve.py [port]

Open http://127.0.0.1:8765/leaf-loaders-preview.html. Every change in the step designer is written to
Design/Animations/leaf-loaders.json, which the app's loaders are built from.
"""
import http.server
import json
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SAVE = os.path.join(ROOT, "leaf-loaders.json")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_POST(self):
        if self.path != "/save":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            data = json.loads(self.rfile.read(min(length, 1_000_000)))
        except ValueError:
            self.send_error(400, "not JSON")
            return
        with open(SAVE, "w", encoding="utf-8") as file:
            json.dump(data, file, ensure_ascii=False, indent=2)
            file.write("\n")
        self.send_response(204)
        self.end_headers()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"http://127.0.0.1:{port}/leaf-loaders-preview.html", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
