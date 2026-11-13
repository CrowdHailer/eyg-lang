//! next-tui's JavaScript dictionaries expose CHAMP traversal order in type
//! diagnostics. Reproduce that order at the two observable runtime-to-type
//! boundaries; ordinary language record equality remains independent of order.
const std = @import("std");
const runtime = @import("interpreter.zig");
const A = std.mem.Allocator;
const Entry = struct { field: runtime.Field, hash: u32 };
fn stringHash(text: []const u8) u32 {
    var hash: u32 = 0;
    var i: usize = 0;
    while (i < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        const end = @min(text.len, i + len);
        const cp = std.unicode.utf8Decode(text[i..end]) catch 0xfffd;
        i = end;
        if (cp <= 0xffff) hash = hash *% 31 +% cp else {
            const n = cp - 0x10000;
            hash = hash *% 31 +% (0xd800 + (n >> 10));
            hash = hash *% 31 +% (0xdc00 + (n & 0x3ff));
        }
    }
    return hash;
}
const Node = struct {
    entries: std.ArrayList(Entry),
    children: [32]?*Node = [_]?*Node{null} ** 32,
    fn create(allocator: A) !*Node {
        const node = try allocator.create(Node);
        node.* = .{ .entries = std.ArrayList(Entry).init(allocator) };
        return node;
    }
};
fn insert(allocator: A, node: *Node, entry: Entry, shift: usize) anyerror!void {
    if (shift > 32) {
        for (node.entries.items) |*old| if (runtime.eq(old.field.name, entry.field.name)) {
            old.* = entry;
            return;
        };
        try node.entries.append(entry);
        return;
    }
    const distance: u5 = @intCast(shift);
    const bucket = (entry.hash >> distance) & 31;
    if (node.children[bucket]) |child| return insert(allocator, child, entry, shift + 5);
    for (node.entries.items, 0..) |old, index| {
        if ((old.hash >> distance) & 31 != bucket) continue;
        if (runtime.eq(old.field.name, entry.field.name)) {
            node.entries.items[index] = entry;
            return;
        }
        const child = try Node.create(allocator);
        // CHAMP moves the incoming pair before the existing pair when a
        // collision creates a child. This matters for equal complete hashes.
        try insert(allocator, child, entry, shift + 5);
        try insert(allocator, child, old, shift + 5);
        node.children[bucket] = child;
        _ = node.entries.orderedRemove(index);
        return;
    }
    var at: usize = 0;
    while (at < node.entries.items.len and (node.entries.items[at].hash >> distance) & 31 < bucket) : (at += 1) {}
    try node.entries.insert(at, entry);
}
fn collect(node: *const Node, output: *std.ArrayList(runtime.Field)) anyerror!void {
    var bucket: usize = 32;
    while (bucket > 0) {
        bucket -= 1;
        if (node.children[bucket]) |child| try collect(child, output);
    }
    var index = node.entries.items.len;
    while (index > 0) {
        index -= 1;
        try output.append(node.entries.items[index].field);
    }
}
pub fn fields(allocator: A, input: []const runtime.Field) ![]const runtime.Field {
    const root = try Node.create(allocator);
    for (input) |field| try insert(allocator, root, .{ .field = field, .hash = stringHash(field.name) }, 0);
    var output = std.ArrayList(runtime.Field).init(allocator);
    try collect(root, &output);
    return output.toOwnedSlice();
}

test "CHAMP direct entries are reversed after nested collision buckets" {
    const input = [_]runtime.Field{ .{ .name = "a", .value = runtime.unit() }, .{ .name = "b", .value = runtime.unit() }, .{ .name = "c", .value = runtime.unit() } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try fields(arena.allocator(), &input);
    // The auxiliary traversal allocations intentionally use an arena in callers.
    try std.testing.expectEqualStrings("c", result[0].name);
}
