#!/usr/bin/env python3
"""Offline CID bytes and cache resolution compared with the actual Gleam hub."""
import argparse
import base64
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
import shutil
import sys

from differential import PACKAGE, ORACLE_SHA, Peer, first_difference, generated_program, node, call, builtin


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, default=PACKAGE / "work/hub-check")
    p.add_argument("--bun", default=shutil.which("bun") or "/workspace/tooling/bin/bun")
    p.add_argument("--seed", type=int, default=20261028)
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--report", type=Path, default=PACKAGE / "reports/hub.json")
    args = p.parse_args()
    rng = random.Random(args.seed)
    native = Peer([str(args.binary.resolve())])
    oracle = Peer([args.bun, str(PACKAGE / "tests/hub_oracle.mjs")])
    counts = Counter()
    report = {"oracle": ORACLE_SHA, "seed": args.seed, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(), "failures": []}

    def check(category, request, expected):
        got = native.request(request)
        counts[category] += 1
        if got != expected and len(report["failures"]) < 20:
            report["failures"].append({"category": category, "request": request, "difference": first_difference(expected, got), "expected": expected, "got": got})

    try:
        programs = [generated_program(rng) for _ in range(args.cases)]
        programs += [node("i", v=42, _native_node=123), node("u", l="ignored", extra=True), node("i", v=1.0), node("x", v={"/": {"bytes": "AR=="}}), node("s", v="\0\b\f\nλé👩🏽‍💻"), node("s", v="".join(map(chr, range(32))))]
        programs += [node("@", p="demo", r=version) for version in [9007199254740992, 10**18, 10**20, 10**21, -9007199254740992]]
        programs += [node("@", p="demo", r=rng.randrange(1 << 53, 1 << 62)) for _ in range(50)]
        packages = {f"probe{i}": {"version": 1, "program": program} for i, program in enumerate(programs)}
        metadata = oracle.request({"op": "package_metadata", "packages": packages})
        http_fixture = oracle.request({"op": "hub_fixture", "packages": packages})
        if "packages" not in metadata or "modules" not in http_fixture:
            raise RuntimeError(f"oracle fixture failure: {metadata}")
        for entry in metadata["packages"]:
            check("canonicalCID", {"op": "cid", "program": entry["program"]}, {"cid": entry["cid"], "bytes": base64.b64decode(http_fixture["modules"][entry["cid"]]).decode()})

        for i in range(args.cases):
            kind = rng.randrange(5)
            n = rng.randrange(1000)
            module = node("i", v=n) if kind == 0 else node("s", v=f"λ{n}") if kind == 1 else node("f", l="x", b=builtin("int_add", node("v", l="x"), node("i", v=n))) if kind == 2 else call(node("t", l="Some"), node("i", v=n)) if kind == 3 else call(node("c"), node("i", v=n), node("ta"))
            version = rng.randint(1, 10)
            fixture = {"demo": {"version": version, "program": module}}
            cid = oracle.request({"op": "package_metadata", "packages": fixture})["packages"][0]["cid"]
            reference = rng.choice([node("@", p="demo"), node("@", p="demo", r=version), node("@", p="demo", r=version, l={"/": cid}), node("#", l={"/": cid})])
            program = call(reference, node("i", v=7)) if kind == 2 else reference
            request = {"op": "fixture", "packages": fixture, "program": program}
            check("cachedResolution", request, oracle.request(request))

        fixture = {"demo": {"program": node("i", v=42)}}
        request = {"op": "fixture", "packages": fixture, "program": node("@", p="demo")}
        check("defaultVersion", request, oracle.request(request))
        source = node("i", v=42)
        cid = oracle.request({"op": "package_metadata", "packages": {"demo": {"program": source}}})["packages"][0]["cid"]
        check("rejectTamperedModule", {"op": "verify", "cid": cid, "bytes": '{"0":"i","v":41}'}, {"error": "ModuleHashMismatch"})
        check("verifyReorderedModule", {"op": "verify", "cid": cid, "bytes": '{"extra":"ignored","v":42,"0":"i"}'}, {"verified": True})
        for broken in [node("v", l="missing"), call(node("p", l="Probe"), node("u")), node("@", p="unknown")]:
            request = {"op": "fixture", "packages": {"demo": {"version": 1, "program": broken}}, "program": node("@", p="demo")}
            check("rejectImpureOrBrokenModule", request, oracle.request(request))
        for reference in [node("@", p="absent"), node("@", p="demo", r=0), node("@", p="demo", r=2)]:
            request = {"op": "fixture", "packages": fixture, "program": reference}
            check("unknownRelease", request, oracle.request(request))
        report["passed"] = not report["failures"]
    finally:
        native.close()
        oracle.close()
        report["counts"] = dict(counts)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "failures"}))
    if report["failures"]:
        print(json.dumps(report["failures"][:3], ensure_ascii=False, indent=2), file=sys.stderr)
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
