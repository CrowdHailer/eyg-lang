//! The structural editor's view of lambda/let destructuring. This is the
//! reversible sugar used by morph/editable on the pinned oracle, not a second
//! runtime pattern matcher. In particular an unused empty pattern is Bind("$").
const std = @import("std");
const runtime = @import("interpreter.zig");
const parser = @import("parser.zig");
const A = std.mem.Allocator;
const J = std.json.Value;

pub const Field = struct { name: []const u8, variable: []const u8 };
pub const Pattern = struct {
    label: []const u8,
    fields: []const Field = &.{},
    destructured: bool = false,
};
pub const Gather = struct { pattern: Pattern, rest: J };
pub const Lowered = struct { label: []const u8, body: J };

/// Recognize consecutive selectors of the parameter/bound record. The oracle
/// deliberately keeps the original binding when the whole record is still
/// free in the remaining expression.
pub fn gather(a: A, label: []const u8, body: J) !Gather {
    var fields = std.ArrayList(Field).init(a);
    var rest = body;
    while (eq(code(rest), "l")) {
        const definition = field(rest, "v");
        if (!eq(code(definition), "a")) break;
        const select = field(definition, "f");
        const from = field(definition, "a");
        if (!eq(code(select), "g") or !eq(code(from), "v") or !eq(text(from, "l"), label)) break;
        try fields.append(.{ .name = text(select, "l"), .variable = text(rest, "l") });
        rest = field(rest, "t");
    }
    if (isFree(label, rest)) return .{ .pattern = .{ .label = label }, .rest = body };
    return .{ .pattern = .{ .label = label, .fields = fields.items, .destructured = fields.items.len != 0 }, .rest = rest };
}

/// Copy exactly morph/editable.is_free's scope rules. A let shadows its name
/// only in the continuation; a lambda shadows it in its body.
pub fn isFree(label: []const u8, ir: J) bool {
    const tag = code(ir);
    if (eq(tag, "v")) return eq(label, text(ir, "l"));
    if (eq(tag, "f")) return !eq(label, text(ir, "l")) and isFree(label, field(ir, "b"));
    if (eq(tag, "a")) return isFree(label, field(ir, "f")) or isFree(label, field(ir, "a"));
    if (eq(tag, "l")) return isFree(label, field(ir, "v")) or (!eq(label, text(ir, "l")) and isFree(label, field(ir, "t")));
    return false;
}

/// Lower an edited pattern. Every inserted selector, variable, application and
/// let is annotated with the same pattern path, as in pattern_to_annotated.
/// `reverse_path` has the innermost index first.
pub fn lower(a: A, pattern: Pattern, body: J, reverse_path: []const usize) !Lowered {
    if (!pattern.destructured) return .{ .label = pattern.label, .body = body };
    var result = body;
    var i = pattern.fields.len;
    while (i > 0) {
        i -= 1;
        const f = pattern.fields[i];
        const select = try annotate(a, try parser.label(a, "g", f.name), reverse_path);
        const variable = try annotate(a, try parser.label(a, "v", "$"), reverse_path);
        const definition = try annotate(a, try parser.apply(a, select, variable), reverse_path);
        result = try annotate(a, try parser.letNode(a, f.variable, definition, result), reverse_path);
    }
    return .{ .label = "$", .body = result };
}

/// Extend a REPL scope after the pattern's definition has completed. Binding
/// order mirrors the generated lets, including shadowing the synthetic "$".
pub fn bind(engine: *runtime.Engine, pattern: Pattern, value: runtime.Value) !void {
    if (!pattern.destructured) return engine.bind(pattern.label, value);
    try engine.bind("$", value);
    for (pattern.fields) |f| {
        var cursor = engine.scope;
        var current = value;
        while (cursor) |binding| : (cursor = binding.next) {
            if (eq(binding.name, "$")) {
                current = binding.value;
                break;
            }
        }
        if (current != .record) {
            engine.failure = .{ .incorrect_term = .{ .expected = "Record", .got = current } };
            return error.Runtime;
        }
        var selected: ?runtime.Value = null;
        for (current.record) |entry| if (eq(entry.name, f.name)) {
            selected = entry.value;
            break;
        };
        if (selected) |found| try engine.bind(f.variable, found) else {
            engine.failure = .{ .missing_field = f.name };
            return error.Runtime;
        }
    }
}

fn annotate(a: A, ir: J, reverse_path: []const usize) !J {
    var result = ir;
    var path = std.ArrayList(J).init(a);
    for (reverse_path) |index| try path.append(.{ .integer = @intCast(index) });
    try result.object.put("_native_path", .{ .array = path });
    try result.object.put("_native_depth", .{ .integer = @intCast(reverse_path.len) });
    return result;
}
fn field(value: J, label: []const u8) J {
    return runtime.field(value, label);
}
fn text(value: J, label: []const u8) []const u8 {
    return runtime.stringField(value, label) orelse "";
}
fn code(value: J) []const u8 {
    return text(value, "0");
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "gather and lower preserve destructuring order and original record uses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try parser.parseExpression(a, "({x, y: z}) -> { !int_add(x, z) }");
    const gathered = try gather(a, text(source, "l"), field(source, "b"));
    try std.testing.expect(gathered.pattern.destructured);
    try std.testing.expectEqual(@as(usize, 2), gathered.pattern.fields.len);
    try std.testing.expectEqualStrings("x", gathered.pattern.fields[0].name);
    try std.testing.expectEqualStrings("z", gathered.pattern.fields[1].variable);
    const lowered = try lower(a, gathered.pattern, gathered.rest, &.{ 0, 2 });
    const reconstructed = try parser.lambda(a, lowered.label, lowered.body);
    const record = try parser.parseExpression(a, "{x: 20, y: 22}");
    var first = runtime.Engine.init(a);
    var second = runtime.Engine.init(a);
    try std.testing.expectEqual(@as(i64, 42), (try first.eval(try parser.apply(a, source, record))).integer);
    try std.testing.expectEqual(@as(i64, 42), (try second.eval(try parser.apply(a, reconstructed, record))).integer);
    try std.testing.expectEqual(@as(i64, 0), field(lowered.body, "_native_path").array.items[0].integer);
    const retained = try parser.parseExpression(a, "(record) -> { let x = record.x record }");
    const bound = try gather(a, "record", field(retained, "b"));
    try std.testing.expect(!bound.pattern.destructured);
    try std.testing.expectEqualStrings("l", code(bound.rest));
}

test "REPL destructuring exposes selected fields and missing fields fail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var engine = runtime.Engine.init(a);
    const value = try engine.eval(try parser.parseExpression(a, "{x: 20, y: 22}"));
    const pattern = Pattern{ .label = "$", .destructured = true, .fields = &.{ .{ .name = "x", .variable = "a" }, .{ .name = "y", .variable = "b" } } };
    try bind(&engine, pattern, value);
    try std.testing.expectEqual(@as(i64, 42), (try engine.eval(try parser.parseExpression(a, "!int_add(a, b)"))).integer);
    try std.testing.expectError(error.Runtime, bind(&engine, .{ .label = "$", .destructured = true, .fields = &.{.{ .name = "absent", .variable = "a" }} }, value));
    try std.testing.expectEqualStrings("absent", engine.failure.?.missing_field);
}

test "empty destructure normalizes to the oracle synthetic binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try parser.parseExpression(a, "({}) -> { 42 }");
    const gathered = try gather(a, text(source, "l"), field(source, "b"));
    try std.testing.expect(!gathered.pattern.destructured);
    try std.testing.expectEqualStrings("$", gathered.pattern.label);
}
