"""Synthetic HTTP transport proof, never a model-quality evaluation."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

class WorkerTransportTests(unittest.TestCase):
    def run_worker(self, job_id):
        key = 'synthetic-transport-key-' + 'x' * 32
        worker_id = '77777777-7777-4777-8777-777777777777'
        digest = 'a' * 64
        packet = {'prompt_version': 'senior-review-v9', 'files': {'solution.rb': '# synthetic transport fixture, not real feedback'}}
        report = {'summary': 'Synthetic transport fixture; no model judgment.'}
        seen = []
        test = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_GET(self):
                self.reply({'models': [{'name': 'transport-fixture:latest', 'digest': digest}]})
            def do_POST(self):
                data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                seen.append((self.path, data))
                if self.path == '/api/chat':
                    test.assertEqual({**packet, 'files': {'solution.rb': '1| # synthetic transport fixture, not real feedback'}}, json.loads(data['messages'][1]['content']))
                    test.assertFalse(data['stream'])
                    self.reply({'done': True, 'done_reason': 'stop', 'message': {'content': json.dumps(report)}})
                    return
                test.assertEqual('Bearer ' + key, self.headers.get('Authorization'))
                if self.path == '/internal/reviews/lease':
                    self.reply({'job': {'id': job_id, 'revision': 'frozen-revision',
                               'prompt_version': 'senior-review-v9', 'input': packet}, 'lease_token': 'fixture-lease'})
                else: self.reply({'ok': True})
            def reply(self, body):
                data = json.dumps(body).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        app, model = [ThreadingHTTPServer(('127.0.0.1', 0), Handler) for _ in range(2)]
        threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in (app, model)]
        for thread in threads: thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for name in ('worker.py', 'provider.py', 'prompt.txt', 'report.schema.json'):
                    shutil.copy(Path(__file__).resolve().parents[1] / name, root / name)
                result = subprocess.run(['python3', str(root / 'worker.py'), '--once', '--worker-id', worker_id,
                            '--model', 'transport-fixture:latest', '--url', f'http://127.0.0.1:{app.server_port}',
                            '--ollama', f'http://127.0.0.1:{model.server_port}'],
                            env={**os.environ, 'INTERVIEW_REVIEW_BRIDGE_KEY': key}, capture_output=True, text=True, timeout=20)
                self.assertNotIn(key, result.stdout + result.stderr)
                return result, seen, key, report, digest, sorted(path.name for path in (root / '.state').glob('*.json'))
        finally:
            for server in (app, model): server.shutdown(); server.server_close()
            for thread in threads: thread.join(timeout=2)

    def test_local_worker_delivers_a_frozen_packet_and_canonical_model_identity(self):
        result, seen, key, report, digest, state_files = self.run_worker('5b1c2a8e-9d3f-4c6b-8a7e-1f2d3c4b5a69')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual([], state_files)
        heartbeat = next(body for path, body in seen if path.endswith('heartbeat'))
        delivered = next(body for path, body in seen if path.endswith('/result'))
        self.assertEqual('sha256:' + digest, heartbeat['model_digest'])
        self.assertEqual('sha256:' + digest, delivered['model_digest'])
        self.assertEqual('frozen-revision', delivered['revision'])
        self.assertEqual('fixture-lease', delivered['lease_token'])
        self.assertEqual('completed', delivered['status'])
        self.assertEqual(report, delivered['report'])
        self.assertEqual(1, len([path for path, _ in seen if path == '/api/chat']))

    def test_non_canonical_review_id_never_reaches_a_path_or_callback(self):
        result, seen, key, report, digest, state_files = self.run_worker('../../etc/transport-fixture')
        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], state_files)
        self.assertEqual([], [path for path, _ in seen if path == '/api/chat' or path.endswith('/result')])

if __name__ == '__main__': unittest.main()
