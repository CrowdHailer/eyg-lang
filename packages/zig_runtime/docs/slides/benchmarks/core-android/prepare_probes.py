from pathlib import Path
import shutil,re,json,hashlib,subprocess,os,argparse
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
root=(args.package_root or find_package_root()).resolve()
out=args.work_dir or root/'work/slides/android'
out.mkdir(parents=True,exist_ok=True)
src=(root/'src/interpreter.zig').read_text()
variants={'optimized':src,'optimized-debug':src,
 'no-i64':src.replace('return value == .integer and value.integer >= -safe_integer and value.integer <= safe_integer;','_ = value; return false;'),
 'no-tail-trace':src.replace('if (self.k) |previous| if (previous.action == .trace) {','if (self.k) |previous| if (false and previous.action == .trace) {'),
 'no-ir-identity':src.replace('if (left == .object and right == .object and left.object.keys().ptr == right.object.keys().ptr and left.object.count() == right.object.count()) return true;','// Controlled ablation: descend even when the IR map is identical.'),
}
old='''const builtinMap = blk: {
    var entries: [std.meta.fields(Builtin).len]struct { []const u8, Builtin } = undefined;
    for (std.meta.fields(Builtin), 0..) |f, i| entries[i] = .{ f.name, @enumFromInt(f.value) };
    break :blk std.StaticStringMap(Builtin).initComptime(entries);
};'''
new='''const builtinMap = struct {
    fn get(label: []const u8) ?Builtin {
        inline for (std.meta.fields(Builtin)) |f| {
            if (std.mem.eql(u8, label, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }
};'''
assert old in src
variants['linear-builtins']=src.replace(old,new)
driver='''const std = @import("std");
const interpreter = @import("src/interpreter.zig");
const parser = @import("src/parser.zig");
pub fn main() !void {
 const a=std.heap.page_allocator;
 const args=try std.process.argsAlloc(a);
 const input=try std.fs.cwd().readFileAlloc(a,args[1],1024*1024);
 const iterations=try std.fmt.parseInt(usize,args[2],10);
 var parse_arena=std.heap.ArenaAllocator.init(a); defer parse_arena.deinit();
 const ir=try parser.parse(parse_arena.allocator(), input);
 var execution=std.heap.ArenaAllocator.init(a); defer execution.deinit();
 var times=std.ArrayList(u64).init(a); defer times.deinit();
 var checksum: i64=0;
 for(0..iterations+10) |i| {
  _=execution.reset(.retain_capacity);
  var engine=interpreter.Engine.init(execution.allocator());
  var timer=try std.time.Timer.start();
  const result=try engine.evalTrusted(ir);
  const elapsed=timer.read();
  switch(result){.integer=>|x|checksum=x,.tagged=>|t|{if(!std.mem.eql(u8,t.label,"True"))return error.UnexpectedResult;checksum=1;},else=>return error.UnexpectedResult}
  if(i>=10) try times.append(elapsed);
 }
 var stdout=std.io.getStdOut().writer();
 try stdout.print("{{\\\"checksum\\\":{d},\\\"samples_ns\\\":",.{checksum});
 try std.json.stringify(times.items,.{},stdout);try stdout.writeAll("}\\n");
}
'''
# Fix the quoting in the Zig JSON prefix without relying on shell interpolation.
driver=driver.replace('\\\\\\"','\\"')
for name,source in variants.items():
 directory=out/name
 directory.mkdir(exist_ok=True)
 shutil.copytree(root/'src',directory/'src',dirs_exist_ok=True)
 (directory/'src/interpreter.zig').write_text(source)
 (directory/'driver.zig').write_text(driver)
 if name in ['optimized','no-tail-trace']:
  shutil.copyfile(Path(__file__).with_name('trace_depth.zig'),directory/'trace_depth.zig')
(out/'arithmetic.eyg').write_text('let sum = !fix((self, n, acc) -> { match !int_compare(n, 0) { Eq(_) -> { acc } | (_) -> { self(!int_subtract(n, 1), !int_add(acc, n)) } } }) sum(1000, 0)')
expr='x'
for _ in range(200):expr='!int_add(1, '+expr+')'
(out/'closure-equality.eyg').write_text('let f = (x) -> { '+expr+' } !equal(f, f)')
print(json.dumps({'variants':list(variants),'source_sha256':hashlib.sha256(src.encode()).hexdigest()}))
