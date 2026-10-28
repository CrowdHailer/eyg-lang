from pathlib import Path
import subprocess,json,random,statistics,hashlib,platform,time,os,argparse
def find_package_root():
    for ancestor in Path(__file__).resolve().parents:
        if (ancestor / 'src/interpreter.zig').is_file() and (ancestor / 'build.zig').is_file():
            return ancestor
    raise SystemExit('Cannot locate Zig runtime package. Pass --package-root explicitly.')

parser=argparse.ArgumentParser()
parser.add_argument('--package-root',type=Path,default=None)
parser.add_argument('--work-dir',type=Path)
parser.add_argument('--output',type=Path)
parser.add_argument('--debug-only',action='store_true')
args=parser.parse_args()
if args.work_dir is not None: args.work_dir=args.work_dir.resolve()
p=args.work_dir or (args.package_root or find_package_root()).resolve()/'work/slides/android'
def sha(f):return hashlib.sha256(Path(f).read_bytes()).hexdigest()
def stats(values):
 v=sorted(values);n=len(v)
 return {'samples':n,'p50_ms':statistics.median(v)/1e6,'p95_ms':v[min(n-1,int(n*.95))]/1e6,'p99_ms':v[min(n-1,int(n*.99))]/1e6,'max_ms':max(v)/1e6,'min_ms':min(v)/1e6}
experiments=[('native-i64','no-i64','arithmetic.eyg',500500),('tail-trace','no-tail-trace','arithmetic.eyg',500500),('ir-pointer-identity','no-ir-identity','closure-equality.eyg',1),('static-builtin-map','linear-builtins','arithmetic.eyg',500500)]
if args.debug_only: experiments=[('release-fast-build','optimized-debug','arithmetic.eyg',500500)]
rng=random.Random(20261028);report={'kind':'controlled source ablations, not historical release comparison','platform':platform.platform(),'cpu_count':os.cpu_count(),'affinity':sorted(os.sched_getaffinity(0)),'zig':'0.14.1','optimization':('Debug baseline / ReleaseFast production' if args.debug_only else 'ReleaseFast'),'core_boundary':'Engine.evalTrusted on already parsed IR, excludes parsing/process startup/JSON encoding; execution arena resets before timer and retains capacity. Ten warmup iterations per process. No samples filtered.','production_source_sha256':sha(p/'optimized/src/interpreter.zig'),'started_at_ns':time.time_ns(),'core':[]}
for name,baseline,program,expected in experiments:
 variants=[baseline,'optimized'];raw={x:[]for x in variants};order=[]
 for wave in range(3):
  rng.shuffle(variants)
  for variant in variants:
   command=[str(p/variant/'probe'),str(p/program),'100']
   value=json.loads(subprocess.check_output(command,text=True));assert value['checksum']==expected,(variant,program,value)
   raw[variant]+=value['samples_ns'];order.append({'wave':wave,'variant':variant,'samples':len(value['samples_ns'])})
 entry={'name':name,'baseline':baseline,'workload':program,'expected':expected,'program_sha256':sha(p/program),'source_sha256':{v:sha(p/v/'src/interpreter.zig')for v in raw},'binary_sha256':{v:sha(p/v/'probe')for v in raw},'build_configs':{v:('Debug' if v=='optimized-debug' else 'ReleaseFast') for v in raw},'raw_ns':raw,'order':order,'before':stats(raw[baseline]),'after':stats(raw['optimized'])}
 entry['median_speedup']=entry['before']['p50_ms']/entry['after']['p50_ms'];report['core'].append(entry)
 print(name,entry['before'],entry['after'],'speedup',entry['median_speedup'],flush=True)
lifecmd=None if args.debug_only else json.loads((p/'lifecycle/run.json').read_text());report['lifecycle']=[]
for workload,baseline in ([] if args.debug_only else [('active','join-active'),('idle','sync-idle-free')]):
 variants=[baseline,'optimized'];rng.shuffle(variants);raw={}
 for variant in variants:
  command=lifecmd+[variant,workload,'30'];value=json.loads(subprocess.check_output(command,text=True));assert value['verified'];raw[variant]=value['samples_ns']
 entry={'workload':workload,'baseline':baseline,'fixture':'NativeBackend deterministic 25ms release delay for active calls; deterministic 25ms destroy for idle cleanup. Actual production NativeSessions class vs a single-policy source ablation, runs on host JVM17 not Android.','raw_ns':raw,'before':stats(raw[baseline]),'after':stats(raw['optimized']),'production_kotlin_sha256':sha(p/'lifecycle/NativeSessions.kt')}
 entry['median_speedup']=entry['before']['p50_ms']/entry['after']['p50_ms'];report['lifecycle'].append(entry)
 print('lifecycle',workload,entry['before'],entry['after'],flush=True)
report['completed_at_ns']=time.time_ns();output=args.output or p/('debug-evidence.json' if args.debug_only else 'evidence.json');output.write_text(json.dumps(report,indent=2)+'\n');print('evidence',output)
