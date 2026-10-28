const std = @import("std");
const tui = @import("tui");
const J = std.json.Value;
fn color(j: J) tui.Color {
    return switch (j) { .integer => |n| .{ .indexed = @intCast(n) }, .array => |v| .{ .rgb = .{ @intCast(v.items[0].integer), @intCast(v.items[1].integer), @intCast(v.items[2].integer) } }, else => .default };
}
fn field(j: J, k: []const u8) J { return j.object.get(k) orelse .null; }
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.io.getStdIn().readToEndAlloc(a, 16*1024*1024);
    const frame = (try std.json.parseFromSlice(J,a,bytes, .{})).value;
    var buffer = try tui.Buffer.init(a,@intCast(field(frame,"width").integer),@intCast(field(frame,"height").integer));
    for (field(frame,"cells").array.items,0..) |c,i| buffer.cells[i] = .{ .symbol = field(c,"symbol").string, .width = @intCast(field(c,"width").integer), .style = .{ .fg=color(field(c,"fg")), .bg=color(field(c,"bg")), .modifiers=@intCast(field(c,"modifiers").integer), .underline_color=color(field(c,"underline_color")) } };
    tui.bench_no_ansi_style_runs = true;
    const before = try buffer.ansi(a);
    tui.bench_no_ansi_style_runs = false;
    const after = try buffer.ansi(a);
    var o=std.json.ObjectMap.init(a);
    try o.put("before",.{.string=before});try o.put("after",.{.string=after});
    var writer=std.io.bufferedWriter(std.io.getStdOut().writer());
    try std.json.stringify(J{.object=o},.{},writer.writer());try writer.flush();
}
