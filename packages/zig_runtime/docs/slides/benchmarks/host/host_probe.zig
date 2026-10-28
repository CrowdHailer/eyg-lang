const std = @import("std");
const runtime = @import("src/interpreter.zig");
const parser = @import("src/parser.zig");
const git = @import("src/git.zig");
const async_git = @import("src/async_git.zig");
const hub = @import("src/hub.zig");
const async_hub = @import("src/async_hub.zig");
const J = std.json.Value;
const A = std.mem.Allocator;
const repetitions: usize = 20;
const delay_ns: u64 = 20 * std.time.ns_per_ms;
const SumSource = "let sum = !fix((self, n) -> { match !int_compare(n, 0) { Eq(_) -> { 0 } | (_) -> { !int_add(n, self(!int_subtract(n, 1))) } } }) sum(15000)";
fn eq(x: []const u8, y: []const u8) bool { return std.mem.eql(u8,x,y); }
fn obj(a: A, fields: []const struct{[]const u8,J}) !J { return runtime.object(a,fields); }
fn int(n: usize) J { return .{.integer=@intCast(n)}; }
fn str(s: []const u8) J { return .{.string=s}; }
fn samples(a:A) std.ArrayList(J) { return std.ArrayList(J).init(a); }
fn emit(a:A, result:J) !void { const text=try std.json.stringifyAlloc(a,result,.{});try std.io.getStdOut().writeAll(text);try std.io.getStdOut().writeAll("\n"); }
fn cooperative(a:A, variant:[]const u8) !J {
    const program=try parser.parse(a,SumSource);
    var blocking=samples(a);var totals=samples(a);var yields=samples(a);var steps=samples(a);
    for (0..repetitions) |_| {
        var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit();
        var engine=runtime.Engine.init(arena.allocator());
        engine.time_budget_ns=if(eq(variant,"sync")) 0 else 1_000_000;
        engine.probe_clock_mask=if(eq(variant,"every-step")) 0 else 127;
        var total=try std.time.Timer.start();var call=try std.time.Timer.start();var value:?runtime.Value=null;var count:usize=0;
        value=engine.eval(program) catch |err| blk:{ if(err!=error.Yield)return err;count+=1;break :blk null; };
        try blocking.append(int(@intCast(call.read())));
        while(value==null) {
            call.reset();value=engine.continueRun() catch |err| blk:{if(err!=error.Yield)return err;count+=1;break :blk null;};
            try blocking.append(int(@intCast(call.read())));
        }
        try totals.append(int(@intCast(total.read())));try yields.append(int(count));try steps.append(int(engine.steps));
        if(value.?!=.integer or value.?.integer!=112507500)return error.WrongSum;
    }
    return obj(a,&.{.{"mode",str("cooperative")},.{"variant",str(variant)},.{"passed",.{.bool=true}},.{"repetitions",int(repetitions)},.{"source",str(SumSource)},.{"expected",int(112507500)},.{"blocking_samples_ns",.{.array=blocking}},.{"total_samples_ns",.{.array=totals}},.{"yields",.{.array=yields}},.{"steps",.{.array=steps}}});
}
fn gitWorker(a:A,variant:[]const u8,repo:[]const u8) !J {
    const request=try obj(a,&.{.{"repo",str(repo)},.{"ref",str("f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9")},.{"action",str("history")},.{"limit",int(20)}});
    var blocked=samples(a);var complete=samples(a);var expected:?[]const u8=null;
    async_git.probe_delay_ns=delay_ns;
    for(0..repetitions) |_| {
        var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit();
        var timer=try std.time.Timer.start();var result:J=undefined;
        if(eq(variant,"sync")) {
            std.Thread.sleep(delay_ns);result=try git.request(arena.allocator(),request);
            try blocked.append(int(@intCast(timer.read())));
        } else {
            const worker=try async_git.Worker.start(request);defer worker.destroy();
            try blocked.append(int(@intCast(timer.read())));
            while(!worker.ready())std.Thread.sleep(100_000);
            result=switch(worker.response){.success=>|r|r,.failure=>|err|return err,.pending=>return error.NotReady};
            const encoded=try std.json.stringifyAlloc(a,result,.{});
            if(expected) |e| {if(!eq(e,encoded))return error.ChangedGitResult;}else expected=encoded;
            if(result!=.array or result.array.items.len!=20)return error.WrongGitResult;
            try complete.append(int(@intCast(timer.read())));continue;
        }
        const encoded=try std.json.stringifyAlloc(a,result,.{});
        if(expected) |e| {if(!eq(e,encoded))return error.ChangedGitResult;}else expected=encoded;
        if(result!=.array or result.array.items.len!=20)return error.WrongGitResult;
        try complete.append(int(@intCast(timer.read())));
    }
    return obj(a,&.{.{"mode",str("git-worker")},.{"variant",str(variant)},.{"passed",.{.bool=true}},.{"repetitions",int(repetitions)},.{"injected_delay_ns",int(delay_ns)},.{"blocking_samples_ns",.{.array=blocked}},.{"completion_samples_ns",.{.array=complete}},.{"result_json",str(expected.?)}});
}
fn contentRef(a:A,cid:[]const u8) !J { return obj(a,&.{.{"0",str("#")},.{"l",try obj(a,&.{.{"/",str(cid)}})}}); }
fn hubWorker(a:A,variant:[]const u8,origin:[]const u8) !J {
    const ref=try contentRef(a,"baguqeerav7573zvsbhxirlmt7vqixxn5frippicgputyjumyzekzi2md4usa");
    var blocked=samples(a);var complete=samples(a);
    for(0..repetitions) |_| {
        var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit();
        const x=arena.allocator();var cache=try hub.Cache.init(x,origin);var engine=runtime.Engine.init(x);var timer=try std.time.Timer.start();
        if(eq(variant,"sync")) {
            const value=try cache.resolve(&engine,ref);if(value!=.integer or value.integer!=42)return error.WrongHubValue;
            try blocked.append(int(@intCast(timer.read())));
        } else {
            const worker=try async_hub.Worker.start(&cache,ref);defer worker.destroy();
            try blocked.append(int(@intCast(timer.read())));
            while(!worker.ready())std.Thread.sleep(100_000);
            try worker.merge(&cache);if(worker.failure) |err|return err;
            const value=try cache.resolve(&engine,ref);if(value!=.integer or value.integer!=42)return error.WrongHubValue;
        }
        try complete.append(int(@intCast(timer.read())));
    }
    return obj(a,&.{.{"mode",str("hub-worker")},.{"variant",str(variant)},.{"passed",.{.bool=true}},.{"repetitions",int(repetitions)},.{"blocking_samples_ns",.{.array=blocked}},.{"completion_samples_ns",.{.array=complete}},.{"origin",str(origin)},.{"expected",int(42)}});
}
const Fixture=struct {
    module:[]const u8,cid:[]const u8,requests:usize=0,module_requests:usize=0,ledger_requests:usize=0,next_ledger:?[]const u8=null,
    fn get(context:?*anyopaque,_:A,url:[]const u8) !hub.Response {
        const self:*Fixture=@ptrCast(@alignCast(context.?));self.requests+=1;std.Thread.sleep(2*std.time.ns_per_ms);
        const body=if(std.mem.indexOf(u8,url,"/modules/")!=null) blk:{self.module_requests+=1;break :blk self.module;} else blk:{
            self.ledger_requests+=1;if(self.next_ledger) |page| {self.next_ledger=null;break :blk page;}break :blk "{\"entries\":[]}";
        };
        return .{.status=200,.headers=&.{},.body=body};
    }
};
fn configured(a:A,fixture:*Fixture) !hub.Cache { var c=try hub.Cache.init(a,"https://controlled-fixture.invalid");c.transport=Fixture.get;c.transport_context=fixture;c.pulled=true;return c; }
fn cacheProbe(a:A,variant:[]const u8) !J {
    const source="let sum = !fix((self, n) -> { match !int_compare(n, 0) { Eq(_) -> { 0 } | (_) -> { !int_add(n, self(!int_subtract(n, 1))) } } }) sum(1500)";
    const program=try parser.parse(a,source);const cid=try hub.canonicalCID(a,program);const reference=try contentRef(a,cid);
    var fixture=Fixture{.module=try hub.canonicalBytes(a,program),.cid=cid};var cache=try configured(a,&fixture);var engine=runtime.Engine.init(a);
    const warmed=try cache.resolve(&engine,reference);if(warmed.integer!=1125750)return error.WrongCacheValue;
    const before=fixture.requests;var durations=samples(a);
    for(0..repetitions) |_| {
        if(eq(variant,"cold"))cache.modules.clearRetainingCapacity();
        var timer=try std.time.Timer.start();const value=try cache.resolve(&engine,reference);try durations.append(int(@intCast(timer.read())));
        if(value!=.integer or value.integer!=1125750)return error.WrongCacheValue;
    }
    return obj(a,&.{.{"mode",str("hub-cache")},.{"variant",str(variant)},.{"passed",.{.bool=true}},.{"repetitions",int(repetitions)},.{"fixture_get_delay_ns",int(2*std.time.ns_per_ms)},.{"samples_ns",.{.array=durations}},.{"initial_requests",int(before)},.{"timed_requests",int(fixture.requests-before)},.{"total_module_requests",int(fixture.module_requests)},.{"expected",int(1125750)}});
}
fn releasePage(a:A,cid:[]const u8) ![]const u8 {
    const link=try obj(a,&.{.{"/",str(cid)}});
    const payload=try obj(a,&.{.{"sequence",int(1)},.{"previous",.null},.{"signatory",link},.{"key",str("fixture")},.{"type",str("release")},.{"content",try obj(a,&.{.{"package",str("later")},.{"version",int(1)},.{"module",link}})}});
    const entry=try obj(a,&.{.{"cursor",int(6)},.{"sequence",int(1)},.{"cid",link},.{"entity",link},.{"type",str("release")},.{"payload",str(try std.json.stringifyAlloc(a,payload,.{}))}});
    var entries=std.json.Array.init(a);try entries.append(entry);return std.json.stringifyAlloc(a,try obj(a,&.{.{"entries",.{.array=entries}}}),.{});
}
fn refreshProbe(a:A,variant:[]const u8) !J {
    const program=try parser.parse(a,"42");const cid=try hub.canonicalCID(a,program);
    var fixture=Fixture{.module=try hub.canonicalBytes(a,program),.cid=cid};var cache=try configured(a,&fixture);cache.cursor=5;
    _=try cache.ingestModule(cid,fixture.module);try cache.addPackage("demo",1,cid,5);
    const ref=try obj(a,&.{.{"0",str("@")},.{"p",str("demo")}});var engine=runtime.Engine.init(a);_=try cache.resolve(&engine,ref);
    var durations=samples(a);
    for(0..repetitions) |_| {
        var timer=try std.time.Timer.start();if(eq(variant,"always"))try cache.refresh();
        const value=try cache.resolve(&engine,ref);if(value.integer!=42)return error.WrongRefreshValue;
        try durations.append(int(@intCast(timer.read())));
    }
    const known_requests=fixture.requests;fixture.next_ledger=try releasePage(a,cid);
    const later=try obj(a,&.{.{"0",str("@")},.{"p",str("later")}});var timer=try std.time.Timer.start();const value=try cache.resolve(&engine,later);const first_miss=timer.read();
    if(value.integer!=42 or cache.cursor!=6)return error.RefreshDidNotDiscoverRelease;
    const missed_requests=fixture.requests-known_requests;const before_repeat=fixture.requests;_=try cache.resolve(&engine,later);if(fixture.requests!=before_repeat)return error.KnownNameRefetched;
    return obj(a,&.{.{"mode",str("hub-refresh")},.{"variant",str(variant)},.{"passed",.{.bool=true}},.{"repetitions",int(repetitions)},.{"fixture_get_delay_ns",int(2*std.time.ns_per_ms)},.{"samples_ns",.{.array=durations}},.{"known_lookup_requests",int(known_requests)},.{"new_name_incremental_requests",int(missed_requests)},.{"new_name_lookup_ns",int(@intCast(first_miss))},.{"repeat_known_requests",int(fixture.requests-before_repeat)},.{"final_cursor",int(@intCast(cache.cursor))}});
}
pub fn main() !void {
    var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit();const a=arena.allocator();const args=try std.process.argsAlloc(a);if(args.len<3)return error.ExpectedModeVariant;
    const result=if(eq(args[1],"cooperative")) try cooperative(a,args[2]) else if(eq(args[1],"git"))try gitWorker(a,args[2],args[3]) else if(eq(args[1],"hub"))try hubWorker(a,args[2],args[3]) else if(eq(args[1],"cache"))try cacheProbe(a,args[2]) else if(eq(args[1],"refresh"))try refreshProbe(a,args[2]) else return error.UnknownMode;
    try emit(a,result);
}
