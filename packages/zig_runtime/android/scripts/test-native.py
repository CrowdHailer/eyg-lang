#!/usr/bin/env python3
"""Exercise the actual Zig C ABI from ctypes, not a simulated interpreter."""
import argparse
import ctypes
import json
import random
import subprocess
import sys
import tempfile
import base64
import hashlib
import os
import http.server
import threading
import zlib
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument('library')
    p.add_argument('--cases', type=int, default=1000)
    p.add_argument('--oracle', action='store_true', help='Compare generated programs through this ABI with the pinned Gleam oracle')
    p.add_argument('--bun', default='bun')
    args = p.parse_args()
    lib = ctypes.CDLL(args.library)
    lib.eyg_android_create.restype = ctypes.c_void_p
    lib.eyg_android_result_len.argtypes = [ctypes.c_void_p]
    lib.eyg_android_result_len.restype = ctypes.c_size_t
    lib.eyg_android_destroy.argtypes = [ctypes.c_void_p]
    for name in ['eyg_android_evaluate', 'eyg_android_resume']:
        method = getattr(lib, name)
        method.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
        method.restype = ctypes.c_void_p
    session = lib.eyg_android_create()
    assert session
    def call(method, value):
        if method == 'eyg_android_evaluate':
            value = {**value, 'packages': value.get('packages', {})}
        raw = json.dumps(value).encode()
        ptr = getattr(lib, method)(session, raw, len(raw))
        return json.loads(ctypes.string_at(ptr, lib.eyg_android_result_len(session)))
    rng = random.Random(0x455947)
    oracle = None
    try:
        for i in range(args.cases):
            left, right = rng.randrange(-100000, 100000), rng.randrange(-100000, 100000)
            source = f'let reply = perform Expo({left}) !int_add(reply, {right})'
            response = call('eyg_android_evaluate', {'source': source})
            assert response == {'status': 'effect', 'effect': {'label': 'Expo', 'value': {'integer': left}}}, response
            response = call('eyg_android_resume', {'integer': left})
            assert response == {'status': 'done', 'result': {'value': {'integer': left + right}}}, response
        response = call('eyg_android_resume', {'integer': 0})
        assert response['status'] == 'error' and response['error'] == 'NoPendingEffect', response
        response = call('eyg_android_evaluate', {'source': 'perform Expo({})'})
        assert response['status'] == 'effect'
        response = call('eyg_android_resume', {'integer': 'bad'})
        assert response['status'] == 'error' and response['error'] == 'InvalidReply', response
        response = call('eyg_android_resume', {'record': {}})
        assert response['status'] == 'done', response
        response = call('eyg_android_evaluate', {'source': 'perform Expo({})'})
        assert response['status'] == 'effect'
        response = call('eyg_android_resume', {'binary': {'/': {'bytes': 'AQD/'}}})
        assert response == {'status': 'done', 'result': {'value': {'binary': {'/': {'bytes': 'AQD/'}}}}}, response
        for integer in [1e20, -1e20, 1e100, -1e100]:
            response = call('eyg_android_evaluate', {'source': 'perform Expo({})'})
            assert response['status'] == 'effect', response
            response = call('eyg_android_resume', {'integer': integer})
            assert response == {'status': 'done', 'result': {'value': {'integer': integer}}}, response
        for alias in ['AQ', 'AQ==', 'AR', 'AR==', 'A Q\n']:
            response = call('eyg_android_evaluate', {'source': 'perform Expo({})'})
            assert response['status'] == 'effect', response
            response = call('eyg_android_resume', {'binary': {'/': {'bytes': alias}}})
            assert response == {'status': 'done', 'result': {'value': {'binary': {'/': {'bytes': 'AQ'}}}}}, response
        for source, reason in [
            ('perform EYGParse(1)', {'IncorrectTerm': {'expected': 'String', 'got': {'integer': 1}}}),
            ('perform DecodeJSON("42")', {'IncorrectTerm': {'expected': 'Binary', 'got': {'string': '42'}}}),
            ('perform Hash({algorithm: SHA256({}), bytes: 1})', {'IncorrectTerm': {'expected': 'Binary', 'got': {'integer': 1}}}),
            ('perform Sign({})', {'MissingField': 'key'}),
        ]:
            response = call('eyg_android_evaluate', {'source': source})
            assert response == {'status': 'done', 'result': {'break': reason}}, response
        work = Path(__file__).resolve().parents[1] / 'work'
        work.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='native host-', dir=work) as temporary:
            directory = Path(temporary)
            (directory / 'add.eyg').write_text('(n) -> { !int_add(n, 1) }')
            response = call('eyg_android_evaluate', {'directory': str(directory), 'source': 'let add = import "add.eyg" add(41)'})
            assert response == {'status': 'done', 'result': {'value': {'integer': 42}}}, response
            (directory / 'json.eyg').write_text('{"0":"i","v":42}')
            response = call('eyg_android_evaluate', {'directory': str(directory), 'source': 'import "json.eyg"'})
            assert response == {'status': 'done', 'result': {'value': {'integer': 42}}}, response
            (directory / 'a.eyg').write_text('let run = import "b.eyg" let call = (seed) -> { !int_add(run(seed), 1) } call')
            (directory / 'b.eyg').write_text('(seed) -> { let n = perform Expo(seed) !int_add(n, perform Expo(1)) }')
            response = call('eyg_android_evaluate', {'directory': directory.as_uri(), 'source': 'let run = import "a.eyg" !int_add(run(40), 1)'})
            assert response['status'] == 'effect' and response['effect']['value'] == {'integer': 40}, response
            response = call('eyg_android_resume', {'integer': 40})
            assert response['status'] == 'effect' and response['effect']['value'] == {'integer': 1}, response
            response = call('eyg_android_resume', {'integer': 1})
            assert response == {'status': 'done', 'result': {'value': {'integer': 43}}}, response
            (directory / 'impure.eyg').write_text('perform StandardIn({})')
            response = call('eyg_android_evaluate', {'directory': str(directory), 'source': 'import "impure.eyg"'})
            assert response == {'status': 'done', 'result': {'break': {'UnhandledEffect': {'label': 'StandardIn', 'value': {'record': {}}}}}}, response
            (directory / 'cycle.eyg').write_text('import "cycle.eyg"')
            response = call('eyg_android_evaluate', {'directory': str(directory), 'source': 'import "cycle.eyg"'})
            assert response == {'status': 'error', 'error': 'CyclicImport'}, response
            repo = directory / 'repo'
            subprocess.run(['git', 'init', '-q', '-b', 'main', str(repo)], check=True)
            for i in range(3):
                (repo / 'file').write_text(str(i))
                subprocess.run(['git', '-C', str(repo), 'add', 'file'], check=True)
                subprocess.run(['git', '-C', str(repo), '-c', 'user.name=EYG test', '-c', 'user.email=test@eyg.invalid', 'commit', '-qm', f'change {i}'], check=True)
            head = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
            source = 'perform GitQuery({action: "head", repo: "repo"})'
            response = call('eyg_android_evaluate', {'directory': str(directory), 'source': source})
            result = response['result']['value']['tagged']
            assert result['label'] == 'Ok' and result['value']['record']['id'] == {'string': head}, response
            (repo / 'history.eyg').write_text('(_) -> { perform GitQuery({action: "history", repo: ".", limit: 3}) }')
            source = 'let history = import "repo/history.eyg" history({})'
            response = call('eyg_android_evaluate', {'directory': str(directory), 'source': source})
            result = response['result']['value']['tagged']
            assert result['label'] == 'Ok', response
            commits = result['value']['list']
            assert [entry['record']['subject']['string'] for entry in commits] == ['change 2', 'change 1', 'change 0'], response
        def app(function, argument):
            return {'0': 'a', 'f': function, 'a': argument}
        def binary(data):
            return {'0': 'x', 'v': {'/': {'bytes': base64.b64encode(data).decode().rstrip('=')}}}
        def record(fields):
            result = {'0': 'u'}
            for name, value in reversed(list(fields.items())):
                result = app(app({'0': 'e', 'l': name}, value), result)
            return result
        for label in ['EYGParse', 'DecodeJSON']:
            lift = {'0': 's', 'v': '42'} if label == 'EYGParse' else binary(b'42')
            response = call('eyg_android_evaluate', {'program': app({'0': 'p', 'l': label}, lift)})
            term = response['result']['value']['tagged']
            assert term['label'] == 'Ok', response
            first = term['value']['list'][0]
            ast_term = first if label == 'EYGParse' else first['record']['term']
            assert ast_term == {'tagged': {'label': 'Integer', 'value': {'integer': 42}}}, response
        response = call('eyg_android_evaluate', {'source': 'perform Hash({algorithm: SHA256({}), bytes: !string_to_binary("abc")})'})
        assert response == {'status': 'done', 'result': {'value': {'binary': {'/': {'bytes': base64.b64encode(hashlib.sha256(b'abc').digest()).decode().rstrip('=')}}}}}, response
        response = call('eyg_android_evaluate', {'program': app({'0': 'p', 'l': 'Inflate'}, binary(zlib.compress(b'EYG')))})
        assert response == {'status': 'done', 'result': {'value': {'tagged': {'label': 'Ok', 'value': {'binary': {'/': {'bytes': 'RVlH'}}}}}}}, response
        response = call('eyg_android_evaluate', {'source': 'perform CreateKey(Eddsa({}))'})
        key = response['result']['value']['tagged']
        assert key['label'] == 'Ok' and key['value']['tagged']['label'] == 'Eddsa', response
        for coordinate in ['x', 'd']:
            assert len(base64.b64decode(key['value']['tagged']['value']['record'][coordinate]['binary']['/']['bytes'] + '===')) == 32, response
        seed = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
        request = record({'key': app({'0': 't', 'l': 'Eddsa'}, record({'d': binary(seed)})), 'data': binary(b'')})
        response = call('eyg_android_evaluate', {'program': app({'0': 'p', 'l': 'Sign'}, request)})
        signature = base64.b64decode(response['result']['value']['tagged']['value']['binary']['/']['bytes'] + '===')
        assert signature.hex() == 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b', response
        class FixtureHandler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_GET(self):
                body = b'android-native'
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), FixtureHandler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        previous_no_proxy = os.environ.get('NO_PROXY')
        previous_lower = os.environ.get('no_proxy')
        os.environ['NO_PROXY'] = os.environ['no_proxy'] = '127.0.0.1'
        try:
            port = server.server_address[1]
            source = f'perform Fetch({{method: GET({{}}), scheme: HTTP({{}}), host: "127.0.0.1", port: Some({port}), path: "/", query: None({{}}), headers: [], body: !string_to_binary("")}})'
            response = call('eyg_android_evaluate', {'source': source})
            result = response['result']['value']['tagged']
            assert result['label'] == 'Ok' and result['value']['record']['status'] == {'integer': 200}, response
            assert base64.b64decode(result['value']['record']['body']['binary']['/']['bytes'] + '===') == b'android-native', response
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=5)
            for name, value in [('NO_PROXY', previous_no_proxy), ('no_proxy', previous_lower)]:
                if value is None: os.environ.pop(name, None)
                else: os.environ[name] = value
        def content_id(program):
            canonical = json.dumps(program, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
            return 'b' + base64.b32encode(bytes([1, 0xa9, 2, 0x12, 0x20]) + hashlib.sha256(canonical).digest()).decode().lower().rstrip('=')
        increment = {'0': 'f', 'l': 'n', 'b': app(app({'0': 'b', 'l': 'int_add'}, {'0': 'v', 'l': 'n'}), {'0': 'i', 'v': 1})}
        increment_cid = content_id(increment)
        fixtures = {'demo': {'version': 3, 'program': increment, 'cid': increment_cid}}
        for reference in [
            {'0': '@', 'p': 'demo'}, {'0': '@', 'p': 'demo', 'r': 3},
            {'0': '@', 'p': 'demo', 'r': 3, 'l': {'/': increment_cid}},
            {'0': '#', 'l': {'/': increment_cid}},
        ]:
            response = call('eyg_android_evaluate', {'packages': fixtures, 'program': app(reference, {'0': 'i', 'v': 41})})
            assert response == {'status': 'done', 'result': {'value': {'integer': 42}}}, response
        dependent = app({'0': '#', 'l': {'/': increment_cid}}, {'0': 'i', 'v': 41})
        response = call('eyg_android_evaluate', {'packages': {**fixtures, 'dependent': {'version': 1, 'program': dependent}}, 'source': '@dependent'})
        assert response == {'status': 'done', 'result': {'value': {'integer': 42}}}, response
        phone_function = {'0': 'f', 'l': 'n', 'b': app({'0': 'p', 'l': 'Expo'}, {'0': 'v', 'l': 'n'})}
        response = call('eyg_android_evaluate', {'packages': {'phone': {'version': 1, 'program': phone_function}}, 'source': '@phone(42)'})
        assert response == {'status': 'effect', 'effect': {'label': 'Expo', 'value': {'integer': 42}}}, response
        response = call('eyg_android_resume', {'integer': 42})
        assert response == {'status': 'done', 'result': {'value': {'integer': 42}}}, response
        impure_module = app({'0': 'p', 'l': 'Expo'}, {'0': 'i', 'v': 1})
        response = call('eyg_android_evaluate', {'packages': {'impure': {'version': 1, 'program': impure_module}}, 'source': '@impure'})
        assert response == {'status': 'done', 'result': {'break': {'UnhandledEffect': {'label': 'Expo', 'value': {'integer': 1}}}}}, response
        response = call('eyg_android_evaluate', {'packages': {'unpinned': {'version': 1, 'program': {'0': '@', 'p': 'demo'}}, **fixtures}, 'source': '@unpinned'})
        assert response == {'status': 'done', 'result': {'break': {'UndefinedReference': {'0': '@', 'p': 'demo'}}}}, response
        response = call('eyg_android_evaluate', {'packages': {'wrong': {'version': 1, 'program': {'0': 'i', 'v': 0}, 'cid': increment_cid}}, 'source': '@wrong'})
        assert response == {'status': 'error', 'error': 'ModuleHashMismatch'}, response
        if args.oracle:
            package = Path(__file__).resolve().parents[2]
            sys.path.insert(0, str(package / 'tests'))
            from differential import generated_program, node, call as apply, builtin
            oracle = subprocess.Popen([args.bun, str(package / 'tests/oracle.mjs')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            def oracle_eval(request):
                oracle.stdin.write(json.dumps(request) + '\n')
                oracle.stdin.flush()
                return json.loads(oracle.stdout.readline())
            for i in range(args.cases):
                program = generated_program(rng, depth=3)
                expected = oracle_eval({'op': 'eval', 'program': program})
                actual = call('eyg_android_evaluate', {'program': program})
                if actual['status'] == 'effect':
                    assert expected == {'break': {'UnhandledEffect': {'label': actual['effect']['label'], 'value': actual['effect']['value']}}}, (program, expected, actual)
                    # Finish the paused bridge so its arena can be reused.
                    call('eyg_android_resume', {'record': {}})
                    # Some programs perform repeatedly. Discard the session safely.
                    lib.eyg_android_destroy(session)
                    session = lib.eyg_android_create()
                else:
                    assert actual.get('result') == expected, (program, expected, actual)
            for i in range(args.cases):
                left, right = rng.randrange(-100000, 100000), rng.randrange(-100000, 100000)
                lift = node('i', v=left)
                effect = apply(node('p', l='Expo'), lift)
                program = node('l', l='reply', v=effect, t=builtin('int_add', node('v', l='reply'), node('i', v=right)))
                expected = oracle_eval({'op': 'eval', 'program': program, 'effects': [{'label': 'Expo', 'lift': {'integer': left}, 'reply': {'integer': left}}]})
                actual = call('eyg_android_evaluate', {'program': program})
                assert actual['status'] == 'effect', actual
                actual = call('eyg_android_resume', {'integer': left})
                assert actual.get('result') == expected, (program, expected, actual)
    finally:
        lib.eyg_android_destroy(session)
        if oracle:
            oracle.stdin.close()
            oracle.wait(timeout=5)
    print(json.dumps({'cases': args.cases, 'seed': '0x455947', 'native_effect_resume': 'passed', 'invalid_reply': 'passed', 'relative_imports': 'passed', 'nested_pure_import_phone_closures': 'passed', 'relative_impure_initialization': 'rejected', 'native_git_head_history': 'passed', 'native_fetch_loopback': 'passed', 'native_parse_decode_hash_inflate_create_sign': 'passed', 'hub_references_latest_version_pinned_cid': 'passed', 'hub_pure_initialization_and_phone_closures': 'passed', 'hub_hash_mismatch': 'rejected', 'oracle_programs': args.cases * 2 if args.oracle else 0}))

if __name__ == '__main__':
    main()
