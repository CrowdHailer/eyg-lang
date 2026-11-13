#!/usr/bin/env python3
"""Contemporaneous native and pinned-real-world history measurements.
Query times include fresh native Repository/index setup and SHA-1 validation.
OS caches are warm; no cold-disk or persistent decoded-cache claims are made.
"""
import argparse,hashlib,json,math,os,platform,statistics,subprocess,time
from pathlib import Path
from verify_native import ROOT,Native,git

def percentile(samples,p): return sorted(samples)[max(0,math.ceil(len(samples)*p)-1)]
def summary(samples): return dict(samples=len(samples),min_ms=round(min(samples),4),p50_ms=round(statistics.median(samples),4),p95_ms=round(percentile(samples,.95),4),p99_ms=round(percentile(samples,.99),4),max_ms=round(max(samples),4))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',default=str(ROOT/'work/git-native'));ap.add_argument('--protocol',action='store_true');ap.add_argument('--repo',default=str(ROOT));ap.add_argument('--repeat',type=int,default=100);ap.add_argument('--count',type=int,default=20);ap.add_argument('--gleam-repeat',type=int,default=3);ap.add_argument('--skip-gleam',action='store_true');args=ap.parse_args()
 repo=Path(args.repo);expected=git(repo,'rev-list','--first-parent',f'--max-count={args.count}','HEAD').decode().splitlines()
 native=Native(args.binary,args.protocol);times=[];engine_times=[]
 try:
  for _ in range(args.repeat):
   start=time.perf_counter_ns();rows=native.call(repo,'history',limit=args.count);elapsed=(time.perf_counter_ns()-start)/1e6
   assert [c['id'] for c in rows]==expected
   times.append(elapsed)
   if native.last_duration_ns is not None:engine_times.append(native.last_duration_ns/1e6)
 finally:native.close()
 result=dict(repo=str(repo),count=len(expected),native_roundtrip=summary(times),native_includes=['JSONL roundtrip','repository and pack-index setup','zlib decoding','SHA-1 object and index checks','full structured commit records'],cache='OS file caches warm; native decoded cache starts empty each query',platform=platform.platform(),logical_cpus=os.cpu_count(),binary_sha256=hashlib.sha256(Path(args.binary).read_bytes()).hexdigest())
 if engine_times:result['native_engine']=summary(engine_times)
 if not args.skip_gleam:
  oracle=ROOT/'work/oracle-real-world';binary=oracle/'packages/gleam_cli/dist/eyg'
  source=f'''let git = import {json.dumps(str(oracle/'dark/git/index.eyg'))}
let list = import {json.dumps(str(oracle/'dark/shell/stream.eyg'))}
let run = (_) -> {{
  let start = perform Now({{}})
  let records = list.take({args.count},git.commits({json.dumps(str(repo))}))
  let end = perform Now({{}})
  let _ = perform StandardOut(!string_append(!int_to_string(!int_subtract(end,start)),"\\n"))
  !list_fold(records,{{}},(c,_) -> {{ perform StandardOut(!string_append(c.id,"\\n")) }})
}}
let _ = run({{}})
run({{}})'''
  cold=[];warm=[];process=[]
  for _ in range(args.gleam_repeat):
   start=time.perf_counter();run=subprocess.run([str(binary),'run','-c',source],capture_output=True,text=True,cwd=repo,timeout=60);elapsed=(time.perf_counter()-start)*1000
   assert run.returncode==0,(run.stdout,run.stderr)
   lines=run.stdout.splitlines();size=len(expected)+1
   assert len(lines)==size*2 and lines[1:size]==expected and lines[size+1:]==expected,run.stdout
   cold.append(int(lines[0]));warm.append(int(lines[size]));process.append(elapsed)
  result.update(oracle_commit='f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9',gleam_cold_query=summary(cold),gleam_warm_query=summary(warm),gleam_fresh_process=summary(process))
 out=ROOT/'work/git-native-verification';out.mkdir(parents=True,exist_ok=True);(out/('benchmark-native.json' if args.skip_gleam else 'benchmark.json')).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
