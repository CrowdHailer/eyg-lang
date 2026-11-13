//! The pinned computer harness decodes before invoking any host operation.
//! Its runtime casts are deliberately narrower than static effect types: unit
//! requires an empty record, while CreateKey ignores its options payload.
const std = @import("std");
pub const runtime = @import("interpreter.zig");
const V = runtime.Value;
const Engine = runtime.Engine;
const Error = error{Runtime};

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn incorrect(engine: *Engine, expected: []const u8, got: V) Error {
    engine.failure = .{ .incorrect_term = .{ .expected = expected, .got = got } };
    return error.Runtime;
}
fn missing(engine: *Engine, name: []const u8) Error {
    engine.failure = .{ .missing_field = name };
    return error.Runtime;
}
pub fn asString(engine: *Engine, value: V) Error![]const u8 {
    return if (value == .string) value.string else incorrect(engine, "String", value);
}
pub fn asBinary(engine: *Engine, value: V) Error![]const u8 {
    return if (value == .binary) value.binary else incorrect(engine, "Binary", value);
}
pub fn asNumber(engine: *Engine, value: V) Error!f64 {
    return switch (value) {
        .integer, .javascript_integer => runtime.numberFloat(value).?,
        else => incorrect(engine, "Integer", value),
    };
}
fn asRecord(engine: *Engine, value: V) Error![]const runtime.Field {
    return if (value == .record) value.record else incorrect(engine, "Record", value);
}
pub fn asUnit(engine: *Engine, value: V) Error!void {
    if ((try asRecord(engine, value)).len != 0) return missing(engine, "actually to many fields");
}
pub fn field(engine: *Engine, value: V, name: []const u8) Error!V {
    for (try asRecord(engine, value)) |entry| if (eq(entry.name, name)) return entry.value;
    return missing(engine, name);
}
fn variant(engine: *Engine, value: V, names: []const []const u8) Error!*const runtime.Tagged {
    if (value != .tagged) return incorrect(engine, "Tagged", value);
    for (names) |name| if (eq(name, value.tagged.label)) return value.tagged;
    return incorrect(engine, "Variant better error needed", value);
}
const OptionInner = enum { number, string };
fn option(engine: *Engine, value: V, inner: OptionInner) Error!void {
    const tagged = try variant(engine, value, &.{ "Some", "None" });
    if (eq(tagged.label, "None")) return asUnit(engine, tagged.value);
    switch (inner) {
        .number => _ = try asNumber(engine, tagged.value),
        .string => _ = try asString(engine, tagged.value),
    }
}
fn fetch(engine: *Engine, lift: V) Error!void {
    const method = try variant(engine, try field(engine, lift, "method"), &.{ "CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT", "TRACE", "OTHER" });
    if (eq(method.label, "OTHER")) _ = try asString(engine, method.value) else try asUnit(engine, method.value);
    const scheme = try variant(engine, try field(engine, lift, "scheme"), &.{ "HTTP", "HTTPS" });
    try asUnit(engine, scheme.value);
    _ = try asString(engine, try field(engine, lift, "host"));
    try option(engine, try field(engine, lift, "port"), .number);
    _ = try asString(engine, try field(engine, lift, "path"));
    try option(engine, try field(engine, lift, "query"), .string);
    const headers = try field(engine, lift, "headers");
    if (headers != .list) return incorrect(engine, "List", headers);
    var cursor = headers.list;
    while (cursor) |cell| : (cursor = cell.tail) {
        _ = try asString(engine, try field(engine, cell.head, "key"));
        _ = try asString(engine, try field(engine, cell.head, "value"));
    }
    _ = try asBinary(engine, try field(engine, lift, "body"));
}

/// Validate the next-tui computer labels in their actual decoder order. Extra
/// provider labels, such as GitQuery and phone effects, keep their own decoder.
pub fn validate(engine: *Engine, label: []const u8, lift: V) Error!void {
    if (eq(label, "CWD") or eq(label, "Now") or eq(label, "Flip") or eq(label, "StandardIn")) return asUnit(engine, lift);
    if (eq(label, "StandardOut") or eq(label, "StandardError") or eq(label, "Env") or eq(label, "EYGParse") or eq(label, "ReadDirectory") or eq(label, "MakeDirectory") or eq(label, "DeleteFile")) {
        _ = try asString(engine, lift);
    } else if (eq(label, "Sleep") or eq(label, "Random") or eq(label, "Exit")) {
        _ = try asNumber(engine, lift);
    } else if (eq(label, "DecodeJSON")) {
        _ = try asBinary(engine, lift);
    } else if (eq(label, "ReadFile")) {
        _ = try asString(engine, try field(engine, lift, "path"));
        _ = try asNumber(engine, try field(engine, lift, "offset"));
        _ = try asNumber(engine, try field(engine, lift, "limit"));
    } else if (eq(label, "WriteFile") or eq(label, "AppendFile")) {
        _ = try asString(engine, try field(engine, lift, "path"));
        _ = try asBinary(engine, try field(engine, lift, "contents"));
    } else if (eq(label, "Hash")) {
        const algorithm = try variant(engine, try field(engine, lift, "algorithm"), &.{"SHA256"});
        try asUnit(engine, algorithm.value);
        _ = try asBinary(engine, try field(engine, lift, "bytes"));
    } else if (eq(label, "CreateKey")) {
        _ = try variant(engine, lift, &.{"Eddsa"});
    } else if (eq(label, "Sign")) {
        const key = try field(engine, lift, "key");
        _ = try asBinary(engine, try field(engine, lift, "data"));
        const algorithm = try variant(engine, key, &.{"Eddsa"});
        _ = try asBinary(engine, try field(engine, algorithm.value, "d"));
    } else if (eq(label, "Fetch")) {
        try fetch(engine, lift);
    }
}

/// The native Git provider additionally exposes SHA1. Its structure and unit
/// payload follow the same decoder; oracle-facing sandbox hosts stay strict.
pub fn validateNative(engine: *Engine, label: []const u8, lift: V) Error!void {
    if (!eq(label, "Hash")) return validate(engine, label, lift);
    const algorithm = try variant(engine, try field(engine, lift, "algorithm"), &.{ "SHA256", "SHA1" });
    try asUnit(engine, algorithm.value);
    _ = try asBinary(engine, try field(engine, lift, "bytes"));
}

fn record(a: std.mem.Allocator, fields: []const runtime.Field) !V {
    return .{ .record = try a.dupe(runtime.Field, fields) };
}
fn expectIncorrect(engine: *Engine, expected: []const u8, got: V) !void {
    const reason = engine.failure.?.incorrect_term;
    try std.testing.expectEqualStrings(expected, reason.expected);
    try std.testing.expect(runtime.equal(got, reason.got));
}

test "effect casts distinguish strict unit from ignored key options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var engine = Engine.init(a);
    const text: V = .{ .string = "ignored by Eddsa" };
    try validate(&engine, "CreateKey", try engine.tag("Eddsa", text));
    try std.testing.expectError(error.Runtime, validate(&engine, "CWD", text));
    try expectIncorrect(&engine, "Record", text);
    const extra = try record(a, &.{.{ .name = "extra", .value = runtime.unit() }});
    try std.testing.expectError(error.Runtime, validate(&engine, "StandardIn", extra));
    try std.testing.expectEqualStrings("actually to many fields", engine.failure.?.missing_field);
    const hash = try record(a, &.{ .{ .name = "algorithm", .value = try engine.tag("SHA256", text) }, .{ .name = "bytes", .value = .{ .binary = "" } } });
    try std.testing.expectError(error.Runtime, validate(&engine, "Hash", hash));
    try expectIncorrect(&engine, "Record", text);
}

test "effect casts stop at the first decoded field and retain offending values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var engine = Engine.init(a);
    try std.testing.expectError(error.Runtime, validate(&engine, "ReadFile", runtime.unit()));
    try std.testing.expectEqualStrings("path", engine.failure.?.missing_field);
    const wrong: V = .{ .integer = 17 };
    const request = try record(a, &.{.{ .name = "path", .value = wrong }});
    try std.testing.expectError(error.Runtime, validate(&engine, "ReadFile", request));
    try expectIncorrect(&engine, "String", wrong);
    const key: V = .{ .string = "not a key" };
    const sign = try record(a, &.{ .{ .name = "key", .value = key }, .{ .name = "data", .value = wrong } });
    try std.testing.expectError(error.Runtime, validate(&engine, "Sign", sign));
    try expectIncorrect(&engine, "Binary", wrong);
    try std.testing.expectError(error.Runtime, validate(&engine, "CreateKey", try engine.tag("unknown", runtime.unit())));
    try std.testing.expectEqualStrings("Variant better error needed", engine.failure.?.incorrect_term.expected);
}

test "effect integer decoder accepts all native Integer representations" {
    var engine = Engine.init(std.testing.allocator);
    for ([_]V{ .{ .integer = 123 }, .{ .javascript_integer = 1e100 }, .{ .javascript_integer = std.math.nan(f64) } }) |value| {
        try validate(&engine, "Sleep", value);
        try validate(&engine, "Exit", value);
    }
}

test "fetch decoder checks options and header fields before the body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var engine = Engine.init(a);
    const fields = try a.dupe(runtime.Field, &.{
        .{ .name = "method", .value = try engine.tag("GET", runtime.unit()) },
        .{ .name = "scheme", .value = try engine.tag("HTTPS", runtime.unit()) },
        .{ .name = "host", .value = .{ .string = "example.org" } },
        .{ .name = "port", .value = try engine.tag("Some", .{ .javascript_integer = 1e100 }) },
        .{ .name = "path", .value = .{ .string = "/" } },
        .{ .name = "query", .value = try engine.tag("None", runtime.unit()) },
        .{ .name = "headers", .value = .{ .list = null } },
        .{ .name = "body", .value = .{ .binary = "" } },
    });
    const request: V = .{ .record = fields };
    try validate(&engine, "Fetch", request);
    fields[6].value = try engine.cons(try record(a, &.{.{ .name = "key", .value = .{ .string = "x" } }}), null);
    fields[7].value = .{ .integer = 0 };
    try std.testing.expectError(error.Runtime, validate(&engine, "Fetch", request));
    try std.testing.expectEqualStrings("value", engine.failure.?.missing_field);
    fields[5].value = try engine.tag("None", .{ .integer = 1 });
    try std.testing.expectError(error.Runtime, validate(&engine, "Fetch", request));
    try expectIncorrect(&engine, "Record", .{ .integer = 1 });
}

test "SHA1 is isolated to the native provider extension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var engine = Engine.init(arena.allocator());
    const hash = try record(engine.allocator, &.{
        .{ .name = "algorithm", .value = try engine.tag("SHA1", runtime.unit()) },
        .{ .name = "bytes", .value = .{ .binary = "payload" } },
    });
    try std.testing.expectError(error.Runtime, validate(&engine, "Hash", hash));
    try std.testing.expectEqualStrings("Variant better error needed", engine.failure.?.incorrect_term.expected);
    try validateNative(&engine, "Hash", hash);
}
