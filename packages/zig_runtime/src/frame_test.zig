const std = @import("std");
const tui = @import("tui.zig");

test "JSON frames retain symbols and distinguish styles after source disposal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var text = [_]u8{'a'};
    var buffer = try tui.Buffer.init(std.testing.allocator, 3, 1);
    buffer.cells[0].symbol = &text;
    buffer.cells[1].symbol = &text;
    buffer.cells[1].style.fg = .{ .indexed = 1 };
    buffer.cells[2].symbol = &text;
    const frame = try buffer.json(arena.allocator());
    buffer.deinit();
    text[0] = 'b';
    const cells = frame.object.get("cells").?.array.items;
    for (cells) |cell| try std.testing.expectEqualStrings("a", cell.object.get("symbol").?.string);
    try std.testing.expect(cells[0].object.get("fg").? == .null);
    try std.testing.expectEqual(@as(i64, 1), cells[1].object.get("fg").?.integer);
    try std.testing.expect(cells[2].object.get("fg").? == .null);
}

test "caller-owned frames survive scratch disposal without retaining discarded renders" {
    var session = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer session.deinit();
    var retained = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer retained.deinit();
    var discarded = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer discarded.deinit();
    var shell = tui.Tui.init(session.allocator());
    defer shell.shutdown();
    shell.sandboxed = true;
    const paste = try std.json.parseFromSlice(std.json.Value, session.allocator(),
        \\{"paste":"{answer: 42, label: \"λ\"}"}
    , .{});
    try shell.event(paste.value);
    const first = try shell.frameAlloc(retained.allocator(), 80, 24);
    const wire = @import("json_wire.zig");
    const expected = try wire.stringifyAlloc(retained.allocator(), first);
    const capacity = session.queryCapacity();
    for (0..16) |_| {
        _ = try shell.frameAlloc(discarded.allocator(), 80, 24);
        _ = discarded.reset(.retain_capacity);
    }
    try std.testing.expectEqual(capacity, session.queryCapacity());
    const replace = try std.json.parseFromSlice(std.json.Value, session.allocator(),
        \\{"paste":"[1, 2, 3]"}
    , .{});
    try shell.event(replace.value);
    _ = try shell.frameAlloc(discarded.allocator(), 40, 10);
    _ = discarded.reset(.free_all);
    const actual = try wire.stringifyAlloc(retained.allocator(), first);
    try std.testing.expectEqualStrings(expected, actual);
}

test "picker rendering does not retain temporary matching allocations" {
    var session = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer session.deinit();
    var output = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer output.deinit();
    var shell = tui.Tui.init(session.allocator());
    defer shell.shutdown();
    shell.sandboxed = true;
    var open = std.json.ObjectMap.init(session.allocator());
    try open.put("key", .{ .string = "j" });
    try shell.event(.{ .object = open });
    _ = try shell.frameAlloc(output.allocator(), 80, 24);
    _ = output.reset(.retain_capacity);
    const capacity = session.queryCapacity();
    for (0..16) |_| {
        _ = try shell.frameAlloc(output.allocator(), 80, 24);
        _ = output.reset(.retain_capacity);
    }
    try std.testing.expectEqual(capacity, session.queryCapacity());
}
