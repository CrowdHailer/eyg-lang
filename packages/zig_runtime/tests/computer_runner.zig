//! Direct pure-effect transport, independent of the terminal integration.
const std = @import("std");
const computer = @import("computer");
const runtime = computer.runtime;
const J = std.json.Value;

pub fn main() !void {
    var input = std.io.bufferedReader(std.io.getStdIn().reader());
    const writer = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try input.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const request = (try std.json.parseFromSlice(J, a, line, .{ .allocate = .alloc_always })).value;
        var engine = runtime.Engine.init(a);
        if (runtime.field(request, "program") != .null) {
            engine.effect_handler = hostEffect;
            const response = try engine.evaluate(runtime.field(request, "program"));
            try std.json.stringify(response, .{}, writer);
            try writer.writeByte('\n');
            continue;
        }
        const lift = try engine.fromJson(runtime.field(request, "lift"));
        const value = computer.effect(&engine, runtime.stringField(request, "label") orelse "", lift) catch |err| {
            const response = if (err == error.Runtime) try runtime.object(a, &.{.{ "break", try engine.reasonJson(engine.failure.?) }}) else try runtime.object(a, &.{.{ "host_error", .{ .string = @errorName(err) } }});
            try std.json.stringify(response, .{}, writer);
            try writer.writeByte('\n');
            continue;
        };
        try std.json.stringify(try runtime.object(a, &.{.{ "value", try engine.toJson(value) }}), .{}, writer);
        try writer.writeByte('\n');
    }
}
fn hostEffect(_: ?*anyopaque, engine: *runtime.Engine, label: []const u8, lift: runtime.Value) anyerror!runtime.Value {
    return computer.effect(engine, label, lift);
}
