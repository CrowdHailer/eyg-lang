//! Deterministic computer effects for the oracle test transport. Never touches
//! the real filesystem, clock, environment or network.
const std = @import("std");
const runtime = @import("interpreter.zig");
const platform = @import("platform.zig");
const effect_cast = @import("effect_cast.zig");
const A = std.mem.Allocator;
const J = std.json.Value;
const V = runtime.Value;
const Engine = runtime.Engine;

pub const Handler = struct {
    allocator: A,
    entries: std.StringHashMap(?[]const u8),
    host: platform.Host,

    pub fn init(a: A, files: J) !Handler {
        var self = Handler{ .allocator = a, .entries = std.StringHashMap(?[]const u8).init(a), .host = platform.Host.init(a) };
        try self.entries.put("/", null);
        if (files == .object) {
            var it = files.object.iterator();
            while (it.next()) |entry| {
                const fixture_path = try self.path(entry.key_ptr.*);
                try self.makeDirectory(std.fs.path.dirname(fixture_path) orelse "/");
                if (entry.value_ptr.* == .string) try self.entries.put(fixture_path, entry.value_ptr.string);
            }
        }
        return self;
    }
    fn path(self: *Handler, raw: []const u8) ![]const u8 {
        if (std.mem.indexOfScalar(u8, raw, 0) != null) return error.InvalidPath;
        return std.fs.path.resolve(self.allocator, &.{ "/", raw });
    }
    fn makeDirectory(self: *Handler, path_: []const u8) !void {
        if (self.entries.get(path_)) |entry| {
            if (entry != null) return error.PathAlreadyExists;
            return;
        }
        try self.makeDirectory(std.fs.path.dirname(path_) orelse "/");
        try self.entries.put(path_, null);
    }
    fn inspect(self: *Handler, path_: []const u8) !?[]const u8 {
        if (self.entries.get(path_)) |entry| return entry;
        var parent = std.fs.path.dirname(path_);
        while (parent) |part| {
            if (self.entries.get(part)) |entry| if (entry != null) return error.NotDir;
            if (std.mem.eql(u8, part, "/")) break;
            parent = std.fs.path.dirname(part);
        }
        return error.FileNotFound;
    }
    pub fn readFile(self: *Handler, name: []const u8) ![]const u8 {
        return (try self.inspect(try self.path(name))) orelse error.IsDir;
    }
    pub fn effect(self: *Handler, engine: *Engine, name: []const u8, lift: V) anyerror!V {
        try effect_cast.validate(engine, name, lift);
        const a = self.allocator;
        if (eq(name, "CWD")) return engine.tag("Ok", .{ .string = "/" });
        if (eq(name, "Now")) return .{ .integer = 0 };
        if (eq(name, "Env")) return engine.tag("None", runtime.unit());
        if (eq(name, "Sleep") or eq(name, "StandardOut") or eq(name, "StandardError")) return runtime.unit();
        if (eq(name, "Random") or eq(name, "Flip")) return error.UnconfiguredRandomFixture;
        if (eq(name, "Fetch")) return engine.tag("Error", .{ .string = "NetworkError(\"None provided\")" });
        if (eq(name, "ReadFile")) {
            const raw = try text(try field(lift, "path"));
            const offset = try effect_cast.asNumber(engine, try field(lift, "offset"));
            const limit = try effect_cast.asNumber(engine, try field(lift, "limit"));
            if (offset < 0 or limit < 0) return failure(engine, error.InvalidArgument);
            const bytes = self.readFile(raw) catch |err| return failure(engine, err);
            const size: f64 = @floatFromInt(bytes.len);
            if (offset >= size or std.math.isNan(offset)) return engine.tag("Ok", .{ .binary = "" });
            const begin: usize = @intFromFloat(offset);
            const remaining = bytes.len - begin;
            const count: usize = if (limit < @as(f64, @floatFromInt(remaining))) @intFromFloat(limit) else remaining;
            return engine.tag("Ok", .{ .binary = bytes[begin..][0..count] });
        }
        if (eq(name, "WriteFile") or eq(name, "AppendFile")) {
            const path_ = self.path(try text(try field(lift, "path"))) catch |err| return failure(engine, err);
            const bytes = try binary(try field(lift, "contents"));
            const old = self.inspect(path_) catch |err| switch (err) {
                error.FileNotFound => @as(?[]const u8, ""),
                else => return failure(engine, err),
            };
            if (old == null) return failure(engine, error.IsDir);
            const parent = self.inspect(std.fs.path.dirname(path_) orelse "/") catch |err| return failure(engine, err);
            if (parent != null) return failure(engine, error.NotDir);
            const content = if (eq(name, "AppendFile")) try std.mem.concat(a, u8, &.{ old.?, bytes }) else bytes;
            try self.entries.put(path_, content);
            return engine.tag("Ok", runtime.unit());
        }
        if (eq(name, "MakeDirectory")) {
            const path_ = self.path(try text(lift)) catch |err| return failure(engine, err);
            self.makeDirectory(path_) catch |err| return failure(engine, err);
            return engine.tag("Ok", runtime.unit());
        }
        if (eq(name, "DeleteFile")) {
            const path_ = self.path(try text(lift)) catch |err| return failure(engine, err);
            _ = self.inspect(path_) catch |err| return failure(engine, err);
            if (eq(path_, "/")) return failure(engine, error.ResourceBusy);
            const prefix = try std.mem.concat(a, u8, &.{ path_, "/" });
            var deleted = std.ArrayList([]const u8).init(a);
            var it = self.entries.keyIterator();
            while (it.next()) |key| if (eq(key.*, path_) or std.mem.startsWith(u8, key.*, prefix)) try deleted.append(key.*);
            for (deleted.items) |key| _ = self.entries.remove(key);
            return engine.tag("Ok", runtime.unit());
        }
        if (eq(name, "ReadDirectory")) {
            const path_ = self.path(try text(lift)) catch |err| return failure(engine, err);
            const entry = self.inspect(path_) catch |err| return failure(engine, err);
            if (entry != null) return failure(engine, error.NotDir);
            const prefix = if (eq(path_, "/")) "/" else try std.mem.concat(a, u8, &.{ path_, "/" });
            var names = std.ArrayList([]const u8).init(a);
            var it = self.entries.keyIterator();
            while (it.next()) |key| {
                if (!std.mem.startsWith(u8, key.*, prefix) or key.len <= prefix.len) continue;
                const rest = key.*[prefix.len..];
                if (std.mem.indexOfScalar(u8, rest, '/') == null) try names.append(rest);
            }
            std.mem.sort([]const u8, names.items, {}, struct {
                fn less(_: void, x: []const u8, y: []const u8) bool {
                    return @import("unicode.zig").utf16LessThan(x, y);
                }
            }.less);
            var list: ?*const runtime.List = null;
            var i = names.items.len;
            while (i > 0) {
                i -= 1;
                const child_name = names.items[i];
                const child_path = try std.mem.concat(a, u8, &.{ prefix, child_name });
                const bytes = self.entries.get(child_path).?;
                const kind = if (bytes) |data| try engine.tag("File", .{ .record = try a.dupe(runtime.Field, &.{.{ .name = "size", .value = .{ .integer = @intCast(data.len) } }}) }) else try engine.tag("Directory", runtime.unit());
                const child: V = .{ .record = try a.dupe(runtime.Field, &.{ .{ .name = "name", .value = .{ .string = child_name } }, .{ .name = "type", .value = kind } }) };
                list = (try engine.cons(child, list)).list;
            }
            return engine.tag("Ok", .{ .list = list });
        }
        // Hash, parse and signing are pure computer operations. Platform never
        // sees filesystem/network labels through this fallback.
        if (eq(name, "Hash") or eq(name, "CreateKey") or eq(name, "Sign") or eq(name, "DecodeJSON") or eq(name, "EYGParse")) return platform.effect(&self.host, engine, name, lift);
        return error.UnhandledEffect;
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn text(value: V) ![]const u8 {
    return if (value == .string) value.string else error.InvalidEffectArgument;
}
fn binary(value: V) ![]const u8 {
    return if (value == .binary) value.binary else error.InvalidEffectArgument;
}
fn field(value: V, key: []const u8) !V {
    if (value == .record) for (value.record) |f| {
        if (eq(f.name, key)) return f.value;
    };
    return error.InvalidEffectArgument;
}
fn failure(engine: *Engine, err: anyerror) !V {
    return engine.tag("Error", .{ .string = switch (err) {
        error.FileNotFound => "No such file or directory",
        error.NotDir => "Not a directory",
        error.IsDir => "Is a directory",
        error.InvalidArgument => "Invalid argument",
        error.PathAlreadyExists => "File exists",
        error.ResourceBusy => "Resource busy",
        error.InvalidPath => "ERR_INVALID_ARG_VALUE",
        else => @errorName(err),
    } });
}

test "sandbox reads and mutations stay in the fixture world" {
    const parser = @import("parser.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var engine = Engine.init(a);
    var files = std.json.ObjectMap.init(a);
    try files.put("/dir/a", .{ .string = "hello" });
    var world = try Handler.init(a, .{ .object = files });
    const request = try engine.fromPlainJson(try parser.object(a, &.{ .{ "path", .{ .string = "/dir/a" } }, .{ "offset", .{ .integer = 1 } }, .{ "limit", .{ .integer = 3 } } }));
    const answer = try world.effect(&engine, "ReadFile", request);
    try std.testing.expectEqualStrings("ell", answer.tagged.value.binary);
    _ = try world.effect(&engine, "DeleteFile", .{ .string = "/dir" });
    try std.testing.expectError(error.FileNotFound, world.readFile("/dir/a"));
}

test "sandbox validates before effects and accepts wide Integer read ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var engine = Engine.init(a);
    var files = std.json.ObjectMap.init(a);
    try files.put("/data", .{ .string = "bytes" });
    var world = try Handler.init(a, .{ .object = files });
    try std.testing.expectError(error.Runtime, world.effect(&engine, "StandardOut", .{ .integer = 1 }));
    try std.testing.expectEqualStrings("String", engine.failure.?.incorrect_term.expected);
    const fields = try a.dupe(runtime.Field, &.{
        .{ .name = "path", .value = .{ .string = "/data" } },
        .{ .name = "offset", .value = .{ .integer = 0 } },
        .{ .name = "limit", .value = .{ .javascript_integer = 1e100 } },
    });
    const input: V = .{ .record = fields };
    try std.testing.expectEqualStrings("bytes", (try world.effect(&engine, "ReadFile", input)).tagged.value.binary);
    fields[1].value = .{ .javascript_integer = 1e100 };
    try std.testing.expectEqualStrings("", (try world.effect(&engine, "ReadFile", input)).tagged.value.binary);
    const write: V = .{ .record = try a.dupe(runtime.Field, &.{
        .{ .name = "path", .value = .{ .string = "/new" } },
        .{ .name = "contents", .value = .{ .integer = 0 } },
    }) };
    try std.testing.expectError(error.Runtime, world.effect(&engine, "WriteFile", write));
    try std.testing.expectEqualStrings("Binary", engine.failure.?.incorrect_term.expected);
    try std.testing.expect(!world.entries.contains("/new"));
}
