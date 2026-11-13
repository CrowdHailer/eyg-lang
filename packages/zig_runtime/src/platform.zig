//! Computer effects and relative module loading shared by the CLI and TUI.
//! Pure differential tests deliberately do not attach this host.
const std = @import("std");
const interpreter = @import("interpreter.zig");
const parser = @import("parser.zig");
const git = @import("git.zig");
const computer = @import("computer.zig");
const hub = @import("hub.zig");
const http = @import("http.zig");
const effect_cast = @import("effect_cast.zig");
const sources = @import("source.zig");
const A = std.mem.Allocator;
const J = std.json.Value;
const V = interpreter.Value;
const Engine = interpreter.Engine;

pub const Host = struct {
    allocator: A,
    directory: []const u8 = ".",
    output_context: ?*anyopaque = null,
    output: ?*const fn (?*anyopaque, bool, []const u8) anyerror!void = null,
    loading: std.StringHashMap(void),
    hub_cache: ?hub.Cache = null,

    pub fn init(a: A) Host {
        return .{ .allocator = a, .loading = std.StringHashMap(void).init(a) };
    }
    pub fn attach(self: *Host, engine: *Engine) void {
        engine.effect_handler = effect;
        engine.effect_context = self;
        engine.reference_handler = reference;
        engine.reference_context = self;
        engine.origin = self.directory;
    }
    pub fn packages(self: *Host) !*hub.Cache {
        if (self.hub_cache == null) self.hub_cache = try hub.Cache.configured(self.allocator);
        return &self.hub_cache.?;
    }
};

fn valueField(value: V, name: []const u8) !V {
    if (value != .record) return error.InvalidEffectArgument;
    for (value.record) |f| if (std.mem.eql(u8, name, f.name)) return f.value;
    return error.InvalidEffectArgument;
}
fn text(value: V) ![]const u8 {
    return if (value == .string) value.string else error.InvalidEffectArgument;
}
fn binary(value: V) ![]const u8 {
    return if (value == .binary) value.binary else error.InvalidEffectArgument;
}
fn ok(engine: *Engine, value: V) !V {
    return engine.tag("Ok", value);
}
fn fail(engine: *Engine, err: anyerror) !V {
    return engine.tag("Error", .{ .string = switch (err) {
        error.FileNotFound => "No such file or directory",
        error.NotDir => "Not a directory",
        error.IsDir => "Is a directory",
        error.AccessDenied => "Permission denied",
        error.PathAlreadyExists => "File exists",
        else => @errorName(err),
    } });
}
fn effectPath(host: *Host, engine: *Engine, raw: []const u8) ![]const u8 {
    if (!std.fs.path.isAbsolute(raw) and engine.effect_origin == null) return error.NoSourceDirectory;
    return std.fs.path.resolve(engine.allocator, &.{ engine.effect_origin orelse host.directory, raw });
}
fn pathFailure(engine: *Engine, err: anyerror, raw: []const u8) !V {
    if (err == error.NoSourceDirectory) return engine.tag("Error", .{ .string = try std.fmt.allocPrint(engine.allocator, "relative path \"{s}\" requires a disk-backed source; use CWD or an absolute path", .{raw}) });
    return fail(engine, err);
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn effect(context: ?*anyopaque, engine: *Engine, name: []const u8, lift: V) anyerror!V {
    try effect_cast.validateNative(engine, name, lift);
    const host: *Host = @ptrCast(@alignCast(context.?));
    const a = engine.allocator;
    if (eq(name, "Fetch")) return http.effect(engine, lift);
    if (eq(name, "EYGParse") or eq(name, "DecodeJSON") or eq(name, "CreateKey") or eq(name, "Sign")) return computer.effect(engine, name, lift);
    if (eq(name, "GitQuery")) {
        const req = engine.toPlainJson(lift) catch |err| return fail(engine, err);
        const response = git.request(a, req) catch |err| return fail(engine, err);
        return ok(engine, try engine.fromPlainJson(response));
    }
    if (eq(name, "Inflate")) {
        const bytes = git.inflate(a, try binary(lift)) catch |err| return fail(engine, err);
        return ok(engine, .{ .binary = bytes });
    }
    if (eq(name, "Hash")) {
        const algorithm = try valueField(lift, "algorithm");
        if (algorithm != .tagged) return error.InvalidEffectArgument;
        const bytes = try binary(try valueField(lift, "bytes"));
        if (eq(algorithm.tagged.label, "SHA1")) {
            const digest = try a.alloc(u8, 20);
            std.crypto.hash.Sha1.hash(bytes, digest[0..20], .{});
            return .{ .binary = digest };
        }
        if (eq(algorithm.tagged.label, "SHA256")) {
            const digest = try a.alloc(u8, 32);
            std.crypto.hash.sha2.Sha256.hash(bytes, digest[0..32], .{});
            return .{ .binary = digest };
        }
        return error.UnsupportedHash;
    }
    if (eq(name, "CWD")) return ok(engine, .{ .string = try std.process.getCwdAlloc(a) });
    if (eq(name, "Now")) return .{ .integer = std.time.milliTimestamp() };
    if (eq(name, "Random")) {
        const bound = try effect_cast.asNumber(engine, lift);
        return interpreter.numberValue(@floor(std.crypto.random.float(f64) * bound));
    }
    if (eq(name, "Flip")) return engine.boolean(std.crypto.random.boolean());
    if (eq(name, "Env")) {
        const value = std.process.getEnvVarOwned(a, try text(lift)) catch return engine.tag("None", interpreter.unit());
        return engine.tag("Some", .{ .string = value });
    }
    if (eq(name, "Sleep")) {
        const requested = try effect_cast.asNumber(engine, lift);
        // The oracle uses setTimeout: nonfinite, sub-millisecond and values
        // beyond a signed 32-bit timer duration are scheduled after 1 ms.
        const milliseconds: u64 = if (!std.math.isFinite(requested) or requested < 1 or requested > std.math.maxInt(i32)) 1 else @intFromFloat(requested);
        std.time.sleep(milliseconds * std.time.ns_per_ms);
        return interpreter.unit();
    }
    if (eq(name, "StandardOut") or eq(name, "StandardError")) {
        const output = try text(lift);
        const stderr = eq(name, "StandardError");
        if (host.output) |write| try write(host.output_context, stderr, output) else try (if (stderr) std.io.getStdErr() else std.io.getStdOut()).writeAll(output);
        return interpreter.unit();
    }
    if (eq(name, "ReadFile")) {
        const raw = try text(try valueField(lift, "path"));
        const path = effectPath(host, engine, raw) catch |err| return pathFailure(engine, err, raw);
        const offset = try effect_cast.asNumber(engine, try valueField(lift, "offset"));
        const limit = try effect_cast.asNumber(engine, try valueField(lift, "limit"));
        if (!std.math.isFinite(offset) or !std.math.isFinite(limit) or offset < 0 or offset >= 0x1p64 or limit < 0 or limit > 128 * 1024 * 1024) return fail(engine, error.InvalidReadRange);
        const file = std.fs.cwd().openFile(path, .{}) catch |err| return fail(engine, err);
        defer file.close();
        file.seekTo(@intFromFloat(offset)) catch |err| return fail(engine, err);
        var bytes = std.ArrayList(u8).init(a);
        var remaining: usize = @intFromFloat(limit);
        var chunk: [16 * 1024]u8 = undefined;
        while (remaining > 0) {
            const count = file.read(chunk[0..@min(chunk.len, remaining)]) catch |err| return fail(engine, err);
            if (count == 0) break;
            try bytes.appendSlice(chunk[0..count]);
            remaining -= count;
        }
        return ok(engine, .{ .binary = try bytes.toOwnedSlice() });
    }
    if (eq(name, "ReadDirectory")) {
        const raw = try text(lift);
        const path = effectPath(host, engine, raw) catch |err| return pathFailure(engine, err, raw);
        var directory = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| return fail(engine, err);
        defer directory.close();
        var it = directory.iterate();
        var entries = std.ArrayList(V).init(a);
        while (it.next() catch |err| return fail(engine, err)) |entry| {
            const stat = directory.statFile(entry.name) catch continue;
            const kind = if (stat.kind == .directory) try engine.tag("Directory", interpreter.unit()) else if (stat.kind == .file) try engine.tag("File", .{ .record = try a.dupe(interpreter.Field, &.{.{ .name = "size", .value = .{ .integer = @intCast(stat.size) } }}) }) else continue;
            try entries.append(.{ .record = try a.dupe(interpreter.Field, &.{ .{ .name = "name", .value = .{ .string = try a.dupe(u8, entry.name) } }, .{ .name = "type", .value = kind } }) });
        }
        std.mem.sort(V, entries.items, {}, struct {
            fn less(_: void, x: V, y: V) bool {
                return @import("unicode.zig").utf16LessThan(x.record[0].value.string, y.record[0].value.string);
            }
        }.less);
        var result: ?*const interpreter.List = null;
        var i = entries.items.len;
        while (i > 0) {
            i -= 1;
            result = (try engine.cons(entries.items[i], result)).list;
        }
        return ok(engine, .{ .list = result });
    }
    if (eq(name, "WriteFile") or eq(name, "AppendFile")) {
        const raw = try text(try valueField(lift, "path"));
        const path = effectPath(host, engine, raw) catch |err| return pathFailure(engine, err, raw);
        const bytes = try binary(try valueField(lift, "contents"));
        const file = if (eq(name, "AppendFile")) blk: {
            const fd = std.posix.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true, .CLOEXEC = true }, 0o666) catch |err| return fail(engine, err);
            break :blk std.fs.File{ .handle = fd };
        } else std.fs.cwd().createFile(path, .{}) catch |err| return fail(engine, err);
        defer file.close();
        file.writeAll(bytes) catch |err| return fail(engine, err);
        return ok(engine, interpreter.unit());
    }
    if (eq(name, "DeleteFile")) {
        const raw = try text(lift);
        const path = effectPath(host, engine, raw) catch |err| return pathFailure(engine, err, raw);
        _ = std.fs.cwd().statFile(path) catch |err| return fail(engine, err);
        std.fs.cwd().deleteTree(path) catch |err| return fail(engine, err);
        return ok(engine, interpreter.unit());
    }
    if (eq(name, "MakeDirectory")) {
        const raw = try text(lift);
        const path = effectPath(host, engine, raw) catch |err| return pathFailure(engine, err, raw);
        std.fs.cwd().makePath(path) catch |err| return fail(engine, err);
        return ok(engine, interpreter.unit());
    }
    return error.UnhandledEffect;
}

pub fn reference(context: ?*anyopaque, engine: *Engine, ir: J) anyerror!V {
    const host: *Host = @ptrCast(@alignCast(context.?));
    const code = interpreter.stringField(ir, "0") orelse return error.UndefinedReference;
    if (!eq(code, ".")) return (try host.packages()).resolve(engine, ir);
    const path = try std.fs.path.resolve(engine.allocator, &.{ engine.origin orelse host.directory, interpreter.stringField(ir, "i") orelse return error.UndefinedReference });
    if (host.loading.contains(path)) return error.CyclicImport;
    try host.loading.put(path, {});
    defer _ = host.loading.remove(path);
    const source = try std.fs.cwd().readFileAlloc(engine.allocator, path, 64 * 1024 * 1024);
    const parsed = try sources.disk(engine.allocator, source, path);
    const previous = host.directory;
    host.directory = std.fs.path.dirname(path) orelse ".";
    defer host.directory = previous;
    var imported = Engine.init(engine.allocator);
    host.attach(&imported);
    imported.inspection_meta = parsed.meta;
    // Module initialization is pure in next-tui. Exported functions retain
    // source origins and use their caller's effect host when later invoked.
    imported.effect_handler = null;
    const result = imported.eval(parsed.program) catch |err| {
        engine.failure = imported.failure;
        return err;
    };
    return result;
}

test "imported closures retain their source directory for file effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.makePath("module");
    try temp.dir.writeFile(.{ .sub_path = "module/data", .data = "source-relative" });
    try temp.dir.writeFile(.{ .sub_path = "module/read.eyg", .data = "(_) -> { perform ReadFile({path: \"data\", offset: 0, limit: 99}) }" });
    var host = Host.init(a);
    host.directory = try temp.dir.realpathAlloc(a, ".");
    var engine = Engine.init(a);
    host.attach(&engine);
    const result = try engine.eval(try parser.parse(a, "let read = import \"module/read.eyg\" read({})"));
    try std.testing.expectEqualStrings("Ok", result.tagged.label);
    try std.testing.expectEqualStrings("source-relative", result.tagged.value.binary);
}

test "published module closures require an absolute filesystem path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var host = Host.init(a);
    host.hub_cache = try hub.Cache.init(a, "http://localhost:1");
    const source = try parser.parse(a, "(_) -> { perform ReadFile({path: \"data\", offset: 0, limit: 10}) }");
    const cid = try hub.canonicalCID(a, source);
    _ = try host.hub_cache.?.ingestModule(cid, try hub.canonicalBytes(a, source));
    try host.hub_cache.?.addPackage("demo", 1, cid, 1);
    var engine = Engine.init(a);
    host.attach(&engine);
    const value = try engine.eval(try parser.parseExpression(a, "@demo({})"));
    try std.testing.expectEqualStrings("Error", value.tagged.label);
    try std.testing.expectEqualStrings("relative path \"data\" requires a disk-backed source; use CWD or an absolute path", value.tagged.value.string);
}

test "relative module initializers do not run host effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(.{ .sub_path = "effect.eyg", .data = "perform StandardOut(\"must not be emitted\")" });
    var host = Host.init(a);
    host.directory = try temp.dir.realpathAlloc(a, ".");
    var engine = Engine.init(a);
    host.attach(&engine);
    try std.testing.expectError(error.Runtime, engine.eval(try parser.parseExpression(a, "import \"effect.eyg\"")));
    try std.testing.expectEqualStrings("StandardOut", engine.failure.?.unhandled_effect.label);
}

test "host validates the complete lift before resolving a file path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var host = Host.init(a);
    var engine = Engine.init(a);
    const write: V = .{ .record = try a.dupe(interpreter.Field, &.{
        .{ .name = "path", .value = .{ .string = "relative" } },
        .{ .name = "contents", .value = .{ .integer = 0 } },
    }) };
    try std.testing.expectError(error.Runtime, effect(&host, &engine, "WriteFile", write));
    try std.testing.expectEqualStrings("Binary", engine.failure.?.incorrect_term.expected);
    try std.testing.expectError(error.Runtime, effect(&host, &engine, "StandardOut", .{ .integer = 0 }));
    try std.testing.expectEqualStrings("String", engine.failure.?.incorrect_term.expected);
}
