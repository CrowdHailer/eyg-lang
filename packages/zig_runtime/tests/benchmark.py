#!/usr/bin/env python3
"""Measure native key dispatch + complete cell-frame rendering; gate at 10 ms.

Wall timings include event dispatch, complete cell-frame construction, and
reset of the reusable frame-output arena. They exclude terminal transport and
JSON encoding. Paired thread CPU samples are diagnostic; only wall time gates
the 10 ms target. Native and Gleam execute the same event traces in separate
process phases. Correctness remains a separate gate.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import platform
import shutil
import subprocess
import sys

from differential import PACKAGE, REPO, ORACLE_SHA, Peer, tui_scenarios


def summary(samples):
    if not samples:
        raise ValueError("benchmark produced no samples")
    ordered = sorted(samples)
    percentile = lambda p: ordered[min(len(ordered) - 1, math.ceil(len(ordered) * p) - 1)] / 1e6
    return {"samples": len(samples), "p50_ms": percentile(.5), "p95_ms": percentile(.95),
            "p99_ms": percentile(.99), "max_ms": ordered[-1] / 1e6,
            "mean_ms": sum(samples) / len(samples) / 1e6,
            "under_10ms": all(sample < 10_000_000 for sample in samples)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/eyg")
    p.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    p.add_argument("--iterations", type=int, default=100)
    p.add_argument("--warmup", type=int, default=10)
    p.add_argument("--parity-report", type=Path, default=PACKAGE / "reports/differential.json")
    p.add_argument("--input-report", type=Path, default=PACKAGE / "reports/input.json")
    p.add_argument("--pty-report", type=Path, default=PACKAGE / "reports/pty.json")
    p.add_argument("--hub-report", type=Path, default=PACKAGE / "reports/pty-hub.json")
    p.add_argument("--report", type=Path, default=PACKAGE / "reports/benchmark.json")
    p.add_argument("--oracle", action="store_true", help="also time the Gleam oracle")
    args = p.parse_args()
    binary = args.binary.resolve()
    native = Peer([str(binary), "--protocol"], timeout=120)
    build_info = native.request({"op": "info"})
    oracle = None
    scenarios = tui_scenarios()
    history = []
    for i in range(30):
        history += [{"paste": f"!int_add({i}, 1)"}, {"key": "enter"}]
    history += [{"key": k} for k in ("up", "up", "k", "down", "K", "esc")]
    workloads = {
        "integer-input": scenarios["integer-input"],
        "unicode-input": scenarios["string-unicode"],
        "arithmetic": scenarios["arithmetic-paste"],
        "picker": scenarios["builtin-picker"],
        "history-30": history,
        "structural-navigation": [{"paste": "{x: [1, 2, 3], y: 42}"}] + [{"key": k} for k in ("right", "right", "left", "up", "down", "a", "k", "left", "right")],
        "nested-program-edit": [{"paste": 'let data = {count: 42, items: [1, 2, 3], name: "EYG"} let {count, items} = data !list_fold(items, count, (x, total) -> { !int_add(x, total) })'}]
            + [{"key": k} for k in ("right", "right", "down", "right", "a", "left", "right", "k", "i", "esc", "right", "g", "esc", "up", "left", "right", "enter")],
        "long-cjk-input": scenarios["long-cjk-input"],
        "binary-value": scenarios["binary-ir-aqid"],
    }
    parity = json.loads(args.parity_report.read_text()) if args.parity_report.exists() else None
    raw_input = json.loads(args.input_report.read_text()) if args.input_report.exists() else None
    pty = json.loads(args.pty_report.read_text()) if args.pty_report.exists() else None
    hub = json.loads(args.hub_report.read_text()) if args.hub_report.exists() else None
    binary_sha = hashlib.sha256(binary.read_bytes()).hexdigest()
    matches = lambda r: bool(r and r.get("oracle") == ORACLE_SHA and r.get("binary_sha256") == binary_sha)
    required = ("spec", "generated-program", "generated-external-effects", "syntax-fixture", "generated-syntax", "real-world-syntax", "diagnostic-fixture", "tui-scenario", "tui-world", "tui-hub", "generated-behaviour", "generated-program-edit")
    full_coverage = bool(parity and all(parity.get("counts", {}).get(category, {}).get("checked", 0) > 0 for category in required))
    gates = {"release_fast_build": build_info.get("mode") == "ReleaseFast" and build_info.get("zig") == "0.14.1" and build_info.get("oracle") == ORACLE_SHA,
             "same_binary_full_differential": bool(matches(parity) and parity.get("passed") and full_coverage),
             "same_binary_raw_input": bool(matches(raw_input) and raw_input.get("passed")),
             "same_binary_pty_parity_cleanup": bool(matches(pty) and pty.get("parity_passed") and pty.get("cleanup_passed")),
             "same_binary_pty_under_10ms": bool(matches(pty) and pty.get("key_to_frame", {}).get("under_10ms")),
             "same_binary_ready_hub_parity_cleanup": bool(matches(hub) and hub.get("parity_passed") and hub.get("cleanup_passed")),
             "same_binary_ready_hub_under_10ms": bool(matches(hub) and hub.get("key_to_frame", {}).get("under_10ms"))}
    report = {
        "oracle": ORACLE_SHA, "binary_sha256": binary_sha,
        "build_info": build_info,
        "binary_bytes": binary.stat().st_size,
        "machine": {"platform": platform.platform(), "machine": platform.machine(), "processor": platform.processor(), "cpu_count": os.cpu_count()},
        "measurement": "Monotonic wall time for native event dispatch, complete cell-frame construction, and reusable frame-output arena reset inside the timed interval; excludes JSON serialization, terminal transport, startup; sandboxed effects in Gleam.",
        "clocks": {"wall": "std.time.Timer monotonic elapsed nanoseconds; the only performance-gate clock",
                   "cpu": "CLOCK_THREAD_CPUTIME_ID elapsed nanoseconds for the same event/frame/reset; diagnostic only, excludes descheduled time",
                   "difference": "wall_minus_cpu_ns is diagnostic and includes scheduling plus clock/read overhead; samples are neither replaced nor filtered"},
        "warmup_iterations": args.warmup, "iterations": args.iterations,
        "parity_passed": gates["same_binary_full_differential"] and gates["same_binary_raw_input"] and gates["same_binary_pty_parity_cleanup"] and gates["same_binary_ready_hub_parity_cleanup"],
        "correctness_gates": gates,
        "parity_report": str(args.parity_report), "workloads": {},
        "measurement_phase_order": ["native", "gleam"] if args.oracle else ["native"],
        "process_isolation": "Complete all native workloads and close native before spawning the Gleam oracle; handshake oracle imports before its warmup. Preserve all samples and outliers.",
    }
    try:
        for name, events in workloads.items():
            request = {"op": "bench_tui", "width": 80, "height": 24, "events": events}
            native.request({**request, "iterations": args.warmup})
            got = native.request({**request, "iterations": args.iterations})
            wall_samples, cpu_samples = got.get("samples_ns"), got.get("cpu_samples_ns")
            count = args.iterations * len(events)
            if not isinstance(wall_samples, list) or not isinstance(cpu_samples, list) or len(wall_samples) != count or len(cpu_samples) != count:
                raise RuntimeError(f"native benchmark {name} requires {count} paired wall/CPU samples; got wall={len(wall_samples) if isinstance(wall_samples, list) else None}, cpu={len(cpu_samples) if isinstance(cpu_samples, list) else None}")
            if any(type(ns) is not int or ns < 0 for ns in [*wall_samples, *cpu_samples]):
                raise RuntimeError(f"native benchmark {name} contains invalid nanosecond samples")
            cpu_summary = {key: value for key, value in summary(cpu_samples).items() if key != "under_10ms"}
            result = {"native": summary(wall_samples), "native_cpu": cpu_summary,
                      "events_per_iteration": len(events), "events": events,
                      "samples_ns": wall_samples, "cpu_samples_ns": cpu_samples,
                      "outliers": [{"iteration": i // len(events), "event_index": i % len(events),
                                    "event": events[i % len(events)], "ns": ns,
                                    "cpu_ns": cpu_samples[i], "wall_minus_cpu_ns": ns - cpu_samples[i]}
                                   for i, ns in enumerate(wall_samples) if ns >= 10_000_000]}
            report["workloads"][name] = result
            print("native", name, json.dumps({k: v for k, v in result.items() if k not in ("events", "samples_ns", "cpu_samples_ns")}), flush=True)
        # Importing the large compiled Gleam module graph and its later GC must
        # not overlap the native measurements. Keep the same workload requests
        # and complete the second phase only after the native child has exited.
        native.close()
        native = None
        if args.oracle:
            oracle = Peer([args.bun, str(PACKAGE / "tests/oracle.mjs")], timeout=120)
            ready = oracle.request({"op": "parse", "source": "42"})
            if ready != {"program": {"0": "i", "v": 42}}:
                raise RuntimeError(f"Gleam oracle handshake failed: {ready}")
            for name, events in workloads.items():
                request = {"op": "bench_tui", "width": 80, "height": 24, "events": events}
                oracle.request({**request, "iterations": args.warmup})
                expected = oracle.request({**request, "iterations": args.iterations})
                if "samples_ns" not in expected:
                    raise RuntimeError(f"Gleam benchmark failed: {expected}")
                result = report["workloads"][name]
                result["gleam"] = summary(expected["samples_ns"])
                result["gleam_samples_ns"] = expected["samples_ns"]
                result["median_speedup"] = result["gleam"]["p50_ms"] / max(result["native"]["p50_ms"], 1e-9)
                print("gleam", name, json.dumps({"gleam": result["gleam"], "median_speedup": result["median_speedup"]}), flush=True)
        report["performance_passed"] = all(w["native"]["under_10ms"] for w in report["workloads"].values())
        report["passed"] = report["performance_passed"] and report["parity_passed"] and gates["release_fast_build"] and gates["same_binary_pty_under_10ms"] and gates["same_binary_ready_hub_under_10ms"]
    finally:
        if native:
            native.close()
        if oracle:
            oracle.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
