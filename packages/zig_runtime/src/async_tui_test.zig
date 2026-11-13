const std = @import("std");
const tui = @import("tui.zig");
const parser = @import("parser.zig");

fn key(a: std.mem.Allocator, name: []const u8) !std.json.Value {
    return parser.object(a, &.{.{ "key", .{ .string = name } }});
}
fn start(a: std.mem.Allocator, shell: *tui.Tui) !void {
    try shell.event(try parser.object(a, &.{.{ "paste", .{ .string = "perform GitQuery({repo: \"/definitely-missing-eyg-repository\", action: \"head\"})" } }}));
    try shell.event(try key(a, "enter"));
}
test "Git effect suspends and completes on the UI thread" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var shell = tui.Tui.init(a);
    defer shell.shutdown();
    try start(a, &shell);
    try std.testing.expect(shell.hasPendingWork());
    try std.testing.expectEqualStrings("running", @tagName(shell.mode));
    const deadline = std.time.nanoTimestamp() + 5 * std.time.ns_per_s;
    while (shell.hasPendingWork() and std.time.nanoTimestamp() < deadline) {
        _ = try shell.pollWork();
        std.Thread.yield() catch {};
    }
    try std.testing.expect(!shell.hasPendingWork());
    try std.testing.expectEqual(@as(usize, 1), shell.history.items.len);
    const value = shell.history.items[0].value orelse return error.MissingQueryResult;
    try std.testing.expect(value == .tagged);
    try std.testing.expectEqualStrings("Error", value.tagged.label);
    try std.testing.expectEqualStrings("GitQuery", shell.history.items[0].occured[0].label);
}
test "cancelling a worker preserves the cancelled history outcome" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var shell = tui.Tui.init(a);
    defer shell.shutdown();
    try start(a, &shell);
    try shell.event(try key(a, "esc"));
    try std.testing.expectEqualStrings("Cancelled", shell.history.items[0].result.?);
    const deadline = std.time.nanoTimestamp() + 5 * std.time.ns_per_s;
    while (shell.hasPendingWork() and std.time.nanoTimestamp() < deadline) {
        _ = try shell.pollWork();
        std.Thread.yield() catch {};
    }
    try std.testing.expectEqual(@as(usize, 1), shell.history.items.len);
    try std.testing.expectEqualStrings("Cancelled", shell.history.items[0].result.?);
}
