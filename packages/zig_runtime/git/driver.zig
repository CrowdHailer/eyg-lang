//! Standalone verifier/benchmark driver for the native Git module.
const std = @import("std");
const git = @import("git");
pub fn main() !void {
    var buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    const reader = buffered.reader();
    const writer = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = (try reader.readUntilDelimiterOrEofAlloc(a, '\n', 4 * 1024 * 1024)) orelse break;
        const parsed = try std.json.parseFromSlice(std.json.Value, a, line, .{ .allocate = .alloc_always });
        const start = std.time.nanoTimestamp();
        const answer = git.request(a, parsed.value) catch |err| {
            try writer.print("{{\"error\":\"{s}\"}}\n", .{@errorName(err)});
            continue;
        };
        const elapsed = std.time.nanoTimestamp() - start;
        try writer.writeAll("{\"result\":");
        try std.json.stringify(answer, .{}, writer);
        try writer.print(",\"duration_ns\":{d}}}\n", .{elapsed});
    }
}
