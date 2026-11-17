import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
WEBBENCH = os.path.dirname(HERE)
sys.path.insert(0, WEBBENCH)

import server  # noqa: E402


class ServerTestCase(unittest.TestCase):
    def setUp(self):
        self.httpd = server.make_server(0, Path(WEBBENCH) / 'page')
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)

    def url(self, path):
        return 'http://127.0.0.1:%d%s' % (self.port, path)

    def get(self, path):
        with urllib.request.urlopen(self.url(path), timeout=5) as resp:
            return resp.status, resp.read()

    def post_json(self, path, body):
        data = json.dumps(body).encode('utf-8')
        req = urllib.request.Request(
            self.url(path), data=data, method='POST',
            headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status


class ServerTests(ServerTestCase):
    def test_binds_loopback_only(self):
        self.assertEqual(self.httpd.server_address[0], '127.0.0.1')

    def test_result_roundtrip(self):
        body = {'token': 't', 'case': 3, 'field': 'input', 'text': 'xin chào',
                'inputs': [1000.5, 1200.25]}
        self.assertEqual(self.post_json('/result', body), 200)
        status, raw = self.get('/result/t/3')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw.decode('utf-8')), body)

    def test_unknown_case_is_404(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self.get('/result/t/999')
        self.assertEqual(ctx.exception.code, 404)

    def test_serves_page(self):
        status, raw = self.get('/')
        self.assertEqual(status, 200)
        self.assertIn(b'webbench', raw)

    def test_health(self):
        status, raw = self.get('/health')
        self.assertEqual(status, 200)
        self.assertEqual(raw, b'ok')


if __name__ == '__main__':
    unittest.main()
