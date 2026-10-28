//! Read-only hub/cache transport for content-ID and offline/live integration tests.
const std = @import("std");
const hub = @import("hub");
const runtime = hub.runtime;
const J = std.json.Value;

pub fn main() !void {
    var input = std.io.bufferedReader(std.io.getStdIn().reader());
    const writer = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try input.reader().readUntilDelimiterOrEofAlloc(a, '\n', 64 * 1024 * 1024) orelse break;
        const request = (try std.json.parseFromSlice(J, a, line, .{ .allocate = .alloc_always })).value;
        const response = handle(a, request) catch |err| try runtime.object(a, &.{.{ "error", .{ .string = @errorName(err) } }});
        try std.json.stringify(response, .{}, writer);
        try writer.writeByte('\n');
    }
}
fn reference(context: ?*anyopaque, engine: *runtime.Engine, ir: J) anyerror!runtime.Value {
    const cache: *hub.Cache = @ptrCast(@alignCast(context.?));
    return cache.resolve(engine, ir);
}
fn handle(a: std.mem.Allocator, request: J) !J {
    const op = runtime.stringField(request, "op") orelse "";
    const program = runtime.field(request, "program");
    if (std.mem.eql(u8, op, "cid")) return runtime.object(a, &.{
        .{ "cid", .{ .string = try hub.canonicalCID(a, program) } },
        .{ "bytes", .{ .string = try hub.canonicalBytes(a, program) } },
    });
    var cache = try hub.Cache.init(a, runtime.stringField(request, "origin") orelse "https://eyg.run");
    if (std.mem.eql(u8, op, "verify")) {
        _ = try cache.ingestModule(runtime.stringField(request, "cid") orelse return error.MissingCid, runtime.stringField(request, "bytes") orelse return error.MissingBytes);
        return runtime.object(a, &.{.{ "verified", .{ .bool = true } }});
    }
    const fixtures = runtime.field(request, "packages");
    if (fixtures != .null) try cache.ingestPackages(fixtures);
    if (std.mem.eql(u8, op, "pull")) {
        try cache.pull();
        const entries = try cache.packageList(a);
        return (try std.json.parseFromSlice(J, a, try std.json.stringifyAlloc(a, entries, .{}), .{})).value;
    }
    var engine = runtime.Engine.init(a);
    engine.reference_context = &cache;
    engine.reference_handler = reference;
    return engine.evaluate(program);
}
