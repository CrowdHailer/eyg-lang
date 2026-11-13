//! Repository-local Git remote configuration, without global/include expansion.
const std = @import("std");
const A = std.mem.Allocator;
const J = std.json.Value;
const Remote = struct { name: []const u8, urls: std.json.Array, push_urls: std.json.Array, fetch: std.json.Array };

pub fn remotes(a: A, path: []const u8) !J {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return parse(a, try file.readToEndAlloc(a, 4 * 1024 * 1024));
}

pub fn parse(a: A, input: []const u8) !J {
    var logical = std.ArrayList(u8).init(a);
    var at: usize = 0;
    // Continuations are removed before parsing; every other escape is decoded
    // only within its value/subsection, preserving comment and quote context.
    while (at < input.len) : (at += 1) {
        if (input[at] == '\\' and at + 1 < input.len and input[at + 1] == '\n') {
            at += 1;
            continue;
        }
        if (input[at] == '\\' and at + 2 < input.len and input[at + 1] == '\r' and input[at + 2] == '\n') {
            at += 2;
            continue;
        }
        try logical.append(input[at]);
    }
    var items = std.ArrayList(Remote).init(a);
    var selected: ?usize = null;
    var lines = std.mem.splitScalar(u8, logical.items, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, try uncomment(a, raw), " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '[') {
            if (line[line.len - 1] != ']') return error.InvalidGitConfig;
            selected = null;
            const section = std.mem.trim(u8, line[1 .. line.len - 1], " \t");
            var name: ?[]const u8 = null;
            if (std.mem.indexOfAny(u8, section, " \t")) |space| {
                if (!std.ascii.eqlIgnoreCase(section[0..space], "remote")) continue;
                const subsection = std.mem.trim(u8, section[space..], " \t");
                if (subsection.len < 2 or subsection[0] != '"' or subsection[subsection.len - 1] != '"') return error.InvalidGitConfig;
                name = try decode(a, subsection, true);
            } else if (std.mem.indexOfScalar(u8, section, '.')) |dot| {
                if (std.ascii.eqlIgnoreCase(section[0..dot], "remote")) name = try std.ascii.allocLowerString(a, section[dot + 1 ..]);
            }
            if (name) |remote_name| {
                for (items.items, 0..) |item, index| if (std.mem.eql(u8, item.name, remote_name)) {
                    selected = index;
                    break;
                };
                if (selected == null) {
                    selected = items.items.len;
                    try items.append(.{ .name = remote_name, .urls = std.json.Array.init(a), .push_urls = std.json.Array.init(a), .fetch = std.json.Array.init(a) });
                }
            }
            continue;
        }
        const index = selected orelse continue;
        const eq = std.mem.indexOfScalar(u8, line, '=');
        const key = std.mem.trim(u8, if (eq) |e| line[0..e] else line, " \t");
        if (key.len == 0 or !std.ascii.isAlphabetic(key[0])) return error.InvalidGitConfig;
        for (key) |c| if (!std.ascii.isAlphanumeric(c) and c != '-') return error.InvalidGitConfig;
        const value = try decode(a, if (eq) |e| std.mem.trim(u8, line[e + 1 ..], " \t") else "true", false);
        const item = &items.items[index];
        if (std.ascii.eqlIgnoreCase(key, "url")) try item.urls.append(.{ .string = value }) else if (std.ascii.eqlIgnoreCase(key, "pushurl")) try item.push_urls.append(.{ .string = value }) else if (std.ascii.eqlIgnoreCase(key, "fetch")) try item.fetch.append(.{ .string = value });
    }
    var result = std.json.Array.init(a);
    for (items.items) |item| {
        var object = std.json.ObjectMap.init(a);
        try object.put("name", .{ .string = item.name });
        try object.put("urls", .{ .array = item.urls });
        try object.put("push_urls", .{ .array = if (item.push_urls.items.len == 0) item.urls else item.push_urls });
        try object.put("fetch", .{ .array = item.fetch });
        try result.append(.{ .object = object });
    }
    return .{ .array = result };
}

fn uncomment(a: A, input: []const u8) ![]const u8 {
    _ = a;
    var quote = false;
    var escape = false;
    for (input, 0..) |c, i| {
        if (escape) {
            escape = false;
            continue;
        }
        if (c == '\\') {
            escape = true;
            continue;
        }
        if (c == '"') quote = !quote;
        if (!quote and (c == '#' or c == ';')) return input[0..i];
    }
    if (quote or escape) return error.InvalidGitConfig;
    return input;
}
fn decode(a: A, input: []const u8, subsection: bool) ![]const u8 {
    var output = std.ArrayList(u8).init(a);
    var quote = false;
    var at: usize = 0;
    while (at < input.len) : (at += 1) {
        const c = input[at];
        if (c == '"') {
            quote = !quote;
            continue;
        }
        if (c == '\\') {
            at += 1;
            if (at >= input.len) return error.InvalidGitConfig;
            const escaped = input[at];
            if (subsection) {
                if (escaped != '"' and escaped != '\\') return error.InvalidGitConfig;
                try output.append(escaped);
            } else try output.append(switch (escaped) {
                'n' => '\n',
                't' => '\t',
                'b' => 8,
                '"' => '"',
                '\\' => '\\',
                else => return error.InvalidGitConfig,
            });
        } else try output.append(c);
    }
    if (quote or !std.unicode.utf8ValidateSlice(output.items)) return error.InvalidGitConfig;
    return output.toOwnedSlice();
}

test "remote values preserve quoted syntax, repetition, case and continuations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try parse(arena.allocator(), "[ReMoTe \"Origin\"]\nURL = \"https://example.test/a#b\" ; comment\nurl = one\\\n-two\npushurl = ssh://example.test/repo\nfetch = +refs/heads/*:refs/remotes/Origin/*\n");
    const remote = parsed.array.items[0].object;
    try std.testing.expectEqualStrings("Origin", remote.get("name").?.string);
    try std.testing.expectEqualStrings("https://example.test/a#b", remote.get("urls").?.array.items[0].string);
    try std.testing.expectEqualStrings("one-two", remote.get("urls").?.array.items[1].string);
    try std.testing.expectEqualStrings("ssh://example.test/repo", remote.get("push_urls").?.array.items[0].string);
}
