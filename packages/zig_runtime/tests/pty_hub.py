#!/usr/bin/env python3
"""Exercise cache.ready, package selection, loading, and CIDs over a real HTTP hub.

The local server uses module bytes and ledger payloads produced and decoded by
the pinned Gleam adapter. A delayed module response makes the loading screen
observable independently of the later resolved screen.
"""
import argparse
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import threading
import time
from urllib.parse import parse_qs, urlparse

from differential import PACKAGE, ORACLE, ORACLE_SHA, Peer, first_difference
from terminal import Terminal
from benchmark import summary


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/eyg")
    p.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    p.add_argument("--gleam", default=os.environ.get("GLEAM") or shutil.which("gleam") or "/workspace/tooling/bin/gleam")
    p.add_argument("--report", type=Path, default=PACKAGE / "reports/pty-hub.json")
    args = p.parse_args()
    adapter = Peer([args.bun, str(PACKAGE / "tests/oracle.mjs")])
    try:
        fixture = adapter.request({"op": "hub_fixture", "packages": {"demo": {"version": 1, "program": {"0": "i", "v": 42}}}})
    finally:
        adapter.close()
    modules = {cid: base64.b64decode(data) for cid, data in fixture["modules"].items()}
    module_cid = next(iter(modules))
    requests, phase = [], [""]

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urlparse(self.path)
            requests.append({"phase": phase[0], "path": self.path, "user_agent": self.headers.get("User-Agent", "")})
            status, body = 200, b""
            if parsed.path == "/packages/pull":
                since = int(parse_qs(parsed.query).get("since", ["0"])[0])
                body = json.dumps(fixture["ledger"] if since == 0 else {"entries": []}, separators=(",", ":")).encode()
            elif parsed.path.startswith("/modules/") and parsed.path[9:] in modules:
                time.sleep(.5)
                body = modules[parsed.path[9:]]
            else:
                status, body = 404, b"unknown fixture route"
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}"
    report = {"oracle": ORACLE_SHA, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              "fixture": {"cid": module_cid, "program": {"0": "i", "v": 42}, "module_delay_ms": 500},
              "passed": False, "failures": [], "requests": requests, "native_samples_ns": []}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")

    def exercise(label, command, cwd):
        phase[0] = label
        snapshots = []
        with Terminal(command, cwd=cwd, env={"EYG_ORIGIN": origin}) as term:
            term.frame()
            # A ready cache requests another page after every nonempty page.
            deadline = time.monotonic() + 10
            while not any(r["phase"] == label and "since=1" in r["path"] for r in requests):
                term.settle(quiet=.02, timeout=1)
                if time.monotonic() > deadline:
                    raise TimeoutError(f"{label} did not pull and finish the fixture ledger")
            term.settle(quiet=.05)
            snapshots.append(("startup", term.snapshot()))
            for name, data in (("release-picker", b"@"), ("release-complete", b"\t"), ("reference-loading", b"\r")):
                _, elapsed = term.send(data)
                if label == "native":
                    report["native_samples_ns"].append(elapsed)
                snapshots.append((name, term.snapshot()))
            # Typing and cancellation stay responsive while a module request is
            # pending; its eventual reply must preserve the current editor mode.
            _, elapsed = term.send(b"n")
            if label == "native":
                report["native_samples_ns"].append(elapsed)
            snapshots.append(("modal-during-load", term.snapshot()))
            term.send(b"\x1b")
            snapshots.append(("modal-cancelled-load", term.snapshot()))
            if "loading" in term.plain():
                term.frame(timeout=5)
                term.settle(quiet=.03)
            snapshots.append(("reference-resolved", term.snapshot()))
            for name, data in (("run-release", b"\r"), ("paste-content", ("\x1b[200~#" + module_cid + "\x1b[201~").encode()), ("run-content", b"\r")):
                _, elapsed = term.send(data)
                if label == "native":
                    report["native_samples_ns"].append(elapsed)
                snapshots.append((name, term.snapshot()))
            report[label + "_cleanup"] = term.quit()
        return snapshots

    try:
        expected = exercise("gleam", [args.gleam, "run", "--", "tui"], ORACLE / "packages/gleam_cli")
        got = exercise("native", [str(args.binary.resolve())], PACKAGE.parents[1])
        for (name, e), (native_name, g) in zip(expected, got):
            assert name == native_name
            difference = first_difference(e, g)
            if difference:
                report["failures"].append({"name": name, "difference": difference})
        report["checked"] = len(expected)
        report["parity_passed"] = not report["failures"]
        report["cleanup_passed"] = all(report[key]["exit_code"] == 0 and report[key]["termios_restored"] and report[key]["paste_disabled"] for key in ("native_cleanup", "gleam_cleanup"))
        report["key_to_frame"] = summary(report["native_samples_ns"])
        report["passed"] = report["parity_passed"] and report["cleanup_passed"] and report["key_to_frame"]["under_10ms"]
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        server.shutdown()
        server.server_close()
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("requests", "native_samples_ns")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
