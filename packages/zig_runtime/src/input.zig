//! Incremental etui-compatible terminal input parser. Timeout policy is in main.
const std = @import("std");
const unicode = @import("unicode.zig");
const json = @import("parser.zig");
const A = std.mem.Allocator;
const J = std.json.Value;
pub const Parsed = struct { events: std.ArrayList(J), remainder: []const u8 };
const Decoded = struct { event: J, end: usize };
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn key(a: A, name: []const u8) !J {
    return json.object(a, &.{.{ "key", .{ .string = name } }});
}

pub fn parse(a: A, source: []const u8, flush: bool) !Parsed {
    var result = Parsed{ .events = std.ArrayList(J).init(a), .remainder = "" };
    var i: usize = 0;
    while (i < source.len) {
        if (source[i] == 27) {
            if (try escape(a, source, i)) |decoded| {
                try result.events.append(decoded.event);
                i = decoded.end;
            } else {
                if (flush) try result.events.append(try key(a, "esc")) else result.remainder = source[i..];
                break;
            }
        } else {
            const end = unicode.graphemeEnd(source, i);
            const symbol = source[i..end];
            const name: []const u8 = if (eq(symbol, "\r") or eq(symbol, "\n")) "enter" else if (eq(symbol, "\t")) "tab" else if (eq(symbol, "\x08") or eq(symbol, "\x7f")) "backspace" else if (symbol.len == 1 and symbol[0] >= 1 and symbol[0] <= 26) try std.fmt.allocPrint(a, "ctrl+{c}", .{@as(u8, 'a') + symbol[0] - 1}) else symbol;
            try result.events.append(try key(a, name));
            i = end;
        }
    }
    return result;
}

fn escape(a: A, source: []const u8, start: usize) !?Decoded {
    if (start + 1 == source.len) return null;
    const second = source[start + 1];
    if (second != '[' and second != 'O') {
        const end = unicode.graphemeEnd(source, start + 1);
        return .{ .event = try key(a, try std.fmt.allocPrint(a, "alt+{s}", .{source[start + 1 .. end]})), .end = end };
    }
    if (second == 'O') {
        if (start + 2 == source.len) return null;
        const end = unicode.graphemeEnd(source, start + 2);
        return .{ .event = try key(a, baseKey(source[start + 2 .. end])), .end = end };
    }
    const mouse = start + 2 < source.len and source[start + 2] == '<';
    const params_start = start + (if (mouse) @as(usize, 3) else 2);
    var final = params_start;
    while (final < source.len and !(source[final] >= 0x40 and source[final] <= 0x7e)) : (final = unicode.graphemeEnd(source, final)) {}
    if (final == source.len) return null;
    const end = unicode.graphemeEnd(source, final);
    const params = source[params_start..final];
    const final_text = source[final..end];
    if (mouse) return .{ .event = try mouseEvent(a, params, final_text), .end = end };
    if (eq(params, "200") and eq(final_text, "~")) {
        const terminator = "\x1b[201~";
        const closing = std.mem.indexOf(u8, source[end..], terminator) orelse return null;
        return .{ .event = try json.object(a, &.{.{ "paste", .{ .string = source[end..][0..closing] } }}), .end = end + closing + terminator.len };
    }
    var split = std.mem.splitScalar(u8, params, ';');
    const first = split.next() orelse "";
    const modifier = split.next() orelse "";
    const base = if (eq(final_text, "~")) tildeKey(first) else if (eq(final_text, "Z")) "backtab" else baseKey(final_text);
    const n = std.fmt.parseInt(i64, modifier, 10) catch 1;
    const bits = n -% 1;
    return .{ .event = try key(a, try std.fmt.allocPrint(a, "{s}{s}{s}{s}", .{ if (bits & 4 != 0) "ctrl+" else "", if (bits & 2 != 0) "alt+" else "", if (bits & 1 != 0) "shift+" else "", base })), .end = end };
}

fn baseKey(value: []const u8) []const u8 {
    if (eq(value, "A")) return "up";
    if (eq(value, "B")) return "down";
    if (eq(value, "C")) return "right";
    if (eq(value, "D")) return "left";
    if (eq(value, "H")) return "home";
    if (eq(value, "F")) return "end";
    if (eq(value, "P")) return "f1";
    if (eq(value, "Q")) return "f2";
    if (eq(value, "R")) return "f3";
    if (eq(value, "S")) return "f4";
    return value;
}
fn tildeKey(value: []const u8) []const u8 {
    const keys = [_]struct { []const u8, []const u8 }{ .{ "1", "home" }, .{ "2", "insert" }, .{ "3", "delete" }, .{ "4", "end" }, .{ "5", "pageup" }, .{ "6", "pagedown" }, .{ "11", "f1" }, .{ "12", "f2" }, .{ "13", "f3" }, .{ "14", "f4" }, .{ "15", "f5" }, .{ "17", "f6" }, .{ "18", "f7" }, .{ "19", "f8" }, .{ "20", "f9" }, .{ "21", "f10" }, .{ "23", "f11" }, .{ "24", "f12" } };
    for (keys) |pair| if (eq(value, pair[0])) return pair[1];
    return value;
}
fn mouseEvent(a: A, params: []const u8, final: []const u8) !J {
    var split = std.mem.splitScalar(u8, params, ';');
    const cb = std.fmt.parseInt(i64, split.next() orelse "", 10) catch return key(a, try std.fmt.allocPrint(a, "\x1b[<{s}{s}", .{ params, final }));
    const x = std.fmt.parseInt(i64, split.next() orelse "", 10) catch return key(a, try std.fmt.allocPrint(a, "\x1b[<{s}{s}", .{ params, final }));
    const y = std.fmt.parseInt(i64, split.next() orelse "", 10) catch return key(a, try std.fmt.allocPrint(a, "\x1b[<{s}{s}", .{ params, final }));
    if (split.next() != null) return key(a, try std.fmt.allocPrint(a, "\x1b[<{s}{s}", .{ params, final }));
    const button = cb & 3;
    const wheel = cb & 64 != 0;
    const motion = cb & 32 != 0;
    const kind = if (wheel) "scroll" else if (motion and button == 3) "move" else if (motion) "drag" else if (eq(final, "M")) "press" else "release";
    var event = try json.object(a, &.{ .{ "kind", .{ .string = kind } }, .{ "x", .{ .integer = x - 1 } }, .{ "y", .{ .integer = y - 1 } } });
    if (wheel) try event.object.put("up", .{ .bool = button == 0 }) else if (!eq(kind, "move")) try event.object.put("button", .{ .string = if (button == 1) "middle" else if (button == 2) "right" else "left" });
    return json.object(a, &.{.{ "mouse", event }});
}

test "fragmented paste, alternate arrows, modified keys and grapheme input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const partial = try parse(a, "a\x1b[200~hello", false);
    try std.testing.expectEqual(@as(usize, 1), partial.events.items.len);
    try std.testing.expectEqualStrings("\x1b[200~hello", partial.remainder);
    const full = try parse(a, "\x1b[1;6D\x1bOAe\u{0301}", false);
    try std.testing.expectEqualStrings("ctrl+shift+left", full.events.items[0].object.get("key").?.string);
    try std.testing.expectEqualStrings("up", full.events.items[1].object.get("key").?.string);
    try std.testing.expectEqualStrings("e\u{0301}", full.events.items[2].object.get("key").?.string);
    const flushed = try parse(a, "\x1b[1;", true);
    try std.testing.expectEqualStrings("esc", flushed.events.items[0].object.get("key").?.string);
    try std.testing.expectEqualStrings("", flushed.remainder);
}
