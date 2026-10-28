//! Isolated transport for the structural-pattern compatibility helper.
const std = @import("std");
const patterns = @import("patterns");
const J = std.json.Value;
const A = std.mem.Allocator;

fn field(value: J, name: []const u8) J {
    return if (value == .object) value.object.get(name) orelse .null else .null;
}
fn text(value: J, name: []const u8) []const u8 {
    const v = field(value, name);
    return if (v == .string) v.string else "";
}
fn object(a: A, fields: []const struct { []const u8, J }) !J {
    var map = std.json.ObjectMap.init(a);
    for (fields) |f| try map.put(f[0], f[1]);
    return .{ .object = map };
}
fn encodePattern(a: A, pattern: patterns.Pattern) !J {
    var fields = std.ArrayList(J).init(a);
    for (pattern.fields) |f| try fields.append(try object(a, &.{ .{ "name", .{ .string = f.name } }, .{ "variable", .{ .string = f.variable } } }));
    return object(a, &.{ .{ "label", .{ .string = pattern.label } }, .{ "destructured", .{ .bool = pattern.destructured } }, .{ "fields", .{ .array = fields } } });
}
fn clean(a: A, value: J) anyerror!J {
    if (value == .object) {
        var result = std.json.ObjectMap.init(a);
        var it = value.object.iterator();
        while (it.next()) |entry| if (!std.mem.startsWith(u8, entry.key_ptr.*, "_native_")) try result.put(entry.key_ptr.*, try clean(a, entry.value_ptr.*));
        return .{ .object = result };
    }
    if (value == .array) {
        var result = std.ArrayList(J).init(a);
        for (value.array.items) |item| try result.append(try clean(a, item));
        return .{ .array = result };
    }
    return value;
}
pub fn main() !void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader());
    const writer = std.io.getStdOut().writer();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try reader.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const request = (try std.json.parseFromSlice(J, a, line, .{})).value;
        const response = if (std.mem.eql(u8, text(request, "op"), "gather")) blk: {
            const result = try patterns.gather(a, text(request, "label"), field(request, "body"));
            break :blk try encodePattern(a, result.pattern);
        } else blk: {
            const raw = field(request, "pattern");
            var fields = std.ArrayList(patterns.Field).init(a);
            const items = field(raw, "fields");
            if (items == .array) for (items.array.items) |item| try fields.append(.{ .name = text(item, "name"), .variable = text(item, "variable") });
            const d = field(raw, "destructured");
            const p = patterns.Pattern{ .label = text(raw, "label"), .destructured = d == .bool and d.bool, .fields = fields.items };
            const result = try patterns.lower(a, p, field(request, "body"), &.{0});
            break :blk try clean(a, try object(a, &.{ .{ "0", .{ .string = "f" } }, .{ "l", .{ .string = result.label } }, .{ "b", result.body } }));
        };
        try std.json.stringify(response, .{}, writer);
        try writer.writeByte('\n');
    }
}
