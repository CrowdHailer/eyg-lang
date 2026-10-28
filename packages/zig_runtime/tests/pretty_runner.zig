//! Isolated value-layout transport; build with the named eyg_interpreter module.
const std = @import("std");
const runtime = @import("eyg_interpreter");
const J = runtime.Json;

pub fn main() !void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader());
    const out = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try reader.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const parsed = try std.json.parseFromSlice(J, a, line, .{});
        const request = parsed.value;
        var engine = runtime.Engine.init(a);
        if (runtime.stringField(request, "meta")) |meta| if (runtime.eq(meta, "repl")) {
            engine.inspection_meta = .{ .literal = "Location(origin: Repl, source: Json)" };
        };
        const response = response: {
            const value = engine.eval(runtime.field(request, "program")) catch |err| {
                if (err == error.InvalidIR) break :response try runtime.object(a, &.{.{ "decode_error", .{ .bool = true } }});
                if (engine.failure) |reason| break :response try runtime.object(a, &.{.{ "break", try engine.reasonJson(reason) }});
                break :response try runtime.object(a, &.{.{ "error", .{ .string = @errorName(err) } }});
            };
            const width_field = runtime.field(request, "width");
            const width: usize = if (width_field == .integer and width_field.integer > 0) @intCast(width_field.integer) else 80;
            break :response try runtime.object(a, &.{.{ "text", .{ .string = try engine.render(value, width) } }});
        };
        try std.json.stringify(response, .{}, out);
        try out.writeByte('\n');
    }
}
