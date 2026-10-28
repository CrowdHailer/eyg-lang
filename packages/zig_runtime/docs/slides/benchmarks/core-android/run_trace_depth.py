from pathlib import Path
import argparse,json,subprocess,hashlib
def find_package_root():
    for ancestor in Path(__file__).resolve().parents:
        if (ancestor / 'src/interpreter.zig').is_file() and (ancestor / 'build.zig').is_file():
            return ancestor
    raise SystemExit('Cannot locate Zig runtime package. Pass --package-root explicitly.')

parser=argparse.ArgumentParser()
parser.add_argument('--package-root',type=Path,default=None)
parser.add_argument('--work-dir',type=Path)
args=parser.parse_args()
if args.work_dir is not None: args.work_dir=args.work_dir.resolve()
p=args.work_dir or (args.package_root or find_package_root()).resolve()/'work/slides/android'
report={'kind':'untimed structural observation at identical unhandled effect','workload':'1000 tail calls accumulate sum500500, perform Probe(sum), resume42','note':'Arena capacity is total retained allocation capacity, not live continuation-chain bytes. No time or memory speedup is inferred from this single observation.','variants':{}}
for variant in ['no-tail-trace','optimized']:
 result=json.loads(subprocess.check_output([str(p/variant/'trace-depth')],text=True));result['binary_sha256']=hashlib.sha256((p/variant/'trace-depth').read_bytes()).hexdigest();report['variants'][variant]=result
(p/'trace-depth.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
