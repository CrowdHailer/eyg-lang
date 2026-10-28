#!/usr/bin/env python3
"""Controlled ablations of Git source and allocation kernels. No canonical changes."""
from pathlib import Path
import argparse,datetime,hashlib,json,math,os,platform,random,statistics,subprocess,time
P=Path(os.environ.get('EYG_SLIDES_PACKAGE',Path(__file__).resolve().parents[3])); W=P/'work/slides/git'; REPO=P.parent.parent
PIN='f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def summary(ns):
 x=sorted(ns); n=len(x)
 return {'samples':n,'p50_ms':statistics.median(x)/1e6,'p95_ms':x[math.ceil(n*.95)-1]/1e6,'p99_ms':x[math.ceil(n*.99)-1]/1e6,'max_ms':max(x)/1e6,'min_ms':min(x)/1e6}
class Driver:
 def __init__(self,name):self.name=name;self.p=subprocess.Popen([str(W/name/'driver')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
 def call(self,req):
  start=time.perf_counter_ns();self.p.stdin.write(json.dumps(req)+'\n');self.p.stdin.flush();line=self.p.stdout.readline();end=time.perf_counter_ns()
  assert line,(self.name,self.p.poll());x=json.loads(line);assert 'result' in x,(self.name,x)
  return x['result'],x['duration_ns'],end-start
 def close(self):self.p.stdin.close();assert self.p.wait(timeout=10)==0
class Kernel:
 def __init__(self,name):self.p=subprocess.Popen([str(W/name)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
 def call(self,op):
  self.p.stdin.write(op+'\n');self.p.stdin.flush();x=json.loads(self.p.stdout.readline());assert x['validated'];return x.get('sha1') or x['bytes'],x['duration_ns'],x['duration_ns']
 def close(self):self.p.stdin.close();assert self.p.wait(timeout=10)==0

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--samples',type=int,default=40);args=ap.parse_args();rng=random.Random(0x455947)
 variants=json.loads((W/'variants.json').read_text())
 if (W/'extra-variant.json').exists():variants.update(json.loads((W/'extra-variant.json').read_text()))
 for name, item in variants.items():
  assert sha(W/name/'driver')==item['binary_sha256'],name
  assert sha(W/name/'git.zig')==item['git_sha256'],name
  assert sha(W/name/'git_write.zig')==item['git_write_sha256'],name
 drivers={};kernels={};cases=[];report={'recordedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'kind':'controlled source ablation, not historical release comparison','platform':platform.platform(),'logicalCpus':os.cpu_count(),'zig':'0.14.1','mode':'ReleaseFast','pin':PIN,'osCaches':'warm','clocks':{'engine':'std.time.nanoTimestamp difference (wall CLOCK_REALTIME), no clock correction assumed during short pairs','roundtrip':'Python time.perf_counter_ns monotonic','kernels':'std.time.Timer monotonic'},'timing':'standalone driver nanosecond timer around git.request after JSON parse and before serialization; fresh Repository + arena each request. Kernels separately labelled. All raw samples retained.','sourceVariants':variants,'results':cases}
 def driver(name):
  if name not in drivers:drivers[name]=Driver(name)
  return drivers[name]
 def kernel(name):
  if name not in kernels:kernels[name]=Kernel(name)
  return kernels[name]
 def compare(name,before,after,request,mechanism,*,kernel_case=False,workload=None):
  before_e=[];after_e=[];before_w=[];after_w=[];values=[];order=[]
  for _ in range(3):
   bx,_,_=before();ax,_,_=after();assert bx==ax,(name,'warmup mismatch')
  for i in range(args.samples):
   fns=[('before',before),('after',after)];rng.shuffle(fns);pair={};order.append([k for k,_ in fns])
   for label,fn in fns:pair[label]=fn()
   assert pair['before'][0]==pair['after'][0],(name,'mismatch',i)
   values.append(pair['after'][0])
   before_e.append(pair['before'][1]);after_e.append(pair['after'][1]);before_w.append(pair['before'][2]);after_w.append(pair['after'][2])
  x={'name':name,'mechanism':mechanism,'request':request,'workload':workload,'kernel':kernel_case,'before':summary(before_e),'after':summary(after_e),'median_speedup':statistics.median(before_e)/statistics.median(after_e),'before_samples_ns':before_e,'after_samples_ns':after_e,'randomized_pair_order':order,'result_equality':True,'result_value':values[0] if kernel_case else None}
  if not kernel_case:x.update(before_roundtrip=summary(before_w),after_roundtrip=summary(after_w),before_roundtrip_samples_ns=before_w,after_roundtrip_samples_ns=after_w)
  cases.append(x);(W/'ablation-results.json').write_text(json.dumps(report,indent=2)+'\n');print(name,json.dumps({'before':x['before'],'after':x['after'],'median_speedup':x['median_speedup']}),flush=True)
 try:
  base={'repo':str(REPO),'ref':PIN,'action':'history','limit':20}
  # Confirm the canonical variant returns independent Git first-parent IDs.
  expected=subprocess.check_output(['git','-C',str(REPO),'rev-list','--first-parent','--max-count=20',PIN],text=True).splitlines()
  assert [c['id'] for c in driver('current').call(base)[0]]==expected
  for name,variant,req,mechanism in [
   ('decoded-object-cache','no_object_cache',base|{'action':'query','path':'README.md','limit':20,'scan_limit':200},'Remember decoded immutable objects under OID and pack-offset keys; re-use parent/tree/delta bases within a request.'),
   ('lazy-index-load','reload_indexes',base,'Load and SHA-check pack indexes once per Repository instead of on every packed-object lookup.'),
   ('binary-index-search','linear_index',base,'Use first-byte fanout and binary search instead of scanning the complete sorted object-ID table.'),
   ('fanout-bounds','no_fanout',base,'Use first OID byte to bound binary search to its 1/256 index bucket instead of searching the complete table.'),
   ('cheap-filters-first','path_before_metadata',base|{'action':'query','path':'dark/git/read.eyg','author':'__absent_slide_probe__','scan_limit':100},'Reject by timestamp/message/author before loading current and parent path trees.'),
   ('stop-at-result-limit','scan_after_limit',base,'Stop traversal once 20 matching records exist instead of scanning the remaining 430-commit first-parent history.'),
  ]:
   compare(name,lambda variant=variant,req=req:driver(variant).call(req),lambda req=req:driver('current').call(req),req,mechanism)
  packed_pin=subprocess.check_output(['git','-C',str(REPO),'rev-parse',PIN+'~20'],text=True).strip()
  packed_req=base|{'ref':packed_pin,'limit':3}
  compare('stream-packed-objects',lambda:driver('whole_pack_read').call(packed_req),lambda:driver('current').call(packed_req),packed_req,'Seek to object offset and let buffered zlib decode only that stream instead of reading the entire pack into each object call.',workload='Three packed commit records at pinned first-parent ancestor20, including any delta bases. Same object checksums and output.')
  compare('delta-output-preallocation',lambda:kernel('kernel-no-prealloc').call('d'),lambda:kernel('kernel-current').call('d'),None,'Read delta target length and reserve output capacity once, avoiding successive reallocations and copies.',kernel_case=True,workload='1MiB base and target, 64 indexed 16KiB copy operations; includes allocation, delta application and equality check.')
  phrase=b'let commit = {tree: tree, author: author, message: message}\n'; body=(phrase*((1048576+len(phrase)-1)//len(phrase)))[:1048576]
  assert kernel('kernel-current').call('i')[0]==hashlib.sha1(b'blob 1048576\0'+body).hexdigest()
  compare('incremental-object-hash',lambda:kernel('kernel-current').call('h'),lambda:kernel('kernel-current').call('i'),None,'Feed kind/size/NUL/body incrementally to SHA-1 instead of constructing an extra full header-plus-body buffer.',kernel_case=True,workload='SHA-1 over blob 1048576 NUL plus 1MiB body; allocation and copy included in concatenate baseline.')
  # Compression sizes differ. The kernel validates every decompressed result against its source after stopping its timer.
  # The speed comparison preserves timing outputs while comparing decompressed byte counts.
  kc=kernel('kernel-current'); sizes={}
  def comp(op):
   size,ns,wall=kc.call(op);sizes[op]=size;return 1048576,ns,wall
  compare('fast-write-compression-kernel',lambda:comp('c'),lambda:comp('f'),None,'Zig .fast is deflate level 4 (shorter match search), while .default is level 6. Trade compression work against encoded bytes.',kernel_case=True,workload='Compress 1MiB repeated realistic source phrase, output allocated in arena. Excludes filesystem and fsync.')
  cases[-1]['encoded_bytes']={'before_default':sizes['c'],'after_fast':sizes['f']}
  # Fresh loose writes include SHA, compression, file fsync and rename, but no process startup.
  write_repo=W/'write-fixture';write_repo.mkdir(exist_ok=True)
  if not (write_repo/'HEAD').exists():subprocess.run(['git','init','--bare','-q',str(write_repo)],check=True)
  write_text=body.decode();oid=hashlib.sha1(f'blob {len(body)}\0'.encode()+body).hexdigest();object_file=write_repo/'objects'/oid[:2]/oid[2:]
  write_request={'repo':str(write_repo),'action':'write_blob','text':write_text}
  write_sizes={}
  def fresh_write(variant):
   object_file.unlink(missing_ok=True)
   response=driver(variant).call(write_request)
   assert response[0]==oid
   write_sizes[variant]=object_file.stat().st_size
   return response
  compare('fast-write-compression-end-to-end',lambda:fresh_write('default_write_compression'),lambda:fresh_write('current'),write_request|{'text':'<1MiB fixture from source phrase>'},'Reduce zlib search level from default6 to fast4; measure full immutable-object write including fsync.',workload='1MiB text fixture, OS cache warm, target object removed before each timed request. Timer excludes test setup and JSON parse.')
  cases[-1]['encoded_bytes']={'before_default':write_sizes['default_write_compression'],'after_fast':write_sizes['current']}
  # Existing immutable object reuse follows the normal verification path instead of publishing again.
  existing_repo=W/'existing-fixture';existing_repo.mkdir(exist_ok=True)
  if not (existing_repo/'HEAD').exists():subprocess.run(['git','init','--bare','-q',str(existing_repo)],check=True)
  existing_request=write_request|{'repo':str(existing_repo)}
  assert driver('current').call(existing_request)[0]==oid
  compare('existing-object-write-reuse',lambda:fresh_write('current'),lambda:driver('current').call(existing_request),write_request|{'text':'<1MiB fixture from source phrase>'},'If the content-addressed object exists, read and verify it instead of compressing, syncing and renaming another copy.',workload='Same1MiB body. Before removes target before each request. After keeps identical valid object; both compute the requested object SHA first.')
  cases[-1]['after_request']=existing_request|{'text':'<1MiB fixture from source phrase>'}
  report['sourceSha256']={f:sha(P/'src'/f) for f in ['git.zig','git_write.zig','git_config.zig']}
  report['harnessSha256']=sha(Path(__file__));report['kernelSha256']=sha(W/'kernel.zig');report['kernelBinaries']={x:sha(W/x) for x in ['kernel-current','kernel-no-prealloc']}
  report['sourceChanges']=[f for f,h in report['sourceSha256'].items() if h!=sha(W/'current'/f)]
  report['sourceUnchanged']=not report['sourceChanges']
  assert report['sourceUnchanged']
  report['completedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat();(W/'ablation-results.json').write_text(json.dumps(report,indent=2)+'\n')
 finally:
  for p in [*drivers.values(),*kernels.values()]:p.close()
if __name__=='__main__':main()
