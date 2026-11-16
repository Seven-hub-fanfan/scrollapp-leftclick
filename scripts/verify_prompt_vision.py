"""Run offline protocol integration checks against a loopback fixture server."""
import base64
import http.server
import json
import subprocess
import sys
import threading
import time

RESULT = {"prompt_cn": "测试图片，柔和光线",
          "prompt_en": "A reference image with soft lighting",
          "negative_prompt": "blur", "tags": ["soft", "studio"]}
TEXT = json.dumps(RESULT, ensure_ascii=False, separators=(",", ":"))
KEY = "unit-key-DO-NOT-EXPOSE"
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.send_response(200)
        if self.path == "/webpage":
            self.send_header("Content-Type", "text/html")
            payload = b"<html>Not an image</html>"
        else:
            self.send_header("Content-Type", "image/png")
            payload = PNG
        self.send_header("Content-Length", str(33 * 1024 * 1024 if self.path == "/too-large" else len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        gemini = ":streamGenerateContent" in self.path
        anthropic = self.path.endswith("/messages")
        if gemini:
            assert self.headers["x-goog-api-key"] == KEY
            assert body["contents"][0]["parts"][1]["inlineData"]["mimeType"] == "image/jpeg"
        elif anthropic:
            assert self.headers["x-api-key"] == KEY
            assert self.headers["anthropic-version"] == "2023-06-01"
            assert body["messages"][0]["content"][0]["source"]["media_type"] == "image/jpeg"
        else:
            assert self.headers["Authorization"] == "Bearer " + KEY
            assert body["messages"][1]["content"][1]["image_url"]["url"].startswith("data:image/jpeg;base64,")
        model = body.get("model", "vision-test")
        if model in ["error", "nonstream"]:
            payload = (json.dumps({"error": {"message": "Invalid API key " + KEY}}).encode()
                       if model == "error" else
                       json.dumps({"choices": [{"message": {"content": TEXT}}]}, ensure_ascii=False).encode())
            self.send_response(401 if model == "error" else 200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            for index in range(0, len(TEXT), 13):
                part = TEXT[index:index + 13]
                if gemini:
                    event = {"candidates": [{"content": {"parts": [{"text": part}]}}]}
                elif anthropic:
                    event = {"type": "content_block_delta", "delta": {"type": "text_delta", "text": part}}
                else:
                    event = {"choices": [{"delta": {"content": part}}]}
                self.wfile.write(("data: " + json.dumps(event, ensure_ascii=False) + "\n\n").encode())
                self.wfile.flush()
                if model == "slow":
                    time.sleep(0.2)
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        sys.exit(subprocess.call([sys.argv[1], f"http://127.0.0.1:{server.server_port}"]))
    finally:
        server.shutdown()
