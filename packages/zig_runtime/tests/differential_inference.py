#!/usr/bin/env python3
"""Compare every node's inferred type, effect, and diagnostic to Gleam."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import sys

from differential import PACKAGE, ORACLE_SHA, Peer, generated_program, node, call, builtin, first_difference, same, UNICODE


def annotate(program, counter):
    if isinstance(program, dict):
        if "0" in program:
            counter[0] += 1
            program["_native_node"] = counter[0]
        for key in list(program):
            annotate(program[key], counter)
    elif isinstance(program, list):
        for child in program:
            annotate(child, counter)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/inference-runner")
    p.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    p.add_argument("--seed", type=int, default=20261028)
    p.add_argument("--programs", type=int, default=1000)
    p.add_argument("--scopes", type=int, default=300)
    p.add_argument("--report", type=Path, default=PACKAGE / "reports/inference.json")
    args = p.parse_args()
    native = Peer([str(args.binary.resolve())])
    oracle = Peer([args.bun, str(PACKAGE / "tests/inference_oracle.mjs")])
    rng = random.Random(args.seed)
    report = {"seed": args.seed, "oracle": ORACLE_SHA, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              "programs": 0, "scopes": 0, "node_annotations": 0, "failed": 0, "failures": []}
    try:
        for index in range(args.programs + args.scopes):
            scope = []
            names = []
            if index >= args.programs:
                for i in range(rng.randrange(1, 5)):
                    name = f"prior{i}"
                    scope.append({"name": name, "program": node("i", v=rng.randrange(-1000, 1000))})
                    names.append(name)
                # Runtime closures and partially applied builtins are retyped
                # in a session; scope tests expose their captured environments.
                scope.append({"name": "adder", "program": node("f", l="x", b=builtin("int_add", node("v", l="x"), node("v", l=names[0])))})
                scope.append({"name": "plus3", "program": call(node("b", l="int_add"), node("i", v=3))})
                scope.append({"name": "text", "program": node("s", v=rng.choice(UNICODE))})
            program = generated_program(rng, scope=tuple(names))
            if scope and rng.randrange(3) == 0:
                program = call(node("v", l=rng.choice(("adder", "plus3"))), program)
            counter = [0]
            annotate(program, counter)
            report["node_annotations"] += counter[0]
            for entry in scope:
                annotate(entry["program"], counter)
            request = {"program": program, "scope": scope}
            expected, got = oracle.request(request), native.request(request)
            if "error" in expected:
                raise RuntimeError(f"Gleam inference adapter error: {expected}")
            report["scopes" if scope else "programs"] += 1
            if not same(expected, got):
                report["failed"] += 1
                failure = {"index": index, "request": request, "difference": first_difference(expected, got)}
                if len(report["failures"]) < 30:
                    report["failures"].append(failure)
                if report["failed"] <= 5:
                    print(json.dumps(failure, ensure_ascii=False), file=sys.stderr)
        report["passed"] = report["failed"] == 0
    finally:
        native.close()
        oracle.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "failures"}))
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
