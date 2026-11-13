//! JSON transport for JavaScript strings, including isolated UTF-16 surrogates.
//! Values normally contain UTF-8. The pinned editor can split a surrogate pair
//! during completion; those individual units use WTF-8 internally and must be
//! escaped on the wire. Standard JSON still owns framing, numbers and escaping.
const std = @import("std");
const J = std.json.Value;

fn string(bytes: []const u8, writer: anytype) !void {
    try writer.writeByte('"');
    var start: usize = 0;
    var i: usize = 0;
    while (i + 2 < bytes.len) {
        if (bytes[i] == 0xed and bytes[i + 1] >= 0xa0 and bytes[i + 1] <= 0xbf and bytes[i + 2] >= 0x80 and bytes[i + 2] <= 0xbf) {
            try std.json.encodeJsonStringChars(bytes[start..i], .{}, writer);
            const unit: u16 = (@as(u16, bytes[i] & 0x0f) << 12) | (@as(u16, bytes[i + 1] & 0x3f) << 6) | @as(u16, bytes[i + 2] & 0x3f);
            try writer.print("\\u{x:0>4}", .{unit});
            i += 3;
            start = i;
        } else i += 1;
    }
    try std.json.encodeJsonStringChars(bytes[start..], .{}, writer);
    try writer.writeByte('"');
}

const Wire = struct {
    value: J,

    pub fn jsonStringify(self: Wire, stream: anytype) @TypeOf(stream.*).Error!void {
        switch (self.value) {
            .string => |bytes| {
                // std's generic slice writer treats invalid UTF-8 as a byte
                // array. Its raw-value API lets us retain the JSON string type.
                try stream.beginWriteRaw();
                try string(bytes, stream.stream);
                stream.endWriteRaw();
            },
            .array => |items| {
                try stream.beginArray();
                for (items.items) |item| try stream.write(Wire{ .value = item });
                try stream.endArray();
            },
            .object => |object| {
                try stream.beginObject();
                var it = object.iterator();
                while (it.next()) |entry| {
                    try stream.beginObjectFieldRaw();
                    try string(entry.key_ptr.*, stream.stream);
                    stream.endObjectFieldRaw();
                    try stream.write(Wire{ .value = entry.value_ptr.* });
                }
                try stream.endObject();
            },
            else => try stream.write(self.value),
        }
    }
};

pub fn write(value: J, writer: anytype) @TypeOf(writer).Error!void {
    try std.json.stringify(Wire{ .value = value }, .{}, writer);
}

pub fn stringifyAlloc(a: std.mem.Allocator, value: J) ![]u8 {
    var out = std.ArrayList(u8).init(a);
    errdefer out.deinit();
    try write(value, out.writer());
    return out.toOwnedSlice();
}

test "wire strings retain isolated JavaScript code units and ordinary scalars" {
    const encoded = try stringifyAlloc(std.testing.allocator, .{ .string = "λ\xed\xb8\x80😀\xed\xa0\x80\n\"\\" });
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("\"λ\\ude00😀\\ud800\\n\\\"\\\\\"", encoded);
}

test "wire retains nested JSON types and surrogate property names" {
    var fields = std.json.ObjectMap.init(std.testing.allocator);
    defer fields.deinit();
    try fields.put("\xed\xb8\x80", .{ .integer = 42 });
    try fields.put("ordinary", .{ .bool = true });
    const encoded = try stringifyAlloc(std.testing.allocator, .{ .object = fields });
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"\\ude00\":42,\"ordinary\":true}", encoded);
}
