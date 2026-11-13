//! The small document algebra used by the Gleam oracle's value printer.
//! Groups choose a flat or broken layout from the same Unicode grapheme width.
const std = @import("std");
const runtime = @import("interpreter.zig");
const unicode = @import("unicode.zig");
const A = std.mem.Allocator;
pub const Doc = struct {
    length: usize,
    content: union(enum) {
        text: []const u8,
        sequence: []const *const Doc,
        line: struct { flat: []const u8, broken: []const u8 },
        nest: *const Doc,
        group: *const Doc,
    },
};
pub const Printer = struct {
    allocator: A,
    pub fn create(self: Printer, size: usize, content: @FieldType(Doc, "content")) !*const Doc {
        const doc = try self.allocator.create(Doc);
        doc.* = .{ .length = size, .content = content };
        return doc;
    }
    pub fn text(self: Printer, value: []const u8) !*const Doc {
        return self.create(length(value), .{ .text = value });
    }
    pub fn sequence(self: Printer, docs: []const *const Doc) !*const Doc {
        var size: usize = 0;
        for (docs) |doc| size +|= doc.length;
        return self.create(size, .{ .sequence = try self.allocator.dupe(*const Doc, docs) });
    }
    pub fn line(self: Printer, flat: []const u8, broken: []const u8) !*const Doc {
        return self.create(length(flat), .{ .line = .{ .flat = flat, .broken = broken } });
    }
    pub fn nest(self: Printer, inner: *const Doc) !*const Doc {
        return self.create(inner.length, .{ .nest = inner });
    }
    pub fn group(self: Printer, inner: *const Doc) !*const Doc {
        return self.create(inner.length, .{ .group = inner });
    }
    pub fn wrap(self: Printer, open: []const u8, inner: *const Doc, close: []const u8) !*const Doc {
        return self.group(try self.sequence(&.{ try self.text(open), try self.nest(try self.sequence(&.{ try self.line("", ""), inner })), try self.line("", ""), try self.text(close) }));
    }
    pub fn separated(self: Printer, items: []const *const Doc, open: []const u8, close: []const u8) !*const Doc {
        if (items.len == 0) return self.text(try std.mem.concat(self.allocator, u8, &.{ open, close }));
        var body = std.ArrayList(*const Doc).init(self.allocator);
        try body.append(try self.line("", ""));
        for (items, 0..) |item, i| {
            if (i > 0) try body.append(try self.line(", ", ","));
            try body.append(item);
        }
        return self.group(try self.sequence(&.{ try self.text(open), try self.nest(try self.sequence(body.items)), try self.line("", ","), try self.text(close) }));
    }
    pub fn quote(self: Printer, value: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).init(self.allocator);
        try out.append('"');
        for (value) |c| switch (c) {
            '\\' => try out.appendSlice("\\\\"),
            '"' => try out.appendSlice("\\\""),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => try out.append(c),
        };
        try out.append('"');
        return out.toOwnedSlice();
    }
    fn document(self: Printer, input: runtime.Value, depth: usize) anyerror!*const Doc {
        if (depth >= 8) return self.text("…");
        return switch (input) {
            .integer => |i| self.text(try runtime.integerText(self.allocator, i)),
            .javascript_integer => |f| self.text(try runtime.numberText(self.allocator, f)),
            .string => |s| self.text(try self.quote(s)),
            .binary => |s| self.text(try std.fmt.allocPrint(self.allocator, "Binary({d} bytes): {s}", .{ s.len, try paddedBase64(self.allocator, s) })),
            .tagged => |t| self.sequence(&.{ try self.text(t.label), try self.wrap("(", try self.document(t.value, depth + 1), ")") }),
            .closure => |c| self.text(try std.fmt.allocPrint(self.allocator, "fn({s}) {{ ... }}", .{c.param})),
            .@"resume" => |captured| self.wrap("Partial(", try self.text(try @import("resume_inspect.zig").head(self.allocator, captured)), ")"),
            .list => |list| blk: {
                var items = std.ArrayList(*const Doc).init(self.allocator);
                var cursor = list;
                while (cursor) |cell| : (cursor = cell.tail) try items.append(try self.document(cell.head, depth + 1));
                break :blk self.separated(items.items, "[", "]");
            },
            .record => |fields| blk: {
                const sorted = try self.allocator.dupe(runtime.Field, fields);
                std.mem.sort(runtime.Field, sorted, {}, struct {
                    fn less(_: void, x: runtime.Field, y: runtime.Field) bool {
                        return unicode.utf16LessThan(x.name, y.name);
                    }
                }.less);
                var items = std.ArrayList(*const Doc).init(self.allocator);
                for (sorted) |f| try items.append(try self.sequence(&.{ try self.text(try std.mem.concat(self.allocator, u8, &.{ f.name, ": " })), try self.document(f.value, depth + 1) }));
                break :blk self.separated(items.items, "{", "}");
            },
            .partial => |p| blk: {
                if (p.kind == .tag and p.args.len == 0) break :blk self.text(p.label);
                const name = switch (p.kind) {
                    .cons => "Cons",
                    .extend => "Extend",
                    .overwrite => "Overwrite",
                    .select => "Select",
                    .tag => "Tag",
                    .match => "Match",
                    .no_cases => "NoCases",
                    .perform => "Perform",
                    .handle => "Handle",
                    .builtin => "Builtin",
                };
                const head = if (p.label.len == 0) name else try std.fmt.allocPrint(self.allocator, "{s}({s}: {s})", .{ name, if (p.kind == .builtin) @as([]const u8, "identifier") else "label", try self.quote(p.label) });
                if (p.args.len == 0) break :blk self.wrap("Partial(", try self.text(head), ")");
                var items = std.ArrayList(*const Doc).init(self.allocator);
                try items.append(try self.text(head));
                for (p.args) |arg| {
                    try items.append(try self.text(","));
                    try items.append(try self.line(" ", ""));
                    try items.append(try self.document(arg, depth + 1));
                }
                break :blk self.wrap("Partial(", try self.sequence(items.items), ")");
            },
        };
    }
};
fn paddedBase64(allocator: A, bytes: []const u8) ![]const u8 {
    const encoder = std.base64.standard.Encoder;
    const output = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    return encoder.encode(output, bytes);
}
fn length(text: []const u8) usize {
    var i: usize = 0;
    var count: usize = 0;
    while (i < text.len) : (count += 1) i = unicode.graphemeEnd(text, i);
    return count;
}
fn emit(doc: *const Doc, out: *std.ArrayList(u8), width: usize, column: *usize, indent: usize, flat: bool) anyerror!void {
    switch (doc.content) {
        .text => |text| {
            try out.appendSlice(text);
            column.* +|= doc.length;
        },
        .sequence => |docs| for (docs) |child| try emit(child, out, width, column, indent, flat),
        .nest => |inner| try emit(inner, out, width, column, indent + 2, flat),
        .group => |inner| try emit(inner, out, width, column, indent, column.* +| inner.length <= width),
        .line => |line| if (flat) {
            try out.appendSlice(line.flat);
            column.* +|= doc.length;
        } else {
            try out.appendSlice(line.broken);
            try out.append('\n');
            try out.appendNTimes(' ', indent);
            column.* = indent;
        },
    }
}
pub fn render(allocator: A, value: runtime.Value, width: usize) ![]const u8 {
    const printer = Printer{ .allocator = allocator };
    const doc = try printer.document(value, 0);
    return renderDocument(allocator, doc, width);
}
test "groups wrap exactly at the column budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var engine = runtime.Engine.init(arena.allocator());
    const list = try engine.cons(.{ .integer = 123 }, (try engine.cons(.{ .integer = 456 }, null)).list);
    try std.testing.expectEqualStrings("Binary(1 bytes): AQ==", try render(arena.allocator(), .{ .binary = &.{1} }, 80));
    try std.testing.expectEqualStrings("[123, 456]", try render(arena.allocator(), list, 10));
    try std.testing.expectEqualStrings("[\n  123,\n  456,\n]", try render(arena.allocator(), list, 9));
}

pub fn renderDocument(allocator: A, doc: *const Doc, width: usize) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    var column: usize = 0;
    try emit(doc, &output, width, &column, 0, true);
    return output.toOwnedSlice();
}
