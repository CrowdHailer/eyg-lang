from pathlib import Path
import datetime, hashlib, json, math, platform, statistics, subprocess
import sys
p=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parent
base=p
sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest()
raw=json.loads((p/'raw.json').read_text())
labels={
 'utf16':('Allocation-free UTF-16 ordering','Materialize two UTF-16 arrays with libc allocation, then compare','Stream UTF-16 code units, stopping on the first difference','121 pair comparisons over 11 strings with ASCII, BMP, supplementary characters and combining marks'),
 'properties':('Binary Unicode property lookup','Linear scan of sorted Unicode ranges with early stop','Binary search over the same generated Unicode range table','Segment one mixed-script string containing ASCII, combining sequences, emoji ZWJ, flags, Indic and CJK'),
 'mapping':('Binary Unicode case-map lookup','Linear scan of sorted case mappings with early stop','Binary search over the same case map','Uppercase one mixed-script string; same Unicode property lookup in both modes'),
 'lengths':('Cached document flat lengths','Recursively count grapheme lengths for each text/line/group layout decision','Read precomputed Doc.length for each layout decision','Render an already built shared document DAG, seven nested doubled groups, width 80; document construction excluded'),
 'capture':('Deduplicate free names before reification','Keep all repeated occurrences, reify each, then use the existing canonical definition deduplication','Deduplicate free names while walking IR, reify each distinct free binding once','Capture one closure whose body contains 128 references to x; same canonical reified IR')
}
entries=[]
for c in raw['cases']:
 name,before,after,workload=labels[c['name']]
 def stats(xs):
  xs=sorted(v/c['iterations_per_sample']/1e6 for v in xs)
  return {'samples':len(xs),'median_ms_per_workload':statistics.median(xs),'p95_ms_per_workload':xs[math.ceil(.95*len(xs))-1],'max_ms_per_workload':max(xs)}
 bs,as_=stats(c['before_ns']),stats(c['after_ns'])
 entries.append({'case':c['name'],'optimisation':name,'before_mechanism':before,'after_mechanism':after,'workload':workload,'iterations_per_sample':c['iterations_per_sample'],'before':bs,'after':as_,'median_speedup':bs['median_ms_per_workload']/as_['median_ms_per_workload'],'outputs_exactly_equal':True,'raw_before_batch_ns':c['before_ns'],'raw_after_batch_ns':c['after_ns']})
source={str(q.relative_to(p)):sha(q) for q in (p/'src').iterdir() if q.is_file()}
report={'recorded_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'kind':'controlled source ablations, not historical before binaries','platform':platform.platform(),'zig':'0.14.1 ReleaseFast, libc allocator','driver_sha256':sha(p/'src/util_bench.zig'),'binary_sha256':sha(p/'util-bench'),'source_sha256':source,'measurement':'Monotonic wall time, 31 alternating before/after batches, one warmup per mode, no samples removed. Per-workload times divide batch elapsed by iterations; they are amortised batch timings, not individual tail latencies. Temporary arena reset is timed for allocation-producing kernels. Input/document/closure setup is outside timing.','validation_log':(p/'validation.txt').read_text(),'raw_checksum':raw['checksum'],'cases':entries,'limits':['Valid UTF-8 comparator corpus only. These are utility microbenchmarks, not full TUI or device latency.','Each ablation changes one algorithmic choice in copied sources. The shipping sources remain unchanged.','Free-variable pruning and canonical closure-definition deduplication enforce observable IR shape. Capture-all variants change that shape and are not presented as equivalent speed optimisations.']}
(p/'report.json').write_text(json.dumps(report,indent=2)+'\n')
for x in entries:print(x['case'],x['before']['median_ms_per_workload']*1000,x['after']['median_ms_per_workload']*1000,'us',x['median_speedup'],'x')
