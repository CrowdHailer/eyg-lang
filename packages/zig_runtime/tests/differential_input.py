#!/usr/bin/env python3
"""Compare raw terminal decoding, including every intermediate input fragment."""
import argparse
import json
import hashlib
from pathlib import Path
import random
import os
import shutil
import sys

from differential import PACKAGE, ORACLE_SHA, Peer, UNICODE, first_difference, same


def corpus(rng, count):
    yield from [chr(i) for i in range(128)]
    yield from UNICODE
    yield from ["\x1b", "\x1b[", "\x1bO", "\x1b[1;", "\x1b[200~", "\x1b[200~abc", "\x1b[200~\nλ\x1b[201~"]
    for final in "ABCDHFPQRSZ~uXYZ":
        for modifier in range(1, 9):
            yield f"\x1b[1;{modifier}{final}"
    for number in range(1, 35):
        yield f"\x1b[{number}~"
    for final in "ABCDHFPQRSxyz":
        yield "\x1bO" + final
    for code in (0, 1, 2, 3, 32, 33, 34, 35, 64, 65, 66, 67):
        for final in "Mm":
            yield f"\x1b[<{code};10;20{final}"
    atoms = ["a", "λ", "é", "👩🏽‍💻", "\t", "\r", "\x7f", "\x01", "\x11", "\x1b[A", "\x1b[1;5C", "\x1bOQ", "\x1b[<64;3;8M", "\x1bz"]
    for _ in range(count):
        if rng.randrange(5) == 0:
            yield "\x1b[200~" + "".join(rng.choice(atoms) for _ in range(rng.randrange(8))) + "\x1b[201~"
        else:
            yield "".join(rng.choice(atoms) for _ in range(rng.randrange(1, 12)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/eyg")
    parser.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    parser.add_argument("--seed", type=int, default=20261028)
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--report", type=Path, default=PACKAGE / "reports/input.json")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    native = Peer([str(args.binary.resolve()), "--protocol"])
    oracle = Peer([args.bun, str(PACKAGE / "tests/oracle.mjs")])
    report = {"seed": args.seed, "oracle": ORACLE_SHA, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(), "checked": 0, "failed": 0, "failures": []}

    def check(request):
        expected, got = oracle.request(request), native.request(request)
        report["checked"] += 1
        if not same(expected, got):
            report["failed"] += 1
            if len(report["failures"]) < 20:
                report["failures"].append({"request": request, "difference": first_difference(expected, got)})
        return expected

    try:
        for text in corpus(rng, args.cases):
            check({"op": "input", "text": text, "flush": False})
            check({"op": "input", "text": text, "flush": True})
            # Character boundary fragments model the runtime's UTF-8 decoder.
            # A split UTF-8 scalar is not passed to an API taking valid strings.
            remainder = ""
            at = 0
            while at < len(text):
                end = min(len(text), at + rng.randrange(1, 5))
                response = check({"op": "input", "text": remainder + text[at:end], "flush": False})
                remainder = response["remainder"]
                at = end
            check({"op": "input", "text": remainder, "flush": True})
        report["passed"] = report["failed"] == 0
    finally:
        native.close()
        oracle.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "failures"}))
    if report["failures"]:
        print(json.dumps(report["failures"][:3], ensure_ascii=False, indent=2), file=sys.stderr)
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
