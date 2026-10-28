#!/usr/bin/env python3
from pathlib import Path
import json,subprocess,time,hashlib,math,sys,platform,argparse
cli=argparse.ArgumentParser();cli.add_argument('--package',type=Path);cli.add_argument('--output',type=Path);cli.add_argument('--blocks',type=int,default=4);cli.add_argument('--iterations',type=int,default=5);cli.add_argument('--only');cli.add_argument('--profile',choices=['standard','large-context'],default='standard');args=cli.parse_args()
root=args.package.resolve() if args.package else next(p for p in Path(__file__).resolve().parents if (p/'build.zig').exists() and (p/'src/main.zig').exists())
out=args.output.resolve() if args.output else Path(__file__).resolve().parent
class Peer:
 def __init__(self,path):self.p=subprocess.Popen([str(path),'--protocol'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,cwd=root)
 def call(self,r):
  begin=time.perf_counter_ns();self.p.stdin.write((json.dumps(r,separators=(',',':'))+'\n').encode());self.p.stdin.flush();data=self.p.stdout.readline();received=time.perf_counter_ns();return json.loads(data),received-begin,len(data)
 def close(self):self.p.stdin.close();self.p.wait(timeout=10)
def stats(samples):
 s=sorted(samples)
 return {'samples':len(s),'p50_ms':s[math.ceil(len(s)*.5)-1]/1e6,'p95_ms':s[math.ceil(len(s)*.95)-1]/1e6,'p99_ms':s[math.ceil(len(s)*.99)-1]/1e6,'max_ms':max(s)/1e6,'mean_ms':sum(s)/len(s)/1e6,'breaches_10ms':sum(x>=10_000_000 for x in s)}
def paste(s):return {'paste':s}
def key(s):return {'key':s}
history=[]
for i in range(30):history+=[paste(f'!int_add({i}, 1)'),key('enter')]
# A retained value with enough structure that repeated layout has measurable work.
value='['+', '.join('{index: '+str(i)+', label: "EYG", payload: [1, 2, 3, 4]}' for i in range(50))+']'
nested='let data = {count: 42, items: [1, 2, 3], name: "EYG"} let {count, items} = data !list_fold(items, count, (x, total) -> { !int_add(x, total) })'
big='['+', '.join('{answer: !int_add('+str(i)+', 1), label: "EYG"}' for i in range(50))+']'
scope=[]
for i in range(35):scope+=[paste('let item_'+str(i)+' = {answer: '+str(i)+', label: "EYG"} {}'),key('enter')]
analysis_source='['+', '.join('item_'+str(i)+'.answer' for i in range(35))+']'
cases=[
 ('cell_interning','no_cell_intern',{'op':'bench_static','events':[]},'Identical cells share immutable JSON cell maps. Empty 80x24 frame, repeated full frame snapshot.'),
 ('cell_array_reservation','no_cell_reserve',{'op':'bench_static','events':[]},'Reserve the known cell count rather than repeatedly grow the cell-value array.'),
 ('frame_allocation_lifetime','retained_frames',{'op':'bench_static','events':history+[paste(nested)]},'Before retains temporary layout plus output in session storage. After uses scratch and caller-owned resettable output. Both include output reset and paired clock reads.'),
 ('unused_annotation_walks','dead_annotation_walks',{'op':'bench_static','events':history+[paste(big)]},'Before restores applyInfo to draft plus clearAnnotations on all history trees. Legacy fields exist in both states, isolating tree-walk cost and excluding Node-size savings.'),
 ('draft_analysis_cache','no_analysis_cache',{'op':'bench_static','events':[paste(big)]},'Hash editable draft and scope identity. Reuse prior analysis when neither changed.'),
 ('history_value_pretty_cache','no_history_cache',{'op':'bench_static','events':[paste(value),key('enter')]},'Immutable evaluated value is formatted once per viewport width.'),
 ('immutable_scope_cache','no_scope_cache',{'op':'bench_analysis','events':scope,'source':analysis_source},'Freeze immutable runtime scope type environment by identity, then clone it for each fresh inference run.'),
 ('rendered_type_memoization','no_type_text_cache',{'op':'bench_analysis','events':scope,'source':analysis_source},'Reuse rendered type text by resolved type pointer during one analysis.'),
 ('rendered_scope_memoization','no_scope_text_cache',{'op':'bench_analysis','events':scope,'source':analysis_source},'Reuse repeated completion scope text by immutable environment pointer during one analysis.'),
 ('omit_unused_scope_effect_projections','full_analysis_projection',{'op':'bench_static','events':[paste(big)],'force_analysis':True},'Before builds per-node scope and effect text unused by ordinary rendering. After omits that projection, retaining required types/paths. Each sample forces fresh analysis on both sides.'),
 ('picker_query_casefold_once','repeat_casefold',{'op':'bench_static','events':[key('j'),key('s')]},'Case-fold picker query once per matching pass rather than once per candidate.'),
 ('ansi_style_change_elision','no_ansi_style_runs',{'op':'bench_ansi','events':[paste(nested)]},'Emit SGR changes only when style differs from previous visible cell. Before re-emits complete SGR for every cell.'),
]


if args.profile=='large-context':
 complex_scope=[]
 for i in range(5):complex_scope+=[paste('let item_'+str(i)+' = '+value+' {}'),key('enter')]
 repeated='['+', '.join('item_0' for _ in range(20))+']'
 selected={'immutable_scope_cache','rendered_type_memoization','omit_unused_scope_effect_projections'}
 adjusted=[]
 for name,flag,request,mechanism in cases:
  if name not in selected:continue
  request={**request,'events':complex_scope+([paste(repeated)] if name=='omit_unused_scope_effect_projections' else [])}
  if 'source' in request:request['source']=repeated
  adjusted.append((name,flag,request,mechanism+' Large-context regime: five retained50-record list values,20 references to the same complex value.'))
 cases=adjusted
result_name='results-large-context.json' if args.profile=='large-context' else 'results.json'

def main():
 p=Peer(out/'eyg-ablation');prod=Peer(root/'zig-out/bin/eyg')
 report={'created_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'profile':args.profile,'platform':platform.platform(),'binary_sha256':hashlib.sha256((out/'eyg-ablation').read_bytes()).hexdigest(),'production_sha256':hashlib.sha256((root/'zig-out/bin/eyg').read_bytes()).hexdigest(),'source_provenance':'source-provenance.json','timing_unit':{'bench_static':'Repeated complete frame construction + reset, no event dispatch. Setup outside samples.','bench_analysis':'Fresh inference with scope/effect projection and annotated TUI IR. Separate from key-to-frame target.','bench_ansi':'Repeated complete ANSI frame rendering + reset, no event dispatch. Setup outside samples.'},'method':'Same ReleaseFast executable; one runtime flag disables a single mechanism. AB and BA blocks alternate, no samples discarded. Each internal sample includes final frame/output-reset/paired-clock boundary; analysis-only and ANSI-only probes explicitly differ. Baseline contains restored unused Node fields to isolate traversal. This is an ablation benchmark, not chronological historical measurement.','cases':{},'parity':[]}
 try:
  for name,flag,request,mechanism in cases:
   if args.only and args.only!=name:continue
   # Output parity through the actual TUI transport, with identical seed/setup.
   check={'op':'tui','width':80,'height':24,'events':request['events']+([paste(request['source'])] if 'source' in request else [])}
   expected=prod.call(check)[0]
   base=p.call(check)[0];changed=p.call({**check,'ablation':flag})[0]
   ok=expected==base==changed
   report['parity'].append({'case':name,'all_frames_equal':ok,'states':len(expected.get('frames',[]))})
   if not ok:raise RuntimeError('frame parity '+name)
   for mode in ['',flag]:p.call({**request,'ablation':mode,'iterations':1,'width':80,'height':24})
   raws={'before':[],'after':[]};sizes={'before':[],'after':[]};blocks=[]
   for block in range(args.blocks):
    order=['before','after'] if block%2==0 else ['after','before']
    for label in order:
     mode=flag if label=='before' else ''
     got,roundtrip,_=p.call({**request,'ablation':mode,'iterations':args.iterations,'width':80,'height':24})
     if 'samples_ns' not in got:raise RuntimeError((name,got))
     raws[label]+=got['samples_ns'];sizes[label]+=got.get('sizes',[])
     blocks.append({'block':block,'condition':label,'roundtrip_ns':roundtrip,'samples':got['samples_ns']})
   summary={label:stats(ns) for label,ns in raws.items()}
   item={'flag':flag,'mechanism':mechanism,'request':request,'before':summary['before'],'after':summary['after'],'median_speedup':summary['before']['p50_ms']/summary['after']['p50_ms'],'samples_ns':raws,'sizes':sizes,'blocks':blocks,'parity':ok}
   if name=='frame_allocation_lifetime':
    item['session_capacity_growth_16_frames']={label:p.call({'op':'frame_memory','events':request['events'],'iterations':1,'ablation':flag if label=='before' else ''})[0]['sizes'][0] for label in ['before','after']}
   report['cases'][name]=item
   (out/result_name).write_text(json.dumps(report,indent=2)+'\n')
   print(name,json.dumps({k:item[k] for k in ['before','after','median_speedup']}),flush=True)
  if args.profile=='large-context' or (args.only and args.only!='buffered_jsonl_output'):return
  # JSON output buffering has a separate end-to-end pipe boundary.
  req={'op':'tui','width':80,'height':24,'events':[]}
  expect=p.call(req)[0]
  raw={'before':[],'after':[]};sizes={'before':[],'after':[]}
  for label in ['before','after']:p.call({**req,'ablation':'unbuffered_json' if label=='before' else ''})
  for block in range(args.blocks):
   for label in (['before','after'] if block%2==0 else ['after','before']):
    for _ in range(args.blocks):
     got,ns,size=p.call({**req,'ablation':'unbuffered_json' if label=='before' else ''})
     if got!=expect:raise RuntimeError('JSON byte buffering changed decoded output')
     raw[label].append(ns);sizes[label].append(size)
  item={'mechanism':'std.io.bufferedWriter batches JSON writes; baseline passes the identical JSON encoder directly to stdout. Timer starts before request bytes are written and stops on complete response newline, before json.loads. Includes pipe transport and encoding; excludes startup.','request':req,'before':stats(raw['before']),'after':stats(raw['after']),'samples_ns':raw,'response_bytes':sizes,'parity':True}
  item['median_speedup']=item['before']['p50_ms']/item['after']['p50_ms'];report['cases']['buffered_jsonl_output']=item
  (out/result_name).write_text(json.dumps(report,indent=2)+'\n')
  print('buffered_jsonl_output',json.dumps({k:item[k] for k in ['before','after','median_speedup']}),flush=True)
 finally:p.close();prod.close()

if __name__=='__main__':main()
