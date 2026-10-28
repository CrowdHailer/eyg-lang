#!/usr/bin/env python3
"""Build an isolated oracle at the exact next-tui revision used by the tests."""
from pathlib import Path
import os
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[3]
PIN = "be502aa03df926a8f9df474a0a7fe16c8fb14fbd"
ORACLE = REPO / "work/oracle-next-tui"


def run(*command, cwd=REPO, **kwargs):
    return subprocess.run(command, cwd=cwd, check=True, **kwargs)


if not ORACLE.exists():
    known = subprocess.run(["git", "cat-file", "-e", PIN + "^{commit}"], cwd=REPO, capture_output=True)
    if known.returncode:
        run("git", "fetch", "origin", PIN)
    ORACLE.parent.mkdir(exist_ok=True)
    run("git", "worktree", "add", "--detach", str(ORACLE), PIN)
observed = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ORACLE, text=True).strip()
if observed != PIN:
    raise SystemExit(f"refusing to use oracle {observed}; expected {PIN}")
dirty = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ORACLE, text=True).strip()
if dirty:
    raise SystemExit("refusing to use modified oracle sources: " + dirty)
target = ORACLE / "packages/gleam_cli"
cached = REPO / "packages/gleam_cli/build"
if cached.exists() and not (target / "build").exists():
    shutil.copytree(cached, target / "build")
env = dict(os.environ)
env["PATH"] = "/workspace/tooling/bin:" + env.get("PATH", "")
run("gleam", "build", "--target", "javascript", "--warnings-as-errors", cwd=target, env=env)
print(f"Gleam oracle ready: {PIN}")
