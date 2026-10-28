#!/usr/bin/env python3
"""Compare validation against actual next-tui decoders without running effects."""
import argparse
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import random
import shutil
import sys

from differential import PACKAGE, ORACLE_SHA, Peer, first_difference, literal_fixture, same

UNIT = {"record": {}}
BINARY = {"binary": {"/": {"bytes": ""}}}
TEXT = {"string": "text"}
INTEGER = {"integer": 42}


def tag(label, value=UNIT):
    return {"tagged": {"label": label, "value": deepcopy(value)}}


def record(**fields):
    return {"record": fields}


def profiles():
    valid = {label: deepcopy(UNIT) for label in ("CWD", "Now", "Flip", "StandardIn")}
    valid.update({label: deepcopy(TEXT) for label in ("StandardOut", "StandardError", "Env", "EYGParse", "ReadDirectory", "MakeDirectory", "DeleteFile")})
    valid.update({label: deepcopy(INTEGER) for label in ("Sleep", "Random", "Exit")})
    valid["DecodeJSON"] = deepcopy(BINARY)
    valid["ReadFile"] = record(path=TEXT, offset=INTEGER, limit=INTEGER)
    valid["WriteFile"] = record(path=TEXT, contents=BINARY)
    valid["AppendFile"] = deepcopy(valid["WriteFile"])
    valid["Hash"] = record(algorithm=tag("SHA256"), bytes=BINARY)
    valid["CreateKey"] = tag("Eddsa", TEXT)  # Options are accepted and ignored.
    valid["Sign"] = record(key=tag("Eddsa", record(d=BINARY)), data=BINARY)
    valid["Fetch"] = record(method=tag("GET"), scheme=tag("HTTPS"), host=TEXT,
                            port=tag("None"), path=TEXT, query=tag("None"),
                            headers={"list": [record(key=TEXT, value=TEXT)]}, body=BINARY)
    return valid


def mutations(value):
    # Replace every decoded nested value independently. Keep records' insertion
    # order so simultaneous wrong/missing fields exercise the decoder sequence.
    replacements = [UNIT, INTEGER, {"integer": 1e100}, TEXT, BINARY,
                    {"list": []}, tag("Unknown"), tag("None", TEXT), tag("Some", INTEGER)]
    for replacement in replacements:
        yield deepcopy(replacement)
    if "record" in value:
        for name, child in value["record"].items():
            missing = deepcopy(value)
            del missing["record"][name]
            yield missing
            for mutated in mutations(child):
                result = deepcopy(value)
                result["record"][name] = mutated
                yield result
    elif "tagged" in value:
        for payload in replacements:
            result = deepcopy(value)
            result["tagged"]["value"] = deepcopy(payload)
            yield result
    elif "list" in value:
        for index, child in enumerate(value["list"]):
            for mutated in mutations(child):
                result = deepcopy(value)
                result["list"][index] = mutated
                yield result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=PACKAGE / "work/effect-cast-check")
    parser.add_argument("--bun", default=shutil.which("bun") or "/workspace/tooling/bin/bun")
    parser.add_argument("--seed", type=int, default=20261028)
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--report", type=Path, default=PACKAGE / "reports/effect-cast.json")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    native = Peer([str(args.binary.resolve())])
    oracle = Peer([args.bun, str(PACKAGE / "tests/computer_oracle.mjs")])
    report = {"oracle": ORACLE_SHA, "seed": args.seed,
              "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              "checked": 0, "failed": 0, "failures": [], "passed": False}
    counts = Counter()
    valid_counts = Counter()

    def compare(label, lift):
        request = {"label": label, "lift": lift, "cast_only": True}
        expected, got = oracle.request(request), native.request(request)
        report["checked"] += 1
        counts[label] += 1
        if expected == {"valid": True}:
            valid_counts[label] += 1
        if not same(expected, got):
            report["failed"] += 1
            if len(report["failures"]) < 20:
                report["failures"].append({"request": request,
                    "difference": first_difference(expected, got), "expected": expected, "got": got})
            if report["failed"] <= 5:
                print(json.dumps({"label": label, "difference": first_difference(expected, got)}, ensure_ascii=False), file=sys.stderr)

    try:
        valid = profiles()
        for label, lift in valid.items():
            compare(label, lift)
            for mutated in mutations(lift):
                compare(label, mutated)
        for _ in range(args.cases):
            _, lift = literal_fixture(rng, depth=rng.randrange(1, 5))
            compare(rng.choice(list(valid)), lift)
        report["counts"] = dict(counts)
        report["valid_counts"] = dict(valid_counts)
        report["passed"] = report["failed"] == 0 and set(valid_counts) == set(valid)
    finally:
        native.close()
        oracle.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "failures"}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
