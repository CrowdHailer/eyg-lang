//! Small interpreter-only test transport, useful while porting the terminal.
const std = @import("std");
const interpreter = @import("interpreter");
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
        var fixture = std.json.ObjectMap.init(a);
        try fixture.put("source", request.get("program") orelse .null);
        if (request.get("effects")) |effects| try fixture.put("effects", effects);
        const response = try interpreter.evaluateFixture(a, .{ .object = fixture });
        try std.json.stringify(response, .{}, writer);
        try writer.writeByte('\n');
    }
}
