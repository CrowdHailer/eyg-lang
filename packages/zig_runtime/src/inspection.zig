//! Optional source annotations used only by the observable Gleam inspector.
//! Shared source text stays outside the IR; each native node carries two offsets.
const std = @import("std");
const J = std.json.Value;

pub const Span = [2]usize;
pub const Origin = union(enum) { disk: []const u8, content: []const u8, inline_code, pipe, repl };
pub const Source = struct { origin: Origin, code: ?[]const u8 };
pub const Meta = union(enum) {
    none,
    literal: []const u8,
    located: struct { source: *const Source, span: Span = .{ 0, 0 } },

    pub fn at(self: Meta, ir: J) Meta {
        return switch (self) {
            .located => |location| .{ .located = .{ .source = location.source, .span = span(ir) } },
            else => self,
        };
    }
};

pub fn create(a: std.mem.Allocator, origin: Origin, code: ?[]const u8) !Meta {
    const source = try a.create(Source);
    source.* = .{ .origin = origin, .code = code };
    return .{ .located = .{ .source = source } };
}

pub fn span(ir: J) Span {
    if (ir != .object) return .{ 0, 0 };
    const offsets = ir.object.get("_span") orelse return .{ 0, 0 };
    if (offsets != .array or offsets.array.items.len != 2) return .{ 0, 0 };
    const start = offsets.array.items[0];
    const end = offsets.array.items[1];
    if (start != .integer or end != .integer or start.integer < 0 or end.integer < 0) return .{ 0, 0 };
    return .{ @intCast(start.integer), @intCast(end.integer) };
}
