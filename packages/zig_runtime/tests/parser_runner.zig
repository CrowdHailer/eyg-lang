//! Parser-only transport for developing the syntax port independently.
const std = @import("std");
const parser = @import("parser");
const J = std.json.Value;

pub fn main() !void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader());
    const writer = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try reader.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const parsed = try std.json.parseFromSlice(J, a, line, .{});
        const request = parsed.value.object;
        const source = request.get("source").?.string;
        const response = if (std.mem.eql(u8, request.get("op").?.string, "diagnostic"))
            try parser.object(a, &.{.{ "message", .{ .string = try parser.diagnostic(a, source) } }})
        else blk: {
            const ir = parser.parse(a, source) catch break :blk try parser.object(a, &.{.{ "parse_error", .{ .bool = true } }});
            break :blk try parser.object(a, &.{.{ "program", ir }});
        };
        try std.json.stringify(response, .{}, writer);
        try writer.writeByte('\n');
    }
}
