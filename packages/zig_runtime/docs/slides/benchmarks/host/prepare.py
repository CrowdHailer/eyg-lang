from pathlib import Path
import shutil,json,hashlib,argparse
HERE=Path(__file__).resolve().parent
def default_root():
    return next(p for p in HERE.parents if (p/'packages/zig_runtime/src').is_dir())
ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=default_root());args=ap.parse_args()
ROOT=args.repo.resolve()
src=ROOT/'packages/zig_runtime/src'
shutil.copytree(src,HERE/'src',dirs_exist_ok=True)
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in src.iterdir() if p.is_file()}
p=HERE/'src/interpreter.zig';s=p.read_text();assert s.count('time_budget_ns: u64 = 0,')==1 and s.count('self.steps & 127 == 0')==1;s=s.replace('time_budget_ns: u64 = 0,','time_budget_ns: u64 = 0,\n    probe_clock_mask: usize = 127,',1);s=s.replace('self.steps & 127 == 0','self.steps & self.probe_clock_mask == 0',1);p.write_text(s)
p=HERE/'src/async_git.zig';s=p.read_text();assert s.count('pub const Worker = struct {')==1 and s.count('defer self.release();\n        if (git.request')==1;s=s.replace('pub const Worker = struct {','pub var probe_delay_ns: u64 = 0;\n\npub const Worker = struct {',1);s=s.replace('defer self.release();\n        if (git.request','defer self.release();\n        std.Thread.sleep(probe_delay_ns);\n        if (git.request',1);p.write_text(s)
(HERE/'source-manifest.json').write_text(json.dumps({'canonical_source_sha256':manifest,'scratch_only_changes':['interpreter.Engine.probe_clock_mask changes check frequency; default127 matches production','async_git.probe_delay_ns injects the same20ms fixture latency before git.request as synchronous control'],'patched_source_sha256':{n:hashlib.sha256((HERE/'src'/n).read_bytes()).hexdigest() for n in ['interpreter.zig','async_git.zig']}},indent=2)+'\n')
