#!/usr/bin/env python3
"""Compare located source trees and captured contexts with actual loam.source."""
import argparse
import hashlib
import json
import os
import random
import shutil
import sys
from pathlib import Path

from differential import PACKAGE, ORACLE_SHA, Peer, first_difference, same, node, call


def syntax(rng, depth=3):
    if depth == 0:
        return rng.choice((str(rng.randrange(-100, 100)), '{}', '[]', 'todo',
                           json.dumps(rng.choice(('hello', '界', 'é', 'a\nb', '"\\')), ensure_ascii=False)))
    child = lambda: syntax(rng, depth - 1)
    choice = rng.randrange(13)
    if choice == 0:
        return f'let x = {child()} x'
    if choice == 1:
        return f'(x, y) -> {{ {child()} }}'
    if choice == 2:
        return f'!int_add({child()},   {child()})'
    if choice == 3:
        return f'{{foo: {child()}, bar: {child()}}}'
    if choice == 4:
        return f'[{child()}, {child()},]'
    if choice == 5:
        return f'Some({child()})'
    if choice == 6:
        return f'match Some({child()}) {{ Some(x) -> {{ x }} | (_) -> {{ {child()} }} }}'
    if choice == 7:
        return f'perform StandardOut({child()})'
    if choice == 8:
        return f'(x) -> {{ x }}({child()})'
    if choice == 9:
        return f'{{foo: {child()}}}.foo'
    if choice == 10:
        return f'let {{foo, bar: other}} = {child()} [foo,other]'
    if choice == 11:
        return f'[1, {child()}, ..tail]'
    return f'{{foo:{child()}, ..tail}}'


def context(rng, depth=4):
    body = 'perform Ping(42)'
    for index in range(rng.randrange(1, depth + 1)):
        choice = rng.randrange(7)
        if choice == 0:
            body = f'let result{index} = {body} {{result: result{index}, pending: [1,2,3]}}'
        elif choice == 1:
            body = f'let callable{index} = (local{index}) -> {{ {body} }} callable{index}({rng.randrange(100)})'
        elif choice == 2:
            body = f'!int_add({body}, {rng.randrange(100)})'
        elif choice == 3:
            body = f'{body}(0)'
        elif choice == 4:
            body = f'handle Other((value, resume) -> {{ resume }}, (_) -> {{ {body} }})'
        elif choice == 5:
            body = f'let captured{index} = (x) -> {{ {{x:x, content:"界"}} }} {body}'
        else:
            body = f'let {{a,b:c}} = {{a:1,b:2}} {body}'
    return f'handle Ping((value, resume) -> {{ resume }}, (_) -> {{ {body} }})'


def directed():
    yield 'empty-record', '{}'
    yield 'empty-list', '[]'
    yield 'trailing-comma-list', '[1,2,]'
    yield 'nested-spread-list', '[[1, ..xs], [2, ..ys]]'
    yield 'nested-spread-record', '{a:{b:2, ..r}, ..s}'
    yield 'record-shorthand', '{a,b,c}'
    yield 'record-trailing-comma', '{a:1,b:2,}'
    yield 'empty-pattern', 'let {} = {} 1'
    yield 'pattern-colons', '({a, b : c},d) -> { let {x:y,z} = d [a,c,y,z] }'
    yield 'match-cases', 'match Some(1) { Some(x) -> { x } Other(y) -> { y } }'
    yield 'open-match', 'match { Some(x) -> {x} | (_) -> {0} }'
    yield 'call-spaces', '!int_add(1,      2)'
    yield 'string-offsets', 'let x = "\\n界👩🏽‍💻\\\"" {x:x}.x'
    yield 'source-comments', '// leading comment\nlet x=42\r\n// comment\r\nx'
    yield 'shebang', '#!/usr/bin/env eyg\nlet x=42 x'
    yield 'disk-json', json.dumps(node('f', l='x', b=node('v', l='x')))
    yield 'import-reference', 'import "./quoted\\\".eyg"'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--binary', type=Path, default=PACKAGE / 'work/source-runner')
    p.add_argument('--bun', default=os.environ.get('BUN') or shutil.which('bun') or '/workspace/tooling/bin/bun')
    p.add_argument('--programs', type=int, default=1000)
    p.add_argument('--contexts', type=int, default=300)
    p.add_argument('--seed', type=int, default=20261028)
    p.add_argument('--report', type=Path, default=PACKAGE / 'reports/source-metadata.json')
    args = p.parse_args()
    native = Peer([str(args.binary.resolve())])
    oracle = Peer([args.bun, str(PACKAGE / 'tests/oracle.mjs')])
    report = {'oracle': ORACLE_SHA, 'binary_sha256': hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              'seed': args.seed, 'checked': 0, 'parsed_trees': 0, 'captured_contexts': 0,
              'failed': 0, 'failures': [], 'passed': False}
    rng = random.Random(args.seed)

    def check(name, request):
        expected, got = oracle.request(request), native.request(request)
        report['checked'] += 1
        if request['op'] == 'source_parse' and 'program' in expected:
            report['parsed_trees'] += 1
        if request['op'] == 'pretty_source' and expected.get('text', '').startswith('Partial('):
            report['captured_contexts'] += 1
        if not same(expected, got):
            report['failed'] += 1
            difference = first_difference(expected, got)
            if len(report['failures']) < 20:
                report['failures'].append({'name': name, 'request': request, 'difference': difference,
                                           'expected': expected, 'got': got})
            if report['failed'] <= 5:
                print(json.dumps({'name': name, 'difference': difference}, ensure_ascii=False)[:1000], file=sys.stderr)

    try:
        for name, text in directed():
            check(name, {'op': 'source_parse', 'source': text})
        for i in range(args.programs):
            check(f'tree-{i}', {'op': 'source_parse', 'source': syntax(rng, rng.randrange(1, 5))})
        for i in range(args.contexts):
            text = context(rng, depth=rng.randrange(1, 7))
            if i % 5 == 0:
                text = '#!/usr/bin/env eyg\n' + text
            check(f'context-{i}', {'op': 'pretty_source', 'source': text,
                                  'path': rng.choice(('/module.eyg', '/quoted"界.eyg', '/tmp/line\nbreak.eyg')),
                                  'origin': rng.choice(('disk', 'disk', 'inline', 'pipe', 'repl')),
                                  'width': rng.choice((1, 2, 8, 20, 40, 80, 120))})
        # JSON file annotations use Json throughout the same continuation tree.
        ping = call(node('p', l='Ping'), node('i', v=42))
        handler = node('f', l='value', b=node('f', l='resume', b=node('v', l='resume')))
        program = call(node('h', l='Ping'), handler, node('f', l='_', b=ping))
        check('json-context', {'op': 'pretty_source', 'source': json.dumps(program), 'path': '/module.eyg.json'})
        report['passed'] = report['failed'] == 0 and report['parsed_trees'] >= args.programs and report['captured_contexts'] == args.contexts + 1
    finally:
        native.close()
        oracle.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k:v for k,v in report.items() if k != 'failures'}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
