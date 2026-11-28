"""Localhost page and result server for webbench.

Serves the bench page from page/, stores the JSON each page run POSTs under
(token, case), and returns it on GET /result/<token>/<case>. Binds 127.0.0.1 only.
"""
import argparse
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

HERE = Path(__file__).resolve().parent
PAGE_DIR = HERE / 'page'
MAX_BODY = 1 << 20

CONTENT_TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
}


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, root):
        self.root = Path(root).resolve()
        self.results = {}
        self.lock = threading.Lock()
        super().__init__(address, handler)


class _Handler(BaseHTTPRequestHandler):
    server_version = 'webbench'

    def log_message(self, fmt, *args):
        pass

    def _reply(self, status, body, content_type):
        if isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def _not_found(self):
        self._reply(404, 'not found', 'text/plain; charset=utf-8')

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/health':
            self._reply(200, 'ok', 'text/plain; charset=utf-8')
            return
        if path.startswith('/result/'):
            parts = path.split('/')
            if len(parts) != 4 or not parts[2] or not parts[3]:
                self._not_found()
                return
            key = (unquote(parts[2]), unquote(parts[3]))
            with self.server.lock:
                stored = self.server.results.get(key)
            if stored is None:
                self._not_found()
                return
            self._reply(200, json.dumps(stored), 'application/json; charset=utf-8')
            return
        name = 'index.html' if path == '/' else unquote(path.lstrip('/'))
        target = (self.server.root / name).resolve()
        if target.parent != self.server.root or not target.is_file():
            self._not_found()
            return
        content_type = CONTENT_TYPES.get(target.suffix, 'application/octet-stream')
        self._reply(200, target.read_bytes(), content_type)

    def do_POST(self):
        if urlsplit(self.path).path != '/result':
            self._not_found()
            return
        try:
            length = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            length = -1
        if length <= 0 or length > MAX_BODY:
            self._reply(400, 'bad length', 'text/plain; charset=utf-8')
            return
        try:
            body = json.loads(self.rfile.read(length).decode('utf-8'))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._reply(400, 'bad json', 'text/plain; charset=utf-8')
            return
        if not isinstance(body, dict) or 'token' not in body or 'case' not in body:
            self._reply(400, 'missing token or case', 'text/plain; charset=utf-8')
            return
        key = (str(body['token']), str(body['case']))
        with self.server.lock:
            self.server.results[key] = body
        self._reply(200, 'ok', 'text/plain; charset=utf-8')


def make_server(port, root):
    """Return a ThreadingHTTPServer bound to 127.0.0.1 that serves `root`."""
    return _Server(('127.0.0.1', port), _Handler, root)


def main(argv=None):
    parser = argparse.ArgumentParser(description='webbench page and result server')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args(argv)
    httpd = make_server(args.port, PAGE_DIR)
    print('webbench serving http://127.0.0.1:%d/' % httpd.server_address[1], flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
