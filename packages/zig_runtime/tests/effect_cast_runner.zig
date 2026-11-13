//! Validation-only transport. It never invokes an effect provider.
const std = @import("std");
const cast = @import("effect_cast");
const runtime = cast.runtime;
const J = runtime.Json;

pub fn main() !void {
    var input = std.io.bufferedReader(std.io.getStdIn().reader());
    const out = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try input.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const request = (try std.json.parseFromSlice(J, a, line, .{ .allocate = .alloc_always })).value;
        var engine = runtime.Engine.init(a);
        const lift = try engine.fromJson(runtime.field(request, "lift"));
        const response = response: {
            cast.validate(&engine, runtime.stringField(request, "label") orelse "", lift) catch {
                break :response try runtime.object(a, &.{.{ "break", try engine.reasonJson(engine.failure.?) }});
            };
            break :response try runtime.object(a, &.{.{ "valid", .{ .bool = true } }});
        };
        try std.json.stringify(response, .{}, out);
        try out.writeByte('\n');
    }
}
