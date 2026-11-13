#!/usr/bin/env python3
"""Compare actual Gleam glam layouts for values, closures, and partial functions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import sys

from differential import PACKAGE, ORACLE_SHA, Peer, literal_fixture, node, call, builtin, first_difference, same, unicode_record_program


def directed():
    for code in [node("c"), node("e", l="x"), node("o", l="x"), node("g", l="x"), node("t", l="Some"), node("m", l="Some"), node("n"), node("p", l="Ping"), node("h", l="Ping"), node("b", l="int_add"), node("f", l="argument", b=node("v", l="argument"))]:
        yield code
    yield call(node("c"), node("i", v=42))
    yield call(node("e", l="answer"), node("i", v=42))
    yield builtin("int_add", node("i", v=42))
    yield builtin("fix", node("f", l="self", b=node("f", l="x", b=node("v", l="x"))))
    yield call(node("h", l="Ping"), node("f", l="x", b=node("f", l="resume", b=node("v", l="resume"))), node("f", l="_", b=call(node("p", l="Ping"), node("i", v=1))))
    for size in (0, 1, 2, 10, 30, 80):
        value = node("ta")
        for i in range(size):
            value = call(node("c"), node("i", v=i), value)
        yield value
    for depth in range(1, 13):
        value = node("s", v="deep")
        for _ in range(depth):
            value = call(node("e", l="nested"), call(node("c"), value, node("ta")), node("u"))
        yield value
    for i in range(32):
        yield node("s", v="a" + chr(i) + "b")
    yield unicode_record_program()


def unicode_records(rng, count):
    """Exercise UTF-16 order with unique scalar labels and shared prefixes."""
    def scalar():
        point = rng.randrange(0x110000 - 0x800)
        return chr(point + 0x800 if point >= 0xD800 else point)

    for _ in range(count):
        shared = chr(rng.randrange(0x10000, 0x110000))
        candidates = [chr(rng.randrange(0xE000, 0x10000)),
                      chr(rng.randrange(0x10000, 0x110000)),
                      shared, shared + "a", shared + scalar()]
        candidates += ["".join(scalar() for _ in range(rng.randrange(1, 4)))
                       for _ in range(rng.randrange(5))]
        labels = list(dict.fromkeys(candidates))
        rng.shuffle(labels)
        program = node("u")
        for index, label in enumerate(labels):
            program = call(node("e", l=label), node("i", v=index), program)
        yield program


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/pretty-runner")
    p.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    p.add_argument("--seed", type=int, default=20261028)
    p.add_argument("--programs", type=int, default=1000)
    p.add_argument("--unicode-records", type=int, default=300)
    p.add_argument("--report", type=Path, default=PACKAGE / "reports/pretty.json")
    args = p.parse_args()
    native = Peer([str(args.binary.resolve())])
    oracle = Peer([args.bun, str(PACKAGE / "tests/oracle.mjs")])
    rng = random.Random(args.seed)
    report = {"oracle": ORACLE_SHA, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              "seed": args.seed, "checked": 0, "unicode_records": 0, "failed": 0, "failures": [], "passed": False}
    widths = (1, 2, 3, 8, 20, 40, 80, 120)

    def check(program, width):
        request = {"op": "pretty", "program": program, "width": width}
        expected, got = oracle.request(request), native.request(request)
        report["checked"] += 1
        if not same(expected, got):
            report["failed"] += 1
            if len(report["failures"]) < 40:
                failure = {"request": request, "difference": first_difference(expected, got), "expected": expected, "got": got}
                report["failures"].append(failure)
                if report["failed"] <= 5:
                    print(json.dumps({"width": width, "path": failure["difference"]["path"],
                                      "expected_preview": str(expected.get("text", expected))[:160],
                                      "got_preview": str(got.get("text", got))[:160]}, ensure_ascii=False), file=sys.stderr)

    try:
        for program in directed():
            for width in widths:
                check(program, width)
        for _ in range(args.programs):
            program, _ = literal_fixture(rng, depth=rng.randrange(1, 5))
            check(program, rng.choice(widths))
        for program in unicode_records(rng, args.unicode_records):
            check(program, rng.choice(widths))
            report["unicode_records"] += 1
        report["passed"] = report["failed"] == 0
    finally:
        native.close()
        oracle.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "failures"}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
