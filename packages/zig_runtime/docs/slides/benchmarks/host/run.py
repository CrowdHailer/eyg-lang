#!/usr/bin/env python3
"""Controlled host probes; synthetic IO delay is explicitly labelled, never a device/UI claim."""
from pathlib import Path
import argparse,contextlib,datetime,hashlib,http.server,json,math,os,platform,select,signal,statistics,subprocess,threading,time
HERE=Path(__file__).resolve().parent
ROOT=next(p for p in HERE.parents if (p/'packages/zig_runtime/src').is_dir())

def stats(xs):
 ys=sorted(xs)
 return {'samples':len(ys),'p50_ms':statistics.median(ys)/1e6,'p95_ms':ys[math.ceil(len(ys)*.95)-1]/1e6,'p99_ms':ys[math.ceil(len(ys)*.99)-1]/1e6,'max_ms':max(ys)/1e6}

def signal_probe():
 results={}
 for variant in ['periodic-100ms','self-pipe']:
  latencies=[];poll_intervals=[]
  for _ in range(20):
   read_fd,write_fd=os.pipe();os.set_blocking(read_fd,False);sent=[]
   def handler(*_):
    if variant=='self-pipe':os.write(write_fd,b'r')
   old=signal.signal(signal.SIGWINCH,handler)
   def send():
    time.sleep(.005);sent.append(time.perf_counter_ns());os.kill(os.getpid(),signal.SIGWINCH)
   worker=threading.Thread(target=send);worker.start();start=time.perf_counter_ns()
   select.select([read_fd] if variant=='self-pipe' else [],[],[],.100)
   end=time.perf_counter_ns();worker.join();signal.signal(signal.SIGWINCH,old);os.close(read_fd);os.close(write_fd)
   assert sent and end>=sent[0]
   latencies.append(end-sent[0]);poll_intervals.append(end-start)
  results[variant]={'passed':True,'signal_to_poll_return_ns':latencies,'signal_to_poll_return':stats(latencies),'poll_intervals_ns':poll_intervals}
 return {'kind':'controlled OS host probe; Python select + actual SIGWINCH/self-pipe; not native TUI or physical-display latency','configured_poll_ms':100,'signal_after_ms':5,'variants':results}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',type=Path,default=HERE/'host-probe');ap.add_argument('--output',type=Path,default=HERE/'results.json');args=ap.parse_args()
 requests=[]
 class Handler(http.server.BaseHTTPRequestHandler):
  def log_message(self,*_):pass
  def do_GET(self):
   started=time.perf_counter_ns();time.sleep(.020)
   body=b'{"0":"i","v":42}'
   assert self.path.startswith('/modules/'),self.path
   self.send_response(200);self.send_header('Content-Length',str(len(body)));self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
   requests.append({'path':self.path,'elapsed_ns':time.perf_counter_ns()-started})
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start();origin=f'http://127.0.0.1:{server.server_port}'
 cases=[('cooperative','sync'),('cooperative','slice'),('cooperative','every-step'),('git','sync',str(ROOT)),('git','worker',str(ROOT)),('hub','sync',origin),('hub','worker',origin),('cache','cold'),('cache','warm'),('refresh','always'),('refresh','miss')]
 all_results={};env={**os.environ,'NO_PROXY':'127.0.0.1,localhost','no_proxy':'127.0.0.1,localhost'}
 try:
  for case in cases:
   run=subprocess.run([str(args.binary.resolve()),*case],cwd=ROOT,env=env,text=True,capture_output=True,timeout=60)
   if run.returncode:raise RuntimeError(f'{case} failed {run.returncode}: {run.stderr}')
   result=json.loads(run.stdout);assert result['passed']
   for key in ['samples_ns','blocking_samples_ns','completion_samples_ns','total_samples_ns']:
    if key in result:result[key.replace('_samples_ns','_statistics').replace('samples_ns','statistics')]=stats(result[key])
   all_results['/'.join(case[:2])]=result
   print('/'.join(case[:2]),{k:v for k,v in result.items() if k.endswith('statistics') or k in ['timed_requests','known_lookup_requests','new_name_incremental_requests','repeat_known_requests']},flush=True)
  assert all_results['git/sync']['result_json']==all_results['git/worker']['result_json']
  for name in ['git/sync','git/worker']:
   r=all_results[name];r['result_json_sha256']=hashlib.sha256(r.pop('result_json').encode()).hexdigest()
  assert all_results['cache/cold']['timed_requests']==20 and all_results['cache/warm']['timed_requests']==0
  assert all_results['refresh/always']['known_lookup_requests']==20 and all_results['refresh/miss']['known_lookup_requests']==0
  for name in ['refresh/always','refresh/miss']:assert all_results[name]['new_name_incremental_requests']==2 and all_results[name]['repeat_known_requests']==0
  assert len(requests)==40,len(requests)
  resize=signal_probe()
 finally:server.shutdown();server.server_close();thread.join()
 report={'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'passed':True,'target':'controlled Linux x86_64 host probes; no physical UI or Android device claim','machine':{'platform':platform.platform(),'cpus':os.cpu_count()},'binary_sha256':hashlib.sha256(args.binary.read_bytes()).hexdigest(),'source_manifest':json.loads((HERE/'source-manifest.json').read_text()),'measurement':{'cooperative':'each evaluator call blocking interval, and total evaluation+resumptions; parsing and arena cleanup excluded','git':'synchronous effect return versus worker start acknowledgment; both inject20ms before the same realGit history request; completion measured separately','hub':'same verified42 module through localHTTP with20ms response delay; synchronous resolution versus worker-start acknowledgment; completion includes merge and module evaluation','cache':'warmup outside timer; cold control clears module source/value cache every lookup; fixtureGET has2ms delay; same sum1500 puremodule result','refresh':'always-refresh control versus production known-name lookup; fixtureGET2ms; new-name miss separately verifies cursor5→6, two requests and no repeat-known requests','resize':'controlled actualSIGWINCH/select/selfpipe probe;100ms periodic polling control and5ms delayed signal; not nativeTUI measurement'},'cases':all_results,'http_fixture':{'response_delay_ms':20,'requests':requests},'resize':resize,'reproduce':{'prepare':'python3 prepare.py','build':'zig build-exe -OReleaseFast host_probe.zig --global-cache-dir .global-cache --cache-dir .zig-cache -femit-bin=host-probe','run':'python3 run.py'}}
 args.output.write_text(json.dumps(report,indent=2)+'\n');print('saved',args.output,flush=True)
if __name__=='__main__':main()
