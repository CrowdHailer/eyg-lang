//! Reify a runtime value as closed canonical EYG IR. Closure environments retain
//! only free variables, sharing equal definitions and renaming shadowed ones.
const std = @import("std");
const runtime = @import("interpreter.zig");
const A = std.mem.Allocator;
const J = std.json.Value;
const V = runtime.Value;
const Definition = struct { name: []const u8, source: J };
const Rename = struct { scoped: []const u8, name: []const u8 };
const Ignore = struct { name: []const u8, next: ?*const Ignore };
const Capture = struct {
    allocator: A,
    definitions: std.ArrayList(Definition),
    fn node(c: *Capture, code: []const u8, fields: []const struct { []const u8, J }) !J {
        var result = try runtime.object(c.allocator, &.{.{ "0", .{ .string = code } }});
        for (fields) |f| try result.object.put(f[0], f[1]);
        return result;
    }
    fn apply(c: *Capture, f: J, arg: J) !J {
        return c.node("a", &.{ .{ "f", f }, .{ "a", arg } });
    }
    fn value(c: *Capture, input: V) anyerror!J {
        return switch (input) {
            .integer => |i| c.node("i", &.{.{ "v", .{ .integer = i } }}),
            .javascript_integer => |f| c.node("i", &.{.{ "v", .{ .float = f } }}),
            .string => |s| c.node("s", &.{.{ "v", .{ .string = s } }}),
            .binary => |b| c.node("x", &.{.{ "v", try runtime.encodeBytes(c.allocator, b) }}),
            .tagged => |t| c.apply(try c.node("t", &.{.{ "l", .{ .string = t.label } }}), try c.value(t.value)),
            .record => |input_fields| blk: {
                const fields = try @import("oracle_order.zig").fields(c.allocator, input_fields);
                var result = try c.node("u", &.{});
                var i = fields.len;
                while (i > 0) {
                    i -= 1;
                    const field = fields[i];
                    const item = try c.value(field.value);
                    result = try c.apply(try c.apply(try c.node("e", &.{.{ "l", .{ .string = field.name } }}), item), result);
                }
                break :blk result;
            },
            .list => |head| blk: {
                var values = std.ArrayList(V).init(c.allocator);
                var cursor = head;
                while (cursor) |cell| : (cursor = cell.tail) try values.append(cell.head);
                var result = try c.node("ta", &.{});
                var i = values.items.len;
                while (i > 0) {
                    i -= 1;
                    const item = try c.value(values.items[i]);
                    result = try c.apply(try c.apply(try c.node("c", &.{}), item), result);
                }
                break :blk result;
            },
            .partial => |p| blk: {
                const code = switch (p.kind) {
                    .cons => "c",
                    .extend => "e",
                    .overwrite => "o",
                    .select => "g",
                    .tag => "t",
                    .match => "m",
                    .no_cases => "n",
                    .perform => "p",
                    .handle => "h",
                    .builtin => "b",
                };
                var result = try c.node(code, if (p.kind == .cons or p.kind == .no_cases) &.{} else &.{.{ "l", .{ .string = p.label } }});
                for (p.args) |arg| result = try c.apply(result, try c.value(arg));
                break :blk result;
            },
            .@"resume" => error.CannotCaptureContinuation,
            .closure => |closure| blk: {
                var names = std.ArrayList([]const u8).init(c.allocator);
                const ignore = Ignore{ .name = closure.param, .next = null };
                try freeVariables(closure.body, &ignore, &names);
                var renames = std.ArrayList(Rename).init(c.allocator);
                for (names.items) |name| {
                    var cursor = closure.env;
                    var captured: ?V = null;
                    while (cursor) |binding| : (cursor = binding.next) {
                        if (runtime.eq(name, binding.name)) {
                            captured = binding.value;
                            break;
                        }
                    }
                    const term = captured orelse continue;
                    const expression = try c.value(term);
                    var old: ?J = null;
                    for (c.definitions.items) |definition| {
                        if (runtime.eq(definition.name, name)) {
                            old = definition.source;
                            break;
                        }
                    }
                    if (old) |previous| {
                        if (canonicalEqual(previous, expression)) continue;
                        const prefix = try std.mem.concat(c.allocator, u8, &.{ name, "#" });
                        var existing: ?[]const u8 = null;
                        for (c.definitions.items) |definition| if (std.mem.startsWith(u8, definition.name, prefix) and canonicalEqual(definition.source, expression)) {
                            existing = definition.name;
                            break;
                        };
                        const scoped = existing orelse try std.fmt.allocPrint(c.allocator, "{s}#{d}", .{ name, c.definitions.items.len });
                        if (existing == null) try c.definitions.insert(0, .{ .name = scoped, .source = expression });
                        try renames.insert(0, .{ .scoped = scoped, .name = name });
                    } else try c.definitions.insert(0, .{ .name = name, .source = expression });
                }
                var result = try c.node("f", &.{ .{ "l", .{ .string = closure.param } }, .{ "b", closure.body } });
                for (renames.items) |rename| result = try c.node("l", &.{ .{ "l", .{ .string = rename.name } }, .{ "v", try c.node("v", &.{.{ "l", .{ .string = rename.scoped } }}) }, .{ "t", result } });
                break :blk result;
            },
        };
    }
};
fn freeVariables(source: J, ignore: ?*const Ignore, names: *std.ArrayList([]const u8)) anyerror!void {
    const code = runtime.stringField(source, "0") orelse return;
    if (runtime.eq(code, "v")) {
        const name = runtime.stringField(source, "l") orelse return;
        var cursor = ignore;
        while (cursor) |binding| : (cursor = binding.next) if (runtime.eq(binding.name, name)) return;
        for (names.items) |existing| if (runtime.eq(existing, name)) return;
        try names.append(name);
    } else if (runtime.eq(code, "a")) {
        try freeVariables(runtime.field(source, "f"), ignore, names);
        try freeVariables(runtime.field(source, "a"), ignore, names);
    } else if (runtime.eq(code, "f") or runtime.eq(code, "l")) {
        if (runtime.eq(code, "l")) try freeVariables(runtime.field(source, "v"), ignore, names);
        const inner = Ignore{ .name = runtime.stringField(source, "l") orelse "", .next = ignore };
        try freeVariables(runtime.field(source, if (runtime.eq(code, "f")) "b" else "t"), &inner, names);
    }
}
fn canonicalEqual(a: J, b: J) bool {
    if (a == .object and b == .object) {
        var it = a.object.iterator();
        while (it.next()) |entry| {
            if (runtime.eq(entry.key_ptr.*, "_native_node")) continue;
            const other = b.object.get(entry.key_ptr.*) orelse return false;
            if (!canonicalEqual(entry.value_ptr.*, other)) return false;
        }
        it = b.object.iterator();
        while (it.next()) |entry| if (!runtime.eq(entry.key_ptr.*, "_native_node") and !a.object.contains(entry.key_ptr.*)) return false;
        return true;
    }
    return runtime.jsonEqual(a, b);
}
pub fn capture(allocator: A, value: V) anyerror!J {
    var state = Capture{ .allocator = allocator, .definitions = std.ArrayList(Definition).init(allocator) };
    var result = try state.value(value);
    for (state.definitions.items) |definition| result = try state.node("l", &.{ .{ "l", .{ .string = definition.name } }, .{ "v", definition.source }, .{ "t", result } });
    return result;
}
test "capture preserves lexical closure shadowing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parser = @import("parser.zig");
    var engine = runtime.Engine.init(a);
    const original = try engine.eval(try parser.parse(a, "let x = 42 let f = (y) -> { !int_add(x, y) } f"));
    const source = try capture(a, original);
    var fresh = runtime.Engine.init(a);
    const restored = try fresh.eval(source);
    const got = try fresh.call(restored, &.{.{ .integer = 8 }});
    try std.testing.expectEqual(@as(i64, 50), got.integer);
}
