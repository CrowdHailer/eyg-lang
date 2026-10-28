#!/usr/bin/env python3
"""Exercise real Gleam and Zig terminals, compare VT cells, time key-to-frame."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

from differential import PACKAGE, ORACLE, ORACLE_SHA, first_difference
from benchmark import summary
from terminal import Terminal


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/eyg")
    p.add_argument("--report", type=Path, default=PACKAGE / "reports/pty.json")
    p.add_argument("--cast", type=Path, default=PACKAGE / "recordings/parity.cast")
    p.add_argument("--gleam", default=os.environ.get("GLEAM") or shutil.which("gleam") or "/workspace/tooling/bin/gleam")
    args = p.parse_args()
    events = [("integer-open", b"n"), ("integer-type", b"7"), ("integer-apply", b"\r"), ("integer-run", b"\r"),
              ("history-open", b"\x1b[A"), ("history-close", b"\x1b[B"),
              ("paste-arithmetic", b"\x1b[200~!int_add(20, 22)\x1b[201~"), ("run-arithmetic", b"\r"),
              ("string-open", b"s"), ("unicode-paste", "\x1b[200~hello λé\x1b[201~".encode()),
              ("string-apply", b"\r"), ("string-run", b"\r"),
              ("picker-open", b"j"), ("picker-next", b"\x1b[B"), ("picker-close", b"\x1b")]
    report = {"oracle": ORACLE_SHA, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              "measurement": "write key bytes to local PTY through read of synchronized frame terminator; includes dispatch, rendering, ANSI encoding, transport, Python reader scheduling; timestamp before observer VT decoding; excludes startup; standalone Escape has oracle 40ms timeout",
              "terminal_model": "pyte 0.8.2; internal full-cell tests additionally cover dim, underline color, hyperlinks",
              "checked": 0, "failures": [], "interactions": []}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({**report, "passed": False, "status": "running"}, indent=2) + "\n")
    with Terminal([str(args.binary.resolve())], env={"EYG_ORIGIN": "http://127.0.0.1:9"}) as native, Terminal([args.gleam, "run", "--", "tui"], cwd=ORACLE / "packages/gleam_cli", env={"EYG_ORIGIN": "http://127.0.0.1:9"}) as oracle:
        def compare(name):
            report["checked"] += 1
            difference = first_difference(oracle.snapshot(), native.snapshot())
            if difference:
                report["failures"].append({"name": name, "difference": difference})
                if len(report["failures"]) < 5:
                    print(f"FAIL PTY {name}: {difference}", file=sys.stderr)
        native.frame()
        oracle.frame()
        native.settle()
        oracle.settle()
        compare("startup")
        _, native_ns = native.send(b"s")
        _, oracle_ns = oracle.send(b"s")
        report["interactions"].append({"name": "split-utf8-open", "native_ns": native_ns, "gleam_ns": oracle_ns, "standalone_escape": False})
        compare("split-utf8-open")
        native.send(b"\xce", wait=False)
        oracle.send(b"\xce", wait=False)
        native.settle(quiet=.02)
        oracle.settle(quiet=.02)
        compare("split-utf8-prefix")
        _, native_ns = native.send(b"\xbb")
        _, oracle_ns = oracle.send(b"\xbb")
        report["interactions"].append({"name": "split-utf8-complete", "native_ns": native_ns, "gleam_ns": oracle_ns, "standalone_escape": False})
        compare("split-utf8-complete")
        native.send(b"\x1b")
        oracle.send(b"\x1b")
        compare("split-utf8-cancel")
        for name, data in events:
            _, native_ns = native.send(data)
            _, oracle_ns = oracle.send(data)
            compare(name)
            report["interactions"].append({"name": name, "native_ns": native_ns, "gleam_ns": oracle_ns,
                                           "standalone_escape": data == b"\x1b"})
        native.resize(100, 30)
        oracle.resize(100, 30)
        compare("resize")
        report["native_cleanup"] = native.quit()
        report["gleam_cleanup"] = oracle.quit()
        native.save_cast(args.cast, "EYG native terminal parity exercise")
        samples = [x["native_ns"] for x in report["interactions"] if not x["standalone_escape"]]
        report["key_to_frame"] = summary(samples)
        report["parity_passed"] = not report["failures"]
        report["cleanup_passed"] = all(report[key]["exit_code"] == 0 and report[key]["termios_restored"] and report[key]["paste_disabled"] for key in ("native_cleanup", "gleam_cleanup"))
        report["passed"] = report["parity_passed"] and report["cleanup_passed"] and report["key_to_frame"]["under_10ms"]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"checked": report["checked"], "parity_passed": report["parity_passed"], "cleanup_passed": report["cleanup_passed"], "key_to_frame": report["key_to_frame"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
