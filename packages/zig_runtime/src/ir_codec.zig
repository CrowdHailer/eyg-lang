//! Validation at the canonical JSON boundary follows the pinned JavaScript
//! codecs, including their accepted padded/whitespace base64 and CID aliases.
const std = @import("std");
const A = std.mem.Allocator;
// Every finite nonnegative JavaScript integer fits in 1024 unsigned bits.
const Wide = std.meta.Int(.unsigned, 1024);
pub fn jsonInteger(value: std.json.Value) ?f64 {
    const number: f64 = switch (value) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .number_string => |s| std.fmt.parseFloat(f64, s) catch return null,
        else => return null,
    };
    return if (std.math.isFinite(number) and @trunc(number) == number) number else null;
}
fn whitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == 12;
}
fn digit64(c: u8) ?u6 {
    return if (c >= 'A' and c <= 'Z') @intCast(c - 'A') else if (c >= 'a' and c <= 'z') @intCast(c - 'a' + 26) else if (c >= '0' and c <= '9') @intCast(c - '0' + 52) else if (c == '+') 62 else if (c == '/') 63 else null;
}
pub fn base64Size(text: []const u8) ?usize {
    var chars: usize = 0;
    // Gleam pads before atob strips ASCII whitespace, using UTF-8 byte length.
    var pads: usize = (4 - text.len % 4) % 4;
    var padding_started = false;
    for (text) |c| {
        if (whitespace(c)) continue;
        if (c == '=') {
            padding_started = true;
            pads += 1;
            continue;
        }
        if (padding_started or digit64(c) == null) return null;
        chars += 1;
    }
    const total = chars + pads;
    if (total % 4 == 0) {
        if (pads > 2) return null;
    } else if (pads != 0) return null;
    if (chars % 4 == 1) return null;
    return chars / 4 * 3 + chars % 4 * 3 / 4;
}
pub fn decodeBase64(allocator: A, text: []const u8) ![]const u8 {
    const size = base64Size(text) orelse return error.InvalidBinary;
    const bytes = try allocator.alloc(u8, size);
    var buffer: u16 = 0;
    var bits: u5 = 0;
    var output: usize = 0;
    for (text) |c| {
        const digit = digit64(c) orelse continue;
        buffer = (buffer << 6) | digit;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            bytes[output] = @intCast((buffer >> @intCast(bits)) & 255);
            output += 1;
        }
        buffer &= (@as(u16, 1) << @intCast(bits)) - 1;
    }
    return bytes;
}
fn base32Body(text: []const u8) ?[]const u8 {
    if (text.len < 2 or text[0] != 'b') return null;
    const payload = text[1..];
    const body_length = std.mem.indexOfScalar(u8, payload, '=') orelse payload.len;
    const body = payload[0..body_length];
    const padding = payload.len - body_length;
    for (body) |c| if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '2' and c <= '7'))) return null;
    const required: usize = switch (body.len % 8) {
        0 => 0,
        2 => 6,
        4 => 4,
        5 => 3,
        7 => 1,
        else => return null,
    };
    if (padding != 0) {
        if (padding != required) return null;
        for (payload[body_length..]) |c| if (c != '=') return null;
    }
    return body;
}
fn roundedInteger(integer: Wide) ?Wide {
    // JavaScript Number rounds an integer to 53 significant bits. Do that
    // directly: LLVM cannot lower u1024<->f64 library calls on Android ARM64.
    var high = integer;
    var base: usize = 0;
    while (high > std.math.maxInt(u64)) : (base += 64) high >>= 64;
    const chunk: u64 = @intCast(high);
    const bits = base + (64 - @as(usize, @clz(chunk)));
    if (bits <= 53) return integer;
    const shift: std.math.Log2Int(Wide) = @intCast(bits - 53);
    var significant = integer >> shift;
    const remainder = integer & ((@as(Wide, 1) << shift) - 1);
    const half = @as(Wide, 1) << (shift - 1);
    if (remainder > half or (remainder == half and significant & 1 != 0)) significant += 1;
    if (bits == @bitSizeOf(Wide) and significant == @as(Wide, 1) << 53) return null;
    return significant << shift;
}
const Reader = struct {
    text: []const u8,
    pos: usize = 0,
    bits: u5 = 0,
    buffer: u16 = 0,
    consumed: usize = 0,
    fn readByte(self: *Reader) ?u8 {
        while (self.bits < 8) {
            if (self.pos == self.text.len) return null;
            const c = std.ascii.toLower(self.text[self.pos]);
            self.pos += 1;
            const value: u16 = if (c <= '7') c - '2' + 26 else c - 'a';
            self.buffer = (self.buffer << 5) | value;
            self.bits += 5;
        }
        self.bits -= 8;
        const byte: u8 = @intCast((self.buffer >> @intCast(self.bits)) & 255);
        self.buffer &= (@as(u16, 1) << @intCast(self.bits)) - 1;
        self.consumed += 1;
        return byte;
    }
    fn varint(self: *Reader) ?Wide {
        const remaining = self.text.len * 5 / 8 - self.consumed;
        if (remaining <= 8) {
            // gleb128's small-buffer path first converts all remaining little
            // endian bytes to a JavaScript Number. Preserve that rounding,
            // even when the value being read is only the first varint.
            var copy = self.*;
            var raw: Wide = 0;
            for (0..remaining) |index| raw |= @as(Wide, copy.readByte().?) << @intCast(index * 8);
            const rounded = roundedInteger(raw) orelse return null;
            var result: Wide = 0;
            var index: usize = 0;
            while (index < remaining) : (index += 1) {
                _ = self.readByte() orelse return null;
                const byte: u8 = @truncate(rounded >> @intCast(index * 8));
                result = roundedInteger(result | (@as(Wide, byte & 127) << @intCast(index * 7))) orelse return null;
                if (byte < 128) return result;
            }
            return null;
        }
        var number: Wide = 0;
        var shift: usize = 0;
        while (true) : (shift += 7) {
            const byte = self.readByte() orelse return null;
            const value = byte & 127;
            if (shift >= 1024) {
                // gleb128 computes value * 2**shift. Even a zero digit is
                // NaN after this exponent overflows JavaScript Number.
                return null;
            } else {
                if (shift == 1022 and value > 3) return null;
                number = roundedInteger(number | (@as(Wide, value) << @intCast(shift))) orelse return null;
            }
            if (byte < 128) return number;
        }
    }
};
pub fn validCid(text: []const u8) bool {
    const body = base32Body(text) orelse return false;
    var reader = Reader{ .text = body };
    if ((reader.varint() orelse return false) != 1) return false;
    _ = reader.varint() orelse return false;
    if ((reader.varint() orelse return false) != 0x12) return false;
    const count = reader.varint() orelse return false;
    return count <= body.len * 5 / 8 - reader.consumed;
}
fn writeVarint(bytes: *std.ArrayList(u8), value: Wide) !void {
    var rest = value;
    while (rest >= 128) : (rest >>= 7) try bytes.append(@as(u8, @intCast(rest & 127)) | 128);
    try bytes.append(@intCast(rest));
}
pub fn canonicalCid(allocator: A, text: []const u8) ![]const u8 {
    const body = base32Body(text) orelse return error.InvalidCid;
    var reader = Reader{ .text = body };
    if ((reader.varint() orelse return error.InvalidCid) != 1) return error.InvalidCid;
    const codec = reader.varint() orelse return error.InvalidCid;
    if ((reader.varint() orelse return error.InvalidCid) != 18) return error.InvalidCid;
    const count = reader.varint() orelse return error.InvalidCid;
    if (count > body.len * 5 / 8 - reader.consumed) return error.InvalidCid;
    var bytes = std.ArrayList(u8).init(allocator);
    try writeVarint(&bytes, 1);
    try writeVarint(&bytes, codec);
    try writeVarint(&bytes, 18);
    try writeVarint(&bytes, count);
    for (0..@intCast(count)) |_| try bytes.append(reader.readByte().?);
    var output = std.ArrayList(u8).init(allocator);
    try output.append('b');
    const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    var buffer: u16 = 0;
    var bits: u5 = 0;
    for (bytes.items) |byte| {
        buffer = (buffer << 8) | byte;
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            try output.append(alphabet[(buffer >> @intCast(bits)) & 31]);
        }
        buffer &= (@as(u16, 1) << @intCast(bits)) - 1;
    }
    if (bits > 0) try output.append(alphabet[(buffer << @intCast(5 - bits)) & 31]);
    return output.toOwnedSlice();
}

test "portable Number rounding preserves ties-to-even and detects infinity" {
    const boundary = @as(Wide, 1) << 53;
    try std.testing.expectEqual(boundary, roundedInteger(boundary + 1).?);
    try std.testing.expectEqual(boundary + 4, roundedInteger(boundary + 3).?);
    try std.testing.expectEqual(@as(Wide, 1) << 1023, roundedInteger(@as(Wide, 1) << 1023).?);
    try std.testing.expect(roundedInteger(std.math.maxInt(Wide)) == null);
}
test "Gleam base64 accepts aliases but pads before whitespace removal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{ "AQ", "AQ==", "AR", "AR==", "A Q\n" }) |text| try std.testing.expectEqualSlices(u8, &.{1}, try decodeBase64(arena.allocator(), text));
    try std.testing.expectEqualSlices(u8, "f", try decodeBase64(arena.allocator(), "Zg="));
    for ([_][]const u8{ "A", "#?", "\tAQ\r\n", "AAAA=", "AQ-_" }) |text| try std.testing.expect(base64Size(text) == null);
}

const Base64Reader = struct {
    text: []const u8,
    position: usize = 0,
    buffer: u16 = 0,
    bits: u5 = 0,
    fn next(self: *Base64Reader) ?u8 {
        while (self.position < self.text.len) {
            const char = self.text[self.position];
            self.position += 1;
            const digit = digit64(char) orelse continue;
            self.buffer = (self.buffer << 6) | digit;
            self.bits += 6;
            if (self.bits >= 8) {
                self.bits -= 8;
                const byte: u8 = @intCast((self.buffer >> @intCast(self.bits)) & 255);
                self.buffer &= (@as(u16, 1) << @intCast(self.bits)) - 1;
                return byte;
            }
        }
        return null;
    }
};
pub fn base64Equal(left: []const u8, right: []const u8) bool {
    const size = base64Size(left) orelse return false;
    if (size != (base64Size(right) orelse return false)) return false;
    var a = Base64Reader{ .text = left };
    var b = Base64Reader{ .text = right };
    for (0..size) |_| if (a.next() != b.next()) return false;
    return true;
}
pub fn cidEqual(left: []const u8, right: []const u8) bool {
    if (!validCid(left) or !validCid(right)) return false;
    var a = Reader{ .text = base32Body(left).? };
    var b = Reader{ .text = base32Body(right).? };
    _ = a.varint();
    _ = b.varint();
    if (a.varint().? != b.varint().?) return false;
    _ = a.varint();
    _ = b.varint();
    const size = a.varint().?;
    if (size != b.varint().?) return false;
    for (0..@intCast(size)) |_| if (a.readByte() != b.readByte()) return false;
    return true;
}

/// ECMAScript Number.toString text, using std Ryu digits and JS layout thresholds.
/// JSON callers encode non-finite numbers as null instead of this display text.
pub fn ecmaNumber(a: A, number: f64) ![]const u8 {
    if (std.math.isNan(number)) return a.dupe(u8, "NaN");
    if (std.math.isInf(number)) return a.dupe(u8, if (number < 0) "-Infinity" else "Infinity");
    var output = std.ArrayList(u8).init(a);
    try writeEcmaNumber(number, output.writer());
    return output.toOwnedSlice();
}
/// Zig's shortest Ryu mantissa with ECMAScript JSON's decimal/exponent layout.
/// Version numbers use JavaScript's integral Number codec even outside its safe
/// range, so using std.json's default `1e18` would hash different module bytes.
fn writeEcmaNumber(number: f64, writer: anytype) !void {
    if (!std.math.isFinite(number)) return error.InvalidIR;
    if (number == 0) return writer.writeByte('0');
    var scratch: [64]u8 = undefined;
    const scientific = try std.fmt.bufPrint(&scratch, "{e}", .{@abs(number)});
    const e = std.mem.indexOfScalar(u8, scientific, 'e') orelse return error.InvalidIR;
    const exponent = try std.fmt.parseInt(i32, scientific[e + 1 ..], 10);
    var digits: [32]u8 = undefined;
    var count: usize = 0;
    for (scientific[0..e]) |c| if (c != '.') {
        digits[count] = c;
        count += 1;
    };
    if (number < 0) try writer.writeByte('-');
    const point = exponent + 1;
    if (point > 0 and point <= 21) {
        const split: usize = @intCast(point);
        if (split >= count) {
            try writer.writeAll(digits[0..count]);
            for (0..split - count) |_| try writer.writeByte('0');
        } else {
            try writer.writeAll(digits[0..split]);
            try writer.writeByte('.');
            try writer.writeAll(digits[split..count]);
        }
    } else if (point <= 0 and point > -6) {
        try writer.writeAll("0.");
        for (0..@intCast(-point)) |_| try writer.writeByte('0');
        try writer.writeAll(digits[0..count]);
    } else {
        try writer.writeByte(digits[0]);
        if (count > 1) {
            try writer.writeByte('.');
            try writer.writeAll(digits[1..count]);
        }
        try writer.writeByte('e');
        if (exponent >= 0) try writer.writeByte('+');
        try writer.print("{d}", .{exponent});
    }
}
