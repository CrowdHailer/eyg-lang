#!/usr/bin/env python3
"""Build and run utility ablations; isolate CPU workloads before measuring."""
from pathlib import Path
import argparse, datetime, subprocess, sys
from prepare import prepare

ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--root',type=Path,help='packages/zig_runtime directory')
ap.add_argument('--output',type=Path,help='scratch output directory')
ap.add_argument('--zig',type=Path,help='Zig0.14.1 executable; defaults to package scripts/zig')
ap.add_argument('--build-only',action='store_true')
ap.add_argument('--measure-only',action='store_true')
args=ap.parse_args()
root=args.root
if root is None:
    root=next((p for p in Path(__file__).resolve().parents if (p/'src/interpreter.zig').is_file() and (p/'build.zig').is_file()),None)
if root is None:ap.error('Pass --root /path/to/packages/zig_runtime')
root=root.resolve()
out=(args.output or root/'work/slides/utility-reproduced'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')).resolve()
out.mkdir(parents=True,exist_ok=True)
binary=out/'util-bench'
if not args.measure_only:
    prepare(root,out)
    zig=(args.zig or root/'scripts/zig').resolve()
    subprocess.run([str(zig),'build-exe',str(out/'src/util_bench.zig'),'-OReleaseFast','-lc',f'-femit-bin={binary}','--cache-dir',str(out/'zig-cache'),'--global-cache-dir',str(out/'global-cache')],cwd=root,check=True)
if not args.build_only:
    with (out/'validation.txt').open('w') as f:subprocess.run([str(binary),'verify'],stdout=f,check=True)
    with (out/'raw.json').open('w') as f:subprocess.run([str(binary)],stdout=f,check=True)
    subprocess.run([sys.executable,str(Path(__file__).with_name('summarize.py')),str(out)],check=True)
print(out)
