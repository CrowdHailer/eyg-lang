#!/usr/bin/env python3
"""A real blocked native Fetch must not reach a later Git mutation after cancel."""
import argparse
import concurrent.futures
import ctypes
import http.server
import json
import os
from pathlib import Path
import tempfile
import threading
import time

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('library')
    args = parser.parse_args()
    lib = ctypes.CDLL(args.library)
    lib.eyg_android_create.restype = ctypes.c_void_p
    lib.eyg_android_evaluate.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    lib.eyg_android_evaluate.restype = ctypes.c_void_p
    lib.eyg_android_result_len.argtypes = [ctypes.c_void_p]
    lib.eyg_android_result_len.restype = ctypes.c_size_t
    lib.eyg_android_cancel.argtypes = [ctypes.c_void_p]
    lib.eyg_android_cancel.restype = None
    lib.eyg_android_destroy.argtypes = [ctypes.c_void_p]
    entered, release = threading.Event(), threading.Event()
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_GET(self):
            entered.set()
            if not release.wait(10):
                self.send_error(504)
                return
            self.send_response(200)
            self.send_header('Content-Length', '5')
            self.end_headers()
            self.wfile.write(b'ready')
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    previous = {key: os.environ.get(key) for key in ['NO_PROXY', 'no_proxy']}
    os.environ['NO_PROXY'] = os.environ['no_proxy'] = '127.0.0.1'
    session = lib.eyg_android_create()
    assert session
    work = Path(__file__).resolve().parents[1] / 'work'
    work.mkdir(exist_ok=True)
    def evaluate(directory, repo):
        port = server.server_address[1]
        code = f'let _ = perform Fetch({{method: GET({{}}), scheme: HTTP({{}}), host: "127.0.0.1", port: Some({port}), path: "/", query: None({{}}), headers: [], body: !string_to_binary("")}}) perform GitQuery({{action: "init", repo: "{repo}"}})'
        data = json.dumps({'directory': str(directory), 'source': code, 'packages': {}}).encode()
        pointer = lib.eyg_android_evaluate(session, data, len(data))
        return json.loads(ctypes.string_at(pointer, lib.eyg_android_result_len(session)))
    try:
        with tempfile.TemporaryDirectory(prefix='cancel-', dir=work) as temporary:
            directory = Path(temporary)
            # Positive control: the same native Fetch -> GitQuery program
            # really creates a repository when it has not been cancelled.
            release.set()
            result = evaluate(directory, 'positive')
            assert result['status'] == 'done' and (directory / 'positive/.git/HEAD').is_file(), result
            entered.clear()
            release.clear()
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
                future = executor.submit(evaluate, directory, 'after_cancel')
                try:
                    assert entered.wait(5), 'Native Fetch never reached the fixture server'
                    started = time.perf_counter_ns()
                    lib.eyg_android_cancel(session)
                    cancel_ms = (time.perf_counter_ns() - started) / 1_000_000
                    assert not future.done(), 'Cancellation test did not block native IO'
                finally:
                    release.set()
                result = future.result(timeout=10)
            assert result == {'status': 'error', 'error': 'Cancelled'}, result
            assert not (directory / 'after_cancel').exists(), 'Git mutation ran after cancellation'
            assert evaluate(directory, 'still_cancelled') == {'status': 'error', 'error': 'Cancelled'}
            assert not (directory / 'still_cancelled').exists(), 'Cancelled session was reusable'
    finally:
        release.set()
        lib.eyg_android_destroy(session)
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)
        for key, value in previous.items():
            if value is None: os.environ.pop(key, None)
            else: os.environ[key] = value
    print(json.dumps({'actualNativeIo': 'passed', 'positiveGitMutationControl': 'passed', 'noGitMutationAfterCancel': 'passed', 'stickyCancellation': 'passed', 'cancelCallMs': cancel_ms}))

if __name__ == '__main__':
    main()
