//! loam.source.parse: JSON first, then surface syntax, with shared provenance.
const std = @import("std");
const parser = @import("parser.zig");
pub const runtime = @import("interpreter.zig");
pub const inspection = @import("inspection.zig");
pub const Parsed = struct { program: std.json.Value, meta: inspection.Meta };

pub fn disk(a: std.mem.Allocator, raw: []const u8, path: []const u8) !Parsed {
    return parse(a, raw, .{ .disk = path });
}

pub fn parse(a: std.mem.Allocator, raw: []const u8, origin: inspection.Origin) !Parsed {
    var code = raw;
    if (std.mem.startsWith(u8, code, "#!")) code = if (std.mem.indexOfScalar(u8, code, '\n')) |newline| code[newline + 1 ..] else "";
    if (std.json.parseFromSlice(std.json.Value, a, code, .{ .allocate = .alloc_always })) |parsed| {
        if (runtime.validIr(parsed.value)) return .{ .program = parsed.value, .meta = try inspection.create(a, origin, null) };
    } else |_| {}
    return .{ .program = try parser.parseExpressionLocated(a, code), .meta = try inspection.create(a, origin, code) };
}

pub fn content(a: std.mem.Allocator, cid: []const u8) !inspection.Meta {
    return inspection.create(a, .{ .content = cid }, null);
}
