#!/usr/bin/env python3
"""Generate captured CEK contexts and compare the actual oracle inspector text."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import sys

from differential import PACKAGE, ORACLE_SHA, Peer, node, call, builtin, literal_fixture, first_difference, same


def lam(name, body):
    return node("f", l=name, b=body)


def var(name):
    return node("v", l=name)


def let(name, value, body):
    return node("l", l=name, v=value, t=body)


def effect(label="Ping"):
    return call(node("p", l=label), node("i", v=42))


def handle(body, label="Ping", handler=None):
    if handler is None:
        handler = lam("payload", lam("resume", var("resume")))
    return call(node("h", l=label), handler, lam("unit", body))


def directed():
    # Each frame action appears in the captured prefix, including CallWith from
    # a suspended curried handler. Pending code is inspected, never evaluated.
    yield "trace", handle(effect())
    yield "argument", handle(call(effect(), node("s", v="pending argument")))
    yield "apply", handle(call(lam("x", var("x")), effect()))
    yield "assign", handle(let("result", effect(), var("result")))
    yield "nested-delimit", handle(handle(effect(), "Other"))
    q_handler = lam("q", let("interrupted", effect(), lam("resumeQ", var("resumeQ"))))
    yield "call-with-resumption", handle(handle(effect("Other"), "Other", q_handler))
    yield "tail-trace-replacement", handle(call(lam("a", call(lam("b", effect()), node("s", v="latest argument"))), node("i", v=123)))
    pending = [node("." , i="./path/quoted\".eyg"), node("@", p="package"), node("@", p="version", r=123)]
    cid = {"/": "baguqeeraaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
    pending.extend([node("#", l=cid), node("@", p="pinned", r=7, l=cid)])
    for i, code in enumerate(pending):
        yield f"reference-{i}", handle(let("pending", effect(), code))
    values = [node("s", v="\u0000\u0007\b\f\n\r\t\u007f\u0085\"\\🦊"),
              node("x", v={"/": {"bytes": "AAECf4D/"}}),
              call(node("t", l="Some"), node("i", v=-123)),
              builtin("int_add", node("i", v=9)),
              lam("closure", let("inside", node("u"), var("captured")))]
    for i, value in enumerate(values):
        yield f"scope-value-{i}", let("captured", node("s", v="outer"), let("bound", value, handle(effect())))
    # A prior captured continuation becomes an ordinary value in the next Env.
    yield "continuation-in-env", let("saved", handle(effect()), handle(effect()))


def generated(rng):
    body = effect()
    for index in range(rng.randrange(1, 7)):
        value, _ = literal_fixture(rng, depth=rng.randrange(1, 4))
        name = f"local{index}"
        choice = rng.randrange(5)
        if choice == 0:
            body = call(body, value)
        elif choice == 1:
            body = call(lam(name, value), body)
        elif choice == 2:
            body = let(name, body, value)
        elif choice == 3:
            body = call(lam(name, body), value)
        else:
            body = handle(body, f"Other{index}")
    value, _ = literal_fixture(rng, depth=3)
    return let("outer", value, handle(body))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/pretty-runner")
    parser.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    parser.add_argument("--seed", type=int, default=20261028)
    parser.add_argument("--programs", type=int, default=300)
    parser.add_argument("--report", type=Path, default=PACKAGE / "reports/resume.json")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    native = Peer([str(args.binary.resolve())])
    oracle = Peer([args.bun, str(PACKAGE / "tests/oracle.mjs")])
    report = {"oracle": ORACLE_SHA, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              "seed": args.seed, "checked": 0, "failed": 0, "failures": [], "passed": False}
    widths = (1, 2, 3, 8, 20, 40, 80, 120)

    def check(name, program, width, meta):
        request = {"op": "pretty", "program": program, "width": width, "meta": meta}
        expected, got = oracle.request(request), native.request(request)
        report["checked"] += 1
        if "text" not in expected or not expected["text"].startswith("Partial(") or not same(expected, got):
            report["failed"] += 1
            if len(report["failures"]) < 20:
                report["failures"].append({"name": name, "request": request,
                    "difference": first_difference(expected, got), "expected": expected, "got": got})
            if report["failed"] <= 5:
                print(json.dumps({"case": name, "width": width, "meta": meta,
                                  "path": first_difference(expected, got)["path"]}, ensure_ascii=False), file=sys.stderr)

    try:
        for name, program in directed():
            for width in widths:
                for meta in (None, "repl"):
                    check(name, program, width, meta)
        for index in range(args.programs):
            program = generated(rng)
            width = rng.choice(widths)
            for meta in (None, "repl"):
                check(f"generated-{index}", program, width, meta)
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
