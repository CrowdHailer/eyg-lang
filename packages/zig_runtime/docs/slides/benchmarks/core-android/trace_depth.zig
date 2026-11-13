const std = @import("std");
const runtime = @import("src/interpreter.zig");
const parser = @import("src/parser.zig");
pub fn main() !void {
 var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit();
 const a=arena.allocator();
 const source="let sum = !fix((self, n, acc) -> { match !int_compare(n, 0) { Eq(_) -> { perform Probe(acc) } | (_) -> { self(!int_subtract(n, 1), !int_add(acc, n)) } } }) sum(1000, 0)";
 var engine=runtime.Engine.init(a);
 const ir=try parser.parse(a,source);
 _=engine.evalTrusted(ir) catch |err| {if(err!=error.Runtime)return err;};
 if(engine.failure==null or engine.failure.?!=.unhandled_effect)return error.ExpectedEffect;
 const effect=engine.failure.?.unhandled_effect;
 if(effect.value!=.integer or effect.value.integer!=500500)return error.UnexpectedResult;
 var k=engine.k;var count:usize=0;var trace_count:usize=0;
 while(k) |node| {count+=1;if(node.action==.trace)trace_count+=1;k=node.next;}
 const capacity=arena.queryCapacity();
 const result=try engine.@"resume"(.{.integer=42});
 if(result!=.integer or result.integer!=42)return error.UnexpectedResume;
 try std.io.getStdOut().writer().print("{{\"continuation_nodes\":{d},\"trace_nodes\":{d},\"arena_capacity_bytes_at_effect\":{d},\"effect_sum\":500500,\"resumed_result\":42}}\n",.{count,trace_count,capacity});
}
