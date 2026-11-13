//! Isolated source-location and continuation inspector differential transport.
const std = @import("std");
const source = @import("eyg_source");
const runtime = source.runtime;
const J = std.json.Value;

pub fn main() !void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader());
    const out = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try reader.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const request = (try std.json.parseFromSlice(J, a, line, .{})).value;
        const response = response: {
            const origin = runtime.stringField(request, "origin") orelse "disk";
            const parsed = source.parse(a, runtime.stringField(request, "source").?, if (runtime.eq(origin, "inline")) .inline_code else if (runtime.eq(origin, "pipe")) .pipe else if (runtime.eq(origin, "repl")) .repl else .{ .disk = runtime.stringField(request, "path") orelse "/module.eyg" }) catch break :response try runtime.object(a, &.{.{ "parse_error", .{ .bool = true } }});
            if (runtime.eq(runtime.stringField(request, "op") orelse "", "source_parse")) break :response try runtime.object(a, &.{.{ "program", parsed.program }});
            var engine = runtime.Engine.init(a);
            engine.inspection_meta = parsed.meta;
            const value = engine.eval(parsed.program) catch |err| {
                if (engine.failure) |reason| break :response try runtime.object(a, &.{.{ "break", try engine.reasonJson(reason) }});
                break :response try runtime.object(a, &.{.{ "error", .{ .string = @errorName(err) } }});
            };
            const width = runtime.field(request, "width");
            break :response try runtime.object(a, &.{.{ "text", .{ .string = try engine.render(value, if (width == .integer and width.integer > 0) @intCast(width.integer) else 80) } }});
        };
        try std.json.stringify(response, .{}, out);
        try out.writeByte('\n');
    }
}
