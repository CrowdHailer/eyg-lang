//! Unicode 16 extended grapheme clusters (UAX #29) and default case mapping.
const std = @import("std");
const data = @import("unicode_data.zig");
const Gcb = enum(u5) { other, cr, lf, control, extend, zwj, ri, prepend, spacing, l, v, t, lv, lvt };
fn properties(cp: u21) u16 {
    var lo: usize = 0;
    var hi = data.ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = data.ranges[mid];
        if (cp < r.first) hi = mid else if (cp > r.last) lo = mid + 1 else return r.flags;
    }
    return 0;
}
fn codepoint(text: []const u8, i: usize) struct { cp: u21, end: usize } {
    const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return .{ .cp = 0xfffd, .end = i + 1 };
    if (i + len > text.len) return .{ .cp = 0xfffd, .end = i + 1 };
    return .{ .cp = std.unicode.utf8Decode(text[i .. i + len]) catch 0xfffd, .end = i + len };
}

/// JavaScript string order compares UTF-16 code units, not UTF-8 bytes or
/// Unicode scalar values. In particular, supplementary characters precede
/// BMP characters at U+E000 and above. No allocation or normalization occurs.
pub fn utf16Order(left: []const u8, right: []const u8) std.math.Order {
    var lhs = Utf16Units{ .text = left };
    var rhs = Utf16Units{ .text = right };
    while (true) {
        const a = lhs.next();
        const b = rhs.next();
        if (a == null) return if (b == null) .eq else .lt;
        if (b == null) return .gt;
        if (a.? < b.?) return .lt;
        if (a.? > b.?) return .gt;
    }
}

pub fn utf16LessThan(left: []const u8, right: []const u8) bool {
    return utf16Order(left, right) == .lt;
}

const Utf16Units = struct {
    text: []const u8,
    at: usize = 0,
    low_surrogate: ?u16 = null,

    fn next(self: *Utf16Units) ?u16 {
        if (self.low_surrogate) |low| {
            self.low_surrogate = null;
            return low;
        }
        if (self.at == self.text.len) return null;
        const first = self.text[self.at];
        if (first < 0x80) {
            self.at += 1;
            return first;
        }
        const point = codepoint(self.text, self.at);
        self.at = point.end;
        if (point.cp <= 0xffff) return @intCast(point.cp);
        const supplementary = point.cp - 0x10000;
        self.low_surrogate = @intCast(0xdc00 + (supplementary & 0x3ff));
        return @intCast(0xd800 + (supplementary >> 10));
    }
};

pub fn graphemeEnd(text: []const u8, start: usize) usize {
    if (start >= text.len) return text.len;
    const first = codepoint(text, start);
    var flags = properties(first.cp);
    var previous: Gcb = @enumFromInt(flags & 31);
    var regional: usize = if (previous == .ri) 1 else 0;
    var pictographic = flags & 32 != 0;
    var after_emoji_zwj = false;
    var consonant = flags & 64 != 0;
    var linker = false;
    var index = first.end;
    while (index < text.len) {
        const current = codepoint(text, index);
        flags = properties(current.cp);
        const next: Gcb = @enumFromInt(flags & 31);
        const joined = if (previous == .cr and next == .lf) true else if (previous == .cr or previous == .lf or previous == .control or next == .cr or next == .lf or next == .control) false else if (previous == .l and (next == .l or next == .v or next == .lv or next == .lvt)) true else if ((previous == .lv or previous == .v) and (next == .v or next == .t)) true else if ((previous == .lvt or previous == .t) and next == .t) true else if (next == .extend or next == .zwj or next == .spacing or previous == .prepend) true else if (consonant and linker and flags & 64 != 0) true else if (after_emoji_zwj and flags & 32 != 0) true else if (previous == .ri and next == .ri and regional % 2 == 1) true else false;
        if (!joined) return index;
        if (next == .ri) regional += 1 else regional = 0;
        after_emoji_zwj = next == .zwj and pictographic;
        if (next != .extend) pictographic = flags & 32 != 0;
        if (flags & 64 != 0) {
            consonant = true;
            linker = false;
        } else if (flags & 128 != 0) {
            linker = linker or consonant;
        } else if (flags & 256 == 0) {
            consonant = false;
            linker = false;
        }
        previous = next;
        index = current.end;
    }
    return text.len;
}
fn mapping(comptime upper: bool, cp: u21) ?[]const u8 {
    const table = if (upper) &data.upper else &data.lower;
    var lo: usize = 0;
    var hi: usize = table.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (cp < table[mid].cp) hi = mid else if (cp > table[mid].cp) lo = mid + 1 else return table[mid].text;
    }
    return null;
}
pub fn changeCase(allocator: std.mem.Allocator, text: []const u8, upper: bool) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    var before_cased = false;
    while (i < text.len) {
        const point = codepoint(text, i);
        const flags = properties(point.cp);
        if (!upper and point.cp == 0x3a3 and before_cased) {
            var next = point.end;
            var after_cased = false;
            while (next < text.len) {
                const p = codepoint(text, next);
                const f = properties(p.cp);
                if (f & 1024 == 0) {
                    after_cased = f & 512 != 0;
                    break;
                }
                next = p.end;
            }
            try output.appendSlice(if (after_cased) "σ" else "ς");
        } else if (if (upper) mapping(true, point.cp) else mapping(false, point.cp)) |mapped| {
            try output.appendSlice(mapped);
        } else try output.appendSlice(text[i..point.end]);
        if (flags & 1024 == 0) before_cased = flags & 512 != 0;
        i = point.end;
    }
    return output.toOwnedSlice();
}
test "extended grapheme clusters and Unicode case" {
    const sample = "ß↑e̊👩🏿‍🚀🇬🇧क्ष";
    var index: usize = 0;
    var count: usize = 0;
    while (index < sample.len) : (count += 1) index = graphemeEnd(sample, index);
    try std.testing.expectEqual(@as(usize, 6), count);
    const upper = try changeCase(std.testing.allocator, "Straße κόσμος", true);
    defer std.testing.allocator.free(upper);
    try std.testing.expectEqualStrings("STRASSE ΚΌΣΜΟΣ", upper);
    const lower = try changeCase(std.testing.allocator, "ΟΣ ΟΣΑ", false);
    defer std.testing.allocator.free(lower);
    try std.testing.expectEqualStrings("ος οσα", lower);
}

test "JavaScript string order uses UTF-16 units" {
    const ordered = [_][]const u8{ "", "a", "aa", "λ", "\u{10000}", "\u{10000}a", "\u{10001}", "😀", "\u{e000}", "\u{ffff}" };
    for (ordered, 0..) |left, i| {
        try std.testing.expectEqual(std.math.Order.eq, utf16Order(left, left));
        for (ordered[i + 1 ..]) |right| {
            try std.testing.expectEqual(std.math.Order.lt, utf16Order(left, right));
            try std.testing.expectEqual(std.math.Order.gt, utf16Order(right, left));
        }
    }
}
