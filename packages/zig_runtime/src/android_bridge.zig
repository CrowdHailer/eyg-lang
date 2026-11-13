//! A session based C ABI shared by Android JNI and the host bridge tests.
//! Output bytes remain valid until the next call on that session or destroy.
//! The caller serializes access except cancel, which is safe during a call.
//! The owner keeps the pointer alive until that call returns.
const std = @import("std");
const interpreter = @import("interpreter.zig");
const parser = @import("parser.zig");
const git = @import("git.zig");
const hub = @import("hub.zig");
const http = @import("http.zig");
const computer = @import("computer.zig");
const codec = @import("ir_codec.zig");
const sources = @import("source.zig");
const effect_cast = @import("effect_cast.zig");
const Json = std.json.Value;
const alloc = std.heap.c_allocator;
const Parent = struct { engine: *interpreter.Engine, path: []const u8, hub_cid: ?[]const u8 = null };
const Session = struct {
    arena: std.heap.ArenaAllocator,
    engine: *interpreter.Engine,
    parents: std.ArrayList(Parent),
    loading: std.StringHashMap(void),
    hub: hub.Cache,
    cancelled: std.atomic.Value(bool),
    directory: []const u8 = ".",
    output: []const u8 = "",
    phase: enum { fresh, suspended, done } = .fresh,
};

export fn eyg_android_create() ?*Session {
    const s = alloc.create(Session) catch return null;
    s.arena = std.heap.ArenaAllocator.init(alloc);
    s.cancelled = std.atomic.Value(bool).init(false);
    const a = s.arena.allocator();
    s.engine = a.create(interpreter.Engine) catch {
        s.arena.deinit();
        alloc.destroy(s);
        return null;
    };
    s.engine.* = interpreter.Engine.init(a);
    s.parents = @TypeOf(s.parents).init(a);
    s.loading = std.StringHashMap(void).init(a);
    s.hub = hub.Cache.configured(a) catch {
        s.arena.deinit();
        alloc.destroy(s);
        return null;
    };
    s.hub.transport = cancellableGet;
    s.hub.transport_context = s;
    s.directory = ".";
    s.output = "";
    s.phase = .fresh;
    return s;
}

export fn eyg_android_destroy(optional: ?*Session) void {
    const s = optional orelse return;
    if (s.output.len > 0) alloc.free(s.output);
    s.arena.deinit();
    alloc.destroy(s);
}

export fn eyg_android_cancel(optional: ?*Session) void {
    if (optional) |s| s.cancelled.store(true, .release);
}

fn checkActive(s: *Session) error{Cancelled}!void {
    if (s.cancelled.load(.acquire)) return error.Cancelled;
}

export fn eyg_android_result_len(optional: ?*Session) usize {
    return if (optional) |s| s.output.len else 0;
}

export fn eyg_android_evaluate(optional: ?*Session, input: [*]const u8, len: usize) ?[*]const u8 {
    const s = optional orelse return null;
    evaluate(s, input[0..len]) catch |err| writeError(s, @errorName(err));
    return s.output.ptr;
}

export fn eyg_android_resume(optional: ?*Session, input: [*]const u8, len: usize) ?[*]const u8 {
    const s = optional orelse return null;
    resumeSession(s, input[0..len]) catch |err| writeError(s, @errorName(err));
    return s.output.ptr;
}

/// A separate, bounded VM for synchronous SDK decisions. It cannot suspend or
/// load modules, and never borrows a running foreground session's continuation.
export fn eyg_android_pure(optional: ?*Session, input: [*]const u8, len: usize) ?[*]const u8 {
    const s = optional orelse return null;
    pure(s, input[0..len]) catch |err| writeError(s, @errorName(err));
    return s.output.ptr;
}

fn pure(s: *Session, input: []const u8) !void {
    try checkActive(s);
    if (input.len > 64 * 1024) return error.InputTooLarge;
    const memory = try alloc.alloc(u8, 4 * 1024 * 1024);
    defer alloc.free(memory);
    var fixed = std.heap.FixedBufferAllocator.init(memory);
    const a = fixed.allocator();
    const request = (try std.json.parseFromSlice(Json, a, input, .{ .allocate = .alloc_always })).value;
    if (request != .object) return error.InvalidRequest;
    const source = request.object.get("source") orelse return error.MissingSource;
    if (source != .string or source.string.len > 4096) return error.InvalidPureSource;
    try shallowSource(source.string);
    const requested = request.object.get("max_steps") orelse Json{ .integer = 1000 };
    if (requested != .integer or requested.integer < 1 or requested.integer > 10_000) return error.InvalidStepBudget;
    const budget: usize = @intCast(requested.integer);
    const argument = request.object.get("argument") orelse return error.MissingArgument;
    if (!validSpec(argument, 0)) return error.InvalidInput;
    const ir = blk: {
        // Canonical IR text can select SDK fields that surface EYG identifiers
        // cannot spell (camelCase, reserved words and punctuation).
        if (std.json.parseFromSlice(Json, a, source.string, .{ .allocate = .alloc_always })) |decoded| {
            if (interpreter.validIr(decoded.value)) break :blk decoded.value;
        } else |_| {}
        break :blk try parser.parse(a, source.string);
    };
    try pureIR(ir, 0);
    var engine = interpreter.Engine.init(a);
    engine.max_steps = budget;
    const function = engine.eval(ir) catch |err| return pureFailure(s, &engine, err);
    const spent = engine.steps;
    if (spent >= budget) return error.StepLimit;
    engine.max_steps = budget - spent;
    const value = engine.call(function, &.{try engine.fromJson(argument)}) catch |err| return pureFailure(s, &engine, err);
    try checkActive(s);
    try pureWrite(s, a, try interpreter.object(a, &.{
        .{ "status", .{ .string = "done" } },
        .{ "steps", .{ .integer = @intCast(spent + engine.steps) } },
        .{ "result", try interpreter.object(a, &.{.{ "value", try engine.toJson(value) }}) },
    }));
}

fn pureFailure(s: *Session, engine: *interpreter.Engine, err: anyerror) !void {
    if (engine.failure) |failure| {
        if (failure == .step_limit) return error.StepLimit;
        try pureWrite(s, engine.allocator, try interpreter.object(engine.allocator, &.{
            .{ "status", .{ .string = "done" } },
            .{ "result", try interpreter.object(engine.allocator, &.{.{ "break", try engine.reasonJson(failure) }}) },
        }));
    } else return err;
}

fn pureWrite(s: *Session, a: std.mem.Allocator, value: Json) !void {
    const output = try std.json.stringifyAlloc(a, value, .{});
    if (output.len > 64 * 1024) return error.PureOutputTooLarge;
    const owned = try alloc.dupe(u8, output);
    if (s.output.len > 0) alloc.free(s.output);
    s.output = owned;
}

fn pureIR(ir: Json, depth: usize) !void {
    if (depth > 128 or ir != .object) return error.InvalidPureSource;
    const code = interpreter.stringField(ir, "0") orelse return error.InvalidPureSource;
    if (std.mem.eql(u8, code, "p") or std.mem.eql(u8, code, "h")) return error.PureEffectsNotAllowed;
    if (std.mem.eql(u8, code, ".") or std.mem.eql(u8, code, "@") or std.mem.eql(u8, code, "#")) return error.PureReferencesNotAllowed;
    // These operations can traverse shared DAGs or perform adversarial
    // superlinear substring searches outside the VM step loop. They remain
    // available in the ordinary asynchronous interpreter.
    if (std.mem.eql(u8, code, "b")) {
        const name = interpreter.stringField(ir, "l") orelse "";
        for ([_][]const u8{ "equal", "string_split", "string_split_once", "string_replace" }) |blocked| {
            if (std.mem.eql(u8, name, blocked)) return error.PureBuiltinNotBounded;
        }
    }
    if (std.mem.eql(u8, code, "a")) {
        try pureIR(interpreter.field(ir, "f"), depth + 1);
        try pureIR(interpreter.field(ir, "a"), depth + 1);
    } else if (std.mem.eql(u8, code, "l")) {
        try pureIR(interpreter.field(ir, "v"), depth + 1);
        try pureIR(interpreter.field(ir, "t"), depth + 1);
    } else if (std.mem.eql(u8, code, "f")) try pureIR(interpreter.field(ir, "b"), depth + 1);
}

fn shallowSource(source: []const u8) !void {
    var string = false;
    var escaped = false;
    var nesting: usize = 0;
    for (source) |byte| {
        if (string) {
            if (escaped) escaped = false else if (byte == '\\') escaped = true else if (byte == '"') string = false;
        } else if (byte == '"') {
            string = true;
        } else if (byte == '(' or byte == '[' or byte == '{') {
            nesting += 1;
            if (nesting > 64) return error.InvalidPureSource;
        } else if (byte == ')' or byte == ']' or byte == '}') {
            nesting -|= 1;
        }
    }
}

fn evaluate(s: *Session, input: []const u8) !void {
    try checkActive(s);
    if (input.len > 16 * 1024 * 1024) return error.InputTooLarge;
    if (s.phase == .suspended) return error.AwaitingEffectReply;
    _ = s.arena.reset(.free_all);
    const a = s.arena.allocator();
    s.engine = try a.create(interpreter.Engine);
    s.engine.* = interpreter.Engine.init(a);
    s.parents = @TypeOf(s.parents).init(a);
    s.loading = std.StringHashMap(void).init(a);
    s.hub = try hub.Cache.configured(a);
    const parsed = try std.json.parseFromSlice(Json, a, input, .{ .allocate = .alloc_always });
    if (parsed.value != .object) return error.InvalidRequest;
    if (parsed.value.object.get("hubOrigin")) |origin| {
        if (origin != .string) return error.InvalidHubOrigin;
        s.hub = try hub.Cache.init(a, origin.string);
    }
    s.hub.transport = cancellableGet;
    s.hub.transport_context = s;
    if (parsed.value.object.get("packages")) |packages| {
        try s.hub.ingestPackages(packages);
        s.hub.transport = fixtureGet;
    }
    const directory: Json = parsed.value.object.get("directory") orelse .{ .string = "." };
    if (directory != .string) return error.InvalidDirectory;
    s.directory = try std.fs.path.resolve(a, &.{try nativePath(a, directory.string)});
    attach(s, s.engine, s.directory);
    const ir = if (parsed.value.object.get("program")) |program| program else blk: {
        const source = parsed.value.object.get("source") orelse return error.MissingSource;
        if (source != .string) return error.InvalidSource;
        break :blk try parser.parse(a, source.string);
    };
    if (parsed.value.object.get("input")) |input_value| {
        if (!validSpec(input_value, 0)) return error.InvalidInput;
        try s.engine.bind("input", try s.engine.fromJson(input_value));
    }
    s.phase = .fresh;
    try checkActive(s);
    const value = s.engine.eval(ir) catch |err| return completeError(s, err);
    try complete(s, value);
}

fn resumeSession(s: *Session, input: []const u8) !void {
    try checkActive(s);
    if (s.phase != .suspended) return error.NoPendingEffect;
    if (input.len > 16 * 1024 * 1024) return error.InputTooLarge;
    const parsed = try std.json.parseFromSlice(Json, s.arena.allocator(), input, .{ .allocate = .alloc_always });
    if (!validSpec(parsed.value, 0)) return error.InvalidReply;
    const reply = try s.engine.fromJson(parsed.value);
    const value = s.engine.@"resume"(reply) catch |err| return completeError(s, err);
    try complete(s, value);
}

fn complete(s: *Session, value: interpreter.Value) !void {
    try checkActive(s);
    var current = value;
    while (s.parents.pop()) |parent| {
        _ = s.loading.remove(parent.path);
        if (parent.hub_cid) |cid| remember(s, cid, current);
        s.engine = parent.engine;
        current = s.engine.@"resume"(current) catch |err| return completeError(s, err);
    }
    s.phase = .done;
    try write(s, try object(s, &.{
        .{ "status", .{ .string = "done" } },
        .{ "result", try object(s, &.{.{ "value", try s.engine.toJson(current) }}) },
    }));
}

fn attach(s: *Session, engine: *interpreter.Engine, directory: []const u8) void {
    engine.origin = directory;
    engine.effect_handler = effect;
    engine.effect_context = s;
    engine.reference_handler = reference;
    engine.reference_context = s;
}

fn nativePath(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, path, "file://")) return path;
    return std.Uri.percentDecodeInPlace(try a.dupe(u8, path[7..]));
}

fn effect(context: ?*anyopaque, engine: *interpreter.Engine, label: []const u8, lift: interpreter.Value) anyerror!interpreter.Value {
    const s: *Session = @ptrCast(@alignCast(context.?));
    try checkActive(s);
    const result = try dispatchEffect(context, engine, label, lift);
    try checkActive(s);
    return result;
}

fn dispatchEffect(context: ?*anyopaque, engine: *interpreter.Engine, label: []const u8, lift: interpreter.Value) anyerror!interpreter.Value {
    const s: *Session = @ptrCast(@alignCast(context.?));
    // Module initialization is pure. Returned functions execute later under
    // the caller's normal phone/native effect handler.
    if (s.parents.items.len != 0) {
        engine.failure = .{ .unhandled_effect = .{ .label = label, .value = lift } };
        return error.Runtime;
    }
    try effect_cast.validateNative(engine, label, lift);
    if (std.mem.eql(u8, label, "Fetch")) return http.effect(engine, lift);
    if (std.mem.eql(u8, label, "EYGParse") or std.mem.eql(u8, label, "DecodeJSON") or std.mem.eql(u8, label, "CreateKey") or std.mem.eql(u8, label, "Sign")) return computer.effect(engine, label, lift);
    if (std.mem.eql(u8, label, "Hash")) {
        const algorithm = try valueField(engine, lift, "algorithm");
        const bytes = try valueField(engine, lift, "bytes");
        if (algorithm != .tagged) return badTerm(engine, "Tagged", algorithm);
        if (bytes != .binary) return badTerm(engine, "Binary", bytes);
        if (std.mem.eql(u8, algorithm.tagged.label, "SHA256")) {
            const digest = try engine.allocator.alloc(u8, 32);
            std.crypto.hash.sha2.Sha256.hash(bytes.binary, digest[0..32], .{});
            return .{ .binary = digest };
        }
        if (std.mem.eql(u8, algorithm.tagged.label, "SHA1")) {
            const digest = try engine.allocator.alloc(u8, 20);
            std.crypto.hash.Sha1.hash(bytes.binary, digest[0..20], .{});
            return .{ .binary = digest };
        }
        return badTerm(engine, "Variant better error needed", algorithm);
    }
    if (std.mem.eql(u8, label, "Inflate")) {
        if (lift != .binary) return badTerm(engine, "Binary", lift);
        const bytes = git.inflate(engine.allocator, lift.binary) catch |err| return engine.tag("Error", .{ .string = @errorName(err) });
        return engine.tag("Ok", .{ .binary = bytes });
    }
    if (std.mem.eql(u8, label, "GitQuery")) {
        var request = try engine.toPlainJson(lift);
        if (request != .object) return engine.tag("Error", .{ .string = "InvalidGitRequest" });
        const repo: Json = request.object.get("repo") orelse .{ .string = "." };
        if (repo != .string) return engine.tag("Error", .{ .string = "InvalidRepositoryPath" });
        const path = try std.fs.path.resolve(engine.allocator, &.{ engine.effect_origin orelse s.directory, try nativePath(engine.allocator, repo.string) });
        try request.object.put("repo", .{ .string = path });
        const response = git.request(engine.allocator, request) catch |err| return engine.tag("Error", .{ .string = @errorName(err) });
        return engine.tag("Ok", try engine.fromPlainJson(response));
    }
    engine.failure = .{ .unhandled_effect = .{ .label = label, .value = lift } };
    return error.Runtime;
}

fn badTerm(engine: *interpreter.Engine, expected: []const u8, got: interpreter.Value) error{Runtime} {
    engine.failure = .{ .incorrect_term = .{ .expected = expected, .got = got } };
    return error.Runtime;
}

fn valueField(engine: *interpreter.Engine, value: interpreter.Value, name: []const u8) anyerror!interpreter.Value {
    if (value != .record) return badTerm(engine, "Record", value);
    for (value.record) |field| if (std.mem.eql(u8, field.name, name)) return field.value;
    engine.failure = .{ .missing_field = name };
    return error.Runtime;
}

fn reference(context: ?*anyopaque, engine: *interpreter.Engine, ir: Json) anyerror!interpreter.Value {
    const s: *Session = @ptrCast(@alignCast(context.?));
    try checkActive(s);
    const code = interpreter.stringField(ir, "0") orelse "";
    if (std.mem.eql(u8, code, "#") or std.mem.eql(u8, code, "@")) {
        if (s.parents.getLastOrNull()) |parent| if (parent.hub_cid != null and std.mem.eql(u8, code, "@") and interpreter.field(ir, "l") == .null) {
            engine.failure = .{ .undefined_reference = ir };
            return error.Runtime;
        };
        const cid = s.hub.referenceCID(ir) catch |err| {
            if (err == error.OutOfMemory) return err;
            engine.failure = .{ .undefined_reference = ir };
            return error.Runtime;
        };
        if (s.hub.modules.get(cid)) |module| if (module.value) |value| return value;
        const tree = s.hub.resolveIR(ir) catch |err| {
            if (err == error.OutOfMemory) return err;
            engine.failure = .{ .undefined_reference = ir };
            return error.Runtime;
        };
        try checkActive(s);
        const key = try std.mem.concat(engine.allocator, u8, &.{ "hub:", cid });
        return load(s, engine, tree, key, s.directory, cid, try sources.content(engine.allocator, cid));
    }
    if (!std.mem.eql(u8, code, ".")) {
        engine.failure = .{ .undefined_reference = ir };
        return error.Runtime;
    }
    const a = engine.allocator;
    if (s.parents.items.len >= 64) return error.ImportDepthLimit;
    if (s.parents.getLastOrNull()) |parent| if (parent.hub_cid != null) {
        engine.failure = .{ .undefined_reference = ir };
        return error.Runtime;
    };
    const location = interpreter.stringField(ir, "i") orelse return error.InvalidImport;
    const path = try std.fs.path.resolve(a, &.{ engine.origin orelse s.directory, try nativePath(a, location) });
    if (s.loading.contains(path)) return error.CyclicImport;
    const source = std.fs.cwd().readFileAlloc(a, path, 64 * 1024 * 1024) catch {
        engine.failure = .{ .undefined_reference = ir };
        return error.Runtime;
    };
    try checkActive(s);
    const parsed = try sources.disk(a, source, path);
    return load(s, engine, parsed.program, path, std.fs.path.dirname(path) orelse ".", null, parsed.meta);
}

fn load(s: *Session, engine: *interpreter.Engine, tree: Json, path: []const u8, directory: []const u8, cid: ?[]const u8, meta: interpreter.InspectionMeta) anyerror!interpreter.Value {
    try checkActive(s);
    const a = engine.allocator;
    if (s.parents.items.len >= 64) return error.ImportDepthLimit;
    if (s.loading.contains(path)) return error.CyclicImport;
    try s.loading.put(path, {});
    try s.parents.append(.{ .engine = engine, .path = path, .hub_cid = cid });
    const imported = try a.create(interpreter.Engine);
    imported.* = interpreter.Engine.init(a);
    attach(s, imported, directory);
    imported.inspection_meta = meta;
    imported.effect_handler = null;
    s.engine = imported;
    // Keep the child engine and parent frame until initialization returns,
    // preserving the child diagnostic if a nested reference fails.
    const result = try imported.eval(tree);
    _ = s.parents.pop();
    _ = s.loading.remove(path);
    if (cid) |key| remember(s, key, result);
    s.engine = engine;
    return result;
}

fn remember(s: *Session, cid: []const u8, value: interpreter.Value) void {
    if (s.hub.modules.getPtr(cid)) |module| module.value = value;
}

fn fixtureGet(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8) anyerror!hub.Response {
    return error.NoModule;
}

fn cancellableGet(context: ?*anyopaque, a: std.mem.Allocator, url: []const u8) anyerror!hub.Response {
    const s: *Session = @ptrCast(@alignCast(context.?));
    try checkActive(s);
    const response = http.get(a, url) catch |err| {
        try checkActive(s);
        return err;
    };
    try checkActive(s);
    return response;
}

fn completeError(s: *Session, err: anyerror) !void {
    try checkActive(s);
    if (err != error.Runtime) return err;
    const failure = s.engine.failure orelse return error.MissingFailure;
    if (failure == .unhandled_effect and s.parents.items.len == 0) {
        s.phase = .suspended;
        const pending = failure.unhandled_effect;
        try write(s, try object(s, &.{
            .{ "status", .{ .string = "effect" } },
            .{ "effect", try object(s, &.{
                .{ "label", .{ .string = pending.label } },
                .{ "value", try s.engine.toJson(pending.value) },
            }) },
        }));
    } else {
        s.phase = .done;
        try write(s, try object(s, &.{
            .{ "status", .{ .string = "done" } },
            .{ "result", try object(s, &.{.{ "break", try s.engine.reasonJson(failure) }}) },
        }));
    }
}

fn object(s: *Session, fields: []const struct { []const u8, Json }) !Json {
    var result = std.json.ObjectMap.init(s.arena.allocator());
    for (fields) |field| try result.put(field[0], field[1]);
    return .{ .object = result };
}
fn write(s: *Session, value: Json) !void {
    const output = try std.json.stringifyAlloc(alloc, value, .{});
    if (s.output.len > 0) alloc.free(s.output);
    s.output = output;
}
fn writeError(s: *Session, reason: []const u8) void {
    const output = std.fmt.allocPrint(alloc, "{{\"status\":\"error\",\"error\":\"{s}\"}}", .{reason}) catch return;
    if (s.output.len > 0) alloc.free(s.output);
    s.output = output;
}

fn validSpec(value: Json, depth: usize) bool {
    if (depth > 128 or value != .object or value.object.count() != 1) return false;
    if (value.object.get("integer")) |i| return codec.jsonInteger(i) != null;
    if (value.object.get("string")) |s| return s == .string;
    if (value.object.get("binary")) |b| {
        if (b != .object) return false;
        const slash = b.object.get("/") orelse return false;
        if (slash != .object) return false;
        const bytes = slash.object.get("bytes") orelse return false;
        if (bytes != .string) return false;
        return codec.base64Size(bytes.string) != null;
    }
    if (value.object.get("record")) |r| {
        if (r != .object) return false;
        for (r.object.values()) |v| if (!validSpec(v, depth + 1)) return false;
        return true;
    }
    if (value.object.get("list")) |list| {
        if (list != .array) return false;
        for (list.array.items) |v| if (!validSpec(v, depth + 1)) return false;
        return true;
    }
    if (value.object.get("tagged")) |t| {
        if (t != .object) return false;
        const label = t.object.get("label") orelse return false;
        const inner = t.object.get("value") orelse return false;
        return label == .string and validSpec(inner, depth + 1);
    }
    return false;
}
