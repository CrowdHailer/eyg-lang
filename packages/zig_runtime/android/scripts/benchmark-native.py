#!/usr/bin/env python3
"""Benchmark the C ABI on the current host; this is not a device latency claim."""
import argparse
import ctypes
import json
import statistics
import time
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument('library')
    p.add_argument('--iterations', type=int, default=10000)
    p.add_argument('--output', type=Path)
    p.add_argument('--budget-ms', type=float, default=10)
    p.add_argument('--pure', action='store_true', help='Also measure isolated synchronous callback creation/evaluation/destruction')
    args = p.parse_args()
    lib = ctypes.CDLL(args.library)
    lib.eyg_android_create.restype = ctypes.c_void_p
    lib.eyg_android_destroy.argtypes = [ctypes.c_void_p]
    lib.eyg_android_result_len.argtypes = [ctypes.c_void_p]
    lib.eyg_android_result_len.restype = ctypes.c_size_t
    for name in ['eyg_android_evaluate', 'eyg_android_resume'] + (['eyg_android_pure'] if args.pure else []):
        fn = getattr(lib, name)
        fn.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
        fn.restype = ctypes.c_void_p
    session = lib.eyg_android_create()
    program = json.dumps({'source': '!int_add(20, 22)'}).encode()
    effect = json.dumps({'source': 'let n = perform Expo(20) !int_add(n, 22)'}).encode()
    reply = json.dumps({'integer': 20}).encode()
    pure_request = json.dumps({'source': '(args) -> { !int_add(args, 22) }', 'argument': {'integer': 20}, 'max_steps': 100}).encode()
    def call(fn, data):
        started = time.perf_counter_ns()
        result = fn(session, data, len(data))
        assert result
        return (time.perf_counter_ns() - started) / 1_000_000
    def pure_call(verify=False):
        started = time.perf_counter_ns()
        isolated = lib.eyg_android_create()
        assert isolated
        try:
            result = lib.eyg_android_pure(isolated, pure_request, len(pure_request))
            assert result
            if verify:
                response = json.loads(ctypes.string_at(result, lib.eyg_android_result_len(isolated)))
                assert response['status'] == 'done' and response['result'] == {'value': {'integer': 42}}
        finally:
            lib.eyg_android_destroy(isolated)
        return (time.perf_counter_ns() - started) / 1_000_000
    try:
        def verified(fn, data, expected):
            result = fn(session, data, len(data))
            assert json.loads(ctypes.string_at(result, lib.eyg_android_result_len(session))) == expected
        done = {'status': 'done', 'result': {'value': {'integer': 42}}}
        verified(lib.eyg_android_evaluate, program, done)
        verified(lib.eyg_android_evaluate, effect, {'status': 'effect', 'effect': {'label': 'Expo', 'value': {'integer': 20}}})
        verified(lib.eyg_android_resume, reply, done)
        if args.pure: pure_call(verify=True)
        for _ in range(200): call(lib.eyg_android_evaluate, program)
        evaluate, resume, pure = [], [], []
        for _ in range(args.iterations):
            evaluate.append(call(lib.eyg_android_evaluate, program))
            call(lib.eyg_android_evaluate, effect)
            resume.append(call(lib.eyg_android_resume, reply))
            if args.pure: pure.append(pure_call())
    finally:
        lib.eyg_android_destroy(session)
    def summary(values):
        values = sorted(values)
        return { 'p50_ms': statistics.median(values), 'p95_ms': values[int(len(values) * .95)], 'p99_ms': values[int(len(values) * .99)], 'max_ms': max(values) }
    report = {'target': 'host C ABI; Android device not measured', 'iterations': args.iterations,
              'results_verified_before_timing': True,
              'workload': 'parse/evaluate !int_add(20,22); external effect continuation resume',
              'evaluate': summary(evaluate), 'resume': summary(resume), 'budget_ms': args.budget_ms}
    report['passed'] = max(report['evaluate']['max_ms'], report['resume']['max_ms']) < args.budget_ms
    if args.pure:
        report['pure_sync_isolated'] = summary(pure)
        report['pure_sync_workload'] = 'fresh session, fixed-buffer pure function evaluation, result serialization and session destruction'
        report['passed'] = report['passed'] and report['pure_sync_isolated']['max_ms'] < args.budget_ms
    text = json.dumps(report, indent=2) + '\n'
    if args.output: args.output.write_text(text)
    print(text, end='')
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == '__main__': main()
