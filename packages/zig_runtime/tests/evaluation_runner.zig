//! Small isolated transport for evaluator and malformed-IR differential tests.
const std = @import("std");
const runtime = @import("eyg_interpreter");
pub fn main() !void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader());
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try reader.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const request = try std.json.parseFromSlice(runtime.Json, a, line, .{});
        const result = runtime.evaluate(a, runtime.field(request.value, "program")) catch |err| try runtime.object(a, &.{.{ "error", .{ .string = @errorName(err) } }});
        try std.json.stringify(result, .{}, std.io.getStdOut().writer());
        try std.io.getStdOut().writeAll("\n");
    }
}
