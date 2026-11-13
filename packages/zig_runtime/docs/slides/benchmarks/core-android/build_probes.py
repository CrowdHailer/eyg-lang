from pathlib import Path
import subprocess,concurrent.futures,time,argparse,json
def find_package_root():
    for ancestor in Path(__file__).resolve().parents:
        if (ancestor / 'src/interpreter.zig').is_file() and (ancestor / 'build.zig').is_file():
            return ancestor
    raise SystemExit('Cannot locate Zig runtime package. Pass --package-root explicitly.')

parser=argparse.ArgumentParser()
parser.add_argument('--package-root',type=Path,default=None)
parser.add_argument('--work-dir',type=Path)
parser.add_argument('--variant',action='append')
parser.add_argument('--jobs',type=int,default=2)
parser.add_argument('--trace-depth',action='store_true')
args=parser.parse_args()
if args.work_dir is not None: args.work_dir=args.work_dir.resolve()
root=(args.package_root or find_package_root()).resolve();out=args.work_dir or root/'work/slides/android'
def build(name):
 t=time.monotonic();d=out/name;optimization='Debug' if name=='optimized-debug' else 'ReleaseFast'
 source='trace_depth.zig' if args.trace_depth else 'driver.zig'
 binary='trace-depth' if args.trace_depth else 'probe'
 command=[str(root/'scripts/zig'),'build-exe','-O'+optimization,str(d/source),'-femit-bin='+str(d/binary)]
 r=subprocess.run(command,cwd=root,text=True,capture_output=True)
 (d/'build.log').write_text(r.stdout+r.stderr)
 (d/'build-command.json').write_text(json.dumps(command,indent=2)+'\n')
 return {'variant':name,'optimization':optimization,'exit':r.returncode,'seconds':round(time.monotonic()-t,2),'error':r.stderr[-1800:] if r.returncode else None}
with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
 results=list(pool.map(build,args.variant or ['optimized','no-i64','no-tail-trace','no-ir-identity','linear-builtins','optimized-debug']))
 for r in results:print(r,flush=True)
 if any(r['exit'] for r in results):raise SystemExit(1)
