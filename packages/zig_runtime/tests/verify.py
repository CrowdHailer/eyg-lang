#!/usr/bin/env python3
"""Build immutable native executables and run the pinned-oracle validation gates.

Default coverage includes 5,000 generated programs, 1,000 generated syntax cases,
100 empty-root and 100 nested-program editing traces, and all subsystem suites.
Every suite runs even when a previous suite fails. Oracle crashes/timeouts keep
strict qualification red; successful comparable tests are reported separately.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from differential import PACKAGE, REPO, ORACLE, ORACLE_SHA, Peer

REAL_SHA = "f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=True, indent=2) + "\n")


def source_manifest():
    paths = {PACKAGE / "build.zig", PACKAGE / "build.zig.zon"}
    for directory in ("src", "tests", "scripts", "git", "http"):
        paths.update(p for p in (PACKAGE / directory).rglob("*") if p.is_file() and p.suffix in (".zig", ".py", ".mjs", ".eyg", ".sh", ".json"))
    paths.update(p for p in (PACKAGE / "scripts").iterdir() if p.is_file())
    paths.add(PACKAGE / "tests/requirements.txt")
    paths.update((REPO / "spec/evaluation").glob("*.json"))
    paths.update((ORACLE / "spec/evaluation").glob("*.json"))
    return {(str(p.relative_to(PACKAGE)) if p.is_relative_to(PACKAGE) else ("oracle/" + str(p.relative_to(ORACLE)) if p.is_relative_to(ORACLE) else "repository/" + str(p.relative_to(REPO)))): digest(p) for p in sorted(paths) if p.exists()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--setup", action="store_true", help="prepare pinned oracle worktrees/build and install pinned Python test dependencies")
    parser.add_argument("--quick", action="store_true", help="smaller diagnostic campaign; cannot qualify full requested coverage")
    parser.add_argument("--skip-performance", action="store_true", help="run all functional checks; leave performance qualification incomplete")
    parser.add_argument("--binary", type=Path, help="copy and validate an existing ReleaseFast executable instead of building the main executable")
    parser.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    parser.add_argument("--gleam", default=os.environ.get("GLEAM") or shutil.which("gleam") or "/workspace/tooling/bin/gleam")
    parser.add_argument("--oracle-timeout", type=float, default=30)
    parser.add_argument("--report", type=Path, default=PACKAGE / "reports/verification.json")
    args = parser.parse_args()
    args.report = args.report.resolve()
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + f"-{os.getpid()}"
    run = PACKAGE / "work/verification" / stamp
    artifacts = args.report.parent / ("verification-" + stamp)
    bin_dir, logs = run / "bin", artifacts / "logs"
    bin_dir.mkdir(parents=True)
    logs.mkdir(parents=True)
    env = dict(os.environ, BUN=args.bun, GLEAM=args.gleam, EYG_ORACLE_ROOT=str(ORACLE))
    env["PATH"] = str(Path(args.gleam).resolve().parent) + os.pathsep + env.get("PATH", "")
    env["PYTHONPATH"] = str(REPO / "work/test-dependencies") + os.pathsep + env.get("PYTHONPATH", "")
    result = {"passed": False, "qualified": False, "status": "running", "quick": args.quick,
              "performance_requested": not args.skip_performance, "oracle": ORACLE_SHA,
              "git_reference": REAL_SHA, "command": sys.argv, "artifacts": str(artifacts),
              "stages": [], "known_oracle_gaps": [], "executables": {}}
    started = time.monotonic()
    original_sources = source_manifest()
    write_json(artifacts / "sources.json", original_sources)
    result["source_manifest_sha256"] = digest(artifacts / "sources.json")
    write_json(args.report, result)

    def stage(name, command, report=None, external_report=None, binary=None):
        entry = {"name": name, "command": list(map(str, command)), "passed": False}
        if binary and Path(binary).exists():
            entry["binary_sha256"] = digest(Path(binary))
        result["stages"].append(entry)
        log = logs / (name + ".log")
        entry["log"] = str(log)
        if report:
            Path(report).unlink(missing_ok=True)
        if external_report:
            Path(external_report).unlink(missing_ok=True)
        then = time.monotonic()
        print(f"[{name}]", flush=True)
        try:
            with log.open("wb") as output:
                child = subprocess.run(list(map(str, command)), cwd=PACKAGE, env=env,
                                       stdout=output, stderr=subprocess.STDOUT)
            entry["exit_code"] = child.returncode
            if external_report and Path(external_report).exists():
                shutil.copy2(external_report, report)
            if report and Path(report).exists():
                document = json.loads(Path(report).read_text())
                entry["report"], entry["report_sha256"] = str(report), digest(Path(report))
                entry["report_passed"] = bool(document.get("passed"))
                entry["passed"] = child.returncode == 0 and entry["report_passed"]
                # Subsystem helpers are separate executables built from the
                # same captured sources. Main/UI reports must match main SHA.
                recorded = document.get("binary_sha256")
                if recorded and recorded != entry.get("binary_sha256"):
                    entry["passed"] = False
                    entry["error"] = "report binary hash differs from the invoked executable"
                pin = document.get("oracle", document.get("oracle_commit"))
                if pin and pin != ORACLE_SHA:
                    entry["passed"] = False
                    entry["error"] = "report oracle revision differs from pinned next-tui"
                gaps = {key: document[key] for key in ("oracle_crash_count", "unsupported_count") if document.get(key)}
                if document.get("peer_failures"):
                    gaps["peer_failures"] = document["peer_failures"]
                if gaps:
                    result["known_oracle_gaps"].append({"stage": name, **gaps})
            elif report:
                entry["error"] = "command produced no report"
            else:
                entry["passed"] = child.returncode == 0
        except Exception as error:
            entry["error"] = repr(error)
        entry["seconds"] = round(time.monotonic() - then, 3)
        write_json(args.report, result)
        print(f"  {'PASS' if entry['passed'] else 'FAIL'} ({entry['seconds']}s)", flush=True)
        return entry["passed"]

    try:
        if args.setup:
            stage("setup-oracles", [PACKAGE / "scripts/prepare-oracles.sh"])
            stage("setup-python", [sys.executable, "-m", "pip", "install", "--target", REPO / "work/test-dependencies", "-r", PACKAGE / "tests/requirements.txt"])
        pins = {}
        for name, checkout, expected in (("next-tui", ORACLE, ORACLE_SHA), ("real-world", REPO / "work/oracle-real-world", REAL_SHA)):
            actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
            clean = subprocess.run(["git", "diff", "--quiet", "HEAD", "--"], cwd=checkout).returncode == 0
            pins[name] = {"actual": actual, "expected": expected, "tracked_sources_clean": clean}
            if actual != expected or not clean:
                raise RuntimeError(f"{name} oracle is not the clean pinned revision")
        result["pins"] = pins
        compiled_oracle = ORACLE / "packages/gleam_cli/build/dev/javascript"
        built = {str(p.relative_to(compiled_oracle)): digest(p) for p in sorted(compiled_oracle.rglob("*.mjs"))}
        if not built:
            raise RuntimeError("oracle is not built; run scripts/verify --setup")
        write_json(artifacts / "oracle-build.json", built)
        result["oracle_build_manifest_sha256"] = digest(artifacts / "oracle-build.json")
        zig = PACKAGE / "scripts/zig"
        result["zig"] = subprocess.check_output([zig, "version"], text=True, env=env).strip()
        result["bun"] = subprocess.check_output([args.bun, "--version"], text=True, env=env).strip()
        result["gleam"] = subprocess.check_output([args.gleam, "--version"], text=True, env=env).strip()
        stage("units", [zig, "build", "test", "-Doptimize=ReleaseFast"])
        if args.binary:
            source_binary = args.binary.resolve()
        else:
            stage("build-main", [zig, "build", "-Doptimize=ReleaseFast", "--prefix", run / "install"])
            source_binary = run / "install/bin/eyg"
        binary = bin_dir / "eyg"
        shutil.copy2(source_binary, binary)
        binary.chmod(0o555)
        result["binary_sha256"] = digest(binary)
        probe = Peer([str(binary), "--protocol"])
        try:
            result["build_info"] = probe.request({"op": "info"})
        finally:
            probe.close()
        info = result["build_info"]
        result["release_fast_build"] = info.get("mode") == "ReleaseFast" and info.get("oracle") == ORACLE_SHA and info.get("zig") == "0.14.1" and info.get("git_reference") == REAL_SHA
        helpers = {
            "inference-runner": ("tests/inference_runner.zig", "eyg_native", "src/lib.zig"),
            "pretty-runner": ("tests/pretty_runner.zig", "eyg_interpreter", "src/interpreter.zig"),
            "evaluation-runner": ("tests/evaluation_runner.zig", "eyg_interpreter", "src/interpreter.zig"),
            "computer-runner": ("tests/computer_runner.zig", "computer", "src/computer.zig"),
            "effect-cast-runner": ("tests/effect_cast_runner.zig", "effect_cast", "src/effect_cast.zig"),
            "hub-runner": ("tests/hub_runner.zig", "hub", "src/hub.zig"),
            "patterns-runner": ("tests/patterns_runner.zig", "patterns", "src/tui_patterns.zig"),
            "source-runner": ("tests/source_runner.zig", "eyg_source", "src/source.zig"),
            "http-driver": ("http/driver.zig", "http", "src/http.zig"),
        }
        for name, (root, module, source) in helpers.items():
            target = bin_dir / name
            stage("build-" + name, [zig, "build-exe", "-OReleaseFast", "--dep", module,
                                   "-Mroot=" + root, "-M" + module + "=" + source, "-femit-bin=" + str(target)])
            if target.exists():
                target.chmod(0o555)
        result["executables"] = {p.name: {"path": str(p), "sha256": digest(p)} for p in sorted(bin_dir.iterdir()) if p.is_file() and p.suffix != ".o"}
        full = not args.quick
        def suite(name, script, executable=binary, extra=()):
            report = artifacts / (name + ".json")
            return stage(name, [sys.executable, PACKAGE / script, "--binary", executable, "--bun", args.bun, "--report", report, *extra], report=report, binary=executable)
        suite("differential", "tests/differential.py", extra=("--programs", 5000 if full else 100, "--syntax", 1000 if full else 30, "--traces", 100 if full else 5, "--edit-traces", 100 if full else 5, "--oracle-timeout", args.oracle_timeout, "--no-shrink"))
        suite("input", "tests/differential_input.py", extra=("--cases", 1000 if full else 30))
        suite("inference", "tests/differential_inference.py", bin_dir / "inference-runner", ("--programs", 1000 if full else 50, "--scopes", 300 if full else 10))
        suite("pretty", "tests/differential_pretty.py", bin_dir / "pretty-runner", ("--programs", 1000 if full else 50, "--unicode-records", 300 if full else 20))
        suite("resume", "tests/differential_resume.py", bin_dir / "pretty-runner", ("--programs", 300 if full else 20))
        suite("source-metadata", "tests/differential_source.py", bin_dir / "source-runner", ("--programs", 1000 if full else 50, "--contexts", 300 if full else 20))
        for name, runner, count in (("patterns", "patterns-runner", 2000), ("computer", "computer-runner", 1000), ("effect_cast", "effect-cast-runner", 2000), ("hub", "hub-runner", 1000)):
            suite(name, "tests/differential_" + name + ".py", bin_dir / runner, ("--cases", count if full else 30))
        suite("malformed-ir", "tests/malformed_ir.py", bin_dir / "evaluation-runner", ("--cases", 2000 if full else 50))
        for name, script, external, executable, extra in (
            ("http", "http/verify.py", REPO / "work/http-verification/result.json", bin_dir / "http-driver", ("--bun", args.bun)),
            ("git-read", "git/verify_native.py", REPO / "work/git-native-verification/result.json", binary, ("--protocol", "--objects", 100 if full else 20)),
            ("git-write", "git/verify_writes.py", REPO / "work/git-native-verification/writes.json", binary, ("--protocol",)),
        ):
            report = artifacts / (name + ".json")
            stage(name, [sys.executable, PACKAGE / script, "--binary", executable, *extra], report=report, external_report=external, binary=executable)
        # All compilers and functional subprocesses have exited before these
        # actual key-to-render measurements and the final dispatch benchmark.
        for name, script, extra in (("pty", "tests/pty_parity.py", ("--cast", artifacts / "parity.cast")), ("pty-hub", "tests/pty_hub.py", ("--bun", args.bun))):
            report = artifacts / (name + ".json")
            stage(name, [sys.executable, PACKAGE / script, "--binary", binary, "--gleam", args.gleam, "--report", report, *extra], report=report, binary=binary)
        if not args.skip_performance:
            suite("benchmark", "tests/benchmark.py", extra=("--iterations", 100 if full else 10, "--oracle", "--parity-report", artifacts / "differential.json", "--input-report", artifacts / "input.json", "--pty-report", artifacts / "pty.json", "--hub-report", artifacts / "pty-hub.json"))
        final_sources = source_manifest()
        result["sources_unchanged"] = original_sources == final_sources
        result["source_changes"] = sorted(key for key in original_sources.keys() | final_sources.keys() if original_sources.get(key) != final_sources.get(key))
        result["binary_unchanged"] = all(Path(item["path"]).exists() and digest(Path(item["path"])) == item["sha256"] for item in result["executables"].values())
        result["oracle_build_unchanged"] = built == {str(p.relative_to(compiled_oracle)): digest(p) for p in sorted(compiled_oracle.rglob("*.mjs"))}
        result["oracle_sources_unchanged"] = all(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip() == expected and subprocess.run(["git", "diff", "--quiet", "HEAD", "--"], cwd=checkout).returncode == 0 for checkout, expected in ((ORACLE, ORACLE_SHA), (REPO / "work/oracle-real-world", REAL_SHA)))
        result["passed"] = all(s["passed"] for s in result["stages"]) and not result["known_oracle_gaps"] and result["sources_unchanged"] and result["binary_unchanged"] and result["oracle_build_unchanged"] and result["oracle_sources_unchanged"] and result["release_fast_build"]
        result["qualified"] = result["passed"] and full and not args.skip_performance
        result["status"] = "complete"
    except Exception as error:
        result["error"] = repr(error)
        result["status"] = "interrupted"
    finally:
        result["seconds"] = round(time.monotonic() - started, 3)
        write_json(args.report, result)
    print(json.dumps({"report": str(args.report), "passed": result["passed"], "qualified": result["qualified"], "status": result["status"], "failed_stages": [s["name"] for s in result["stages"] if not s["passed"]], "known_oracle_gaps": result["known_oracle_gaps"]}, ensure_ascii=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
