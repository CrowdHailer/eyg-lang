//! Pure computer effects with the pinned touch_grass wire contracts.
//! JSON uses Julienne's lexical number/flat-stream model rather than f64 trees.
const std = @import("std");
pub const runtime = @import("interpreter.zig");
const parser = @import("parser.zig");
const codec = @import("ir_codec.zig");
const Engine = runtime.Engine;
const V = runtime.Value;
const J = std.json.Value;
const A = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;

pub fn effect(engine: *Engine, label: []const u8, lift: V) anyerror!V {
    if (eq(label, "DecodeJSON")) {
        var decoder = JsonDecoder{ .engine = engine, .input = try asBinary(engine, lift), .terms = std.ArrayList(V).init(engine.allocator), .stack = std.ArrayList(Container).init(engine.allocator) };
        const terms = decoder.parse() catch |err| {
            if (err == error.InvalidJson) return engine.tag("Error", .{ .string = decoder.reason.? });
            return err;
        };
        return engine.tag("Ok", terms);
    }
    if (eq(label, "EYGParse")) return parseEyg(engine, try asString(engine, lift));
    if (eq(label, "CreateKey")) {
        const algorithm = try asTagged(engine, lift);
        if (!eq(algorithm.label, "Eddsa")) return incorrect(engine, "Variant better error needed", lift);
        const keys = Ed25519.KeyPair.generate();
        return engine.tag("Ok", try engine.tag("Eddsa", try record(engine, &.{
            .{ .name = "kty", .value = .{ .string = "OKP" } },
            .{ .name = "crv", .value = .{ .string = "Ed25519" } },
            .{ .name = "x", .value = .{ .binary = try engine.allocator.dupe(u8, &keys.public_key.toBytes()) } },
            .{ .name = "d", .value = .{ .binary = try engine.allocator.dupe(u8, &keys.secret_key.seed()) } },
        })));
    }
    if (eq(label, "Sign")) {
        const key = try field(engine, lift, "key");
        const data = try asBinary(engine, try field(engine, lift, "data"));
        const algorithm = try asTagged(engine, key);
        if (!eq(algorithm.label, "Eddsa")) return incorrect(engine, "Variant better error needed", key);
        const seed = try asBinary(engine, try field(engine, algorithm.value, "d"));
        if (seed.len != 32) return engine.tag("Error", .{ .string = "invalid Ed25519 private key" });
        const keys = Ed25519.KeyPair.generateDeterministic(seed[0..32].*) catch return engine.tag("Error", .{ .string = "invalid Ed25519 private key" });
        const signature = try keys.sign(data, null);
        return engine.tag("Ok", .{ .binary = try engine.allocator.dupe(u8, &signature.toBytes()) });
    }
    return error.UnhandledEffect;
}

fn incorrect(engine: *Engine, expected: []const u8, got: V) error{Runtime} {
    engine.failure = .{ .incorrect_term = .{ .expected = expected, .got = got } };
    return error.Runtime;
}
fn asString(engine: *Engine, value: V) ![]const u8 {
    return if (value == .string) value.string else incorrect(engine, "String", value);
}
fn asBinary(engine: *Engine, value: V) ![]const u8 {
    return if (value == .binary) value.binary else incorrect(engine, "Binary", value);
}
fn asTagged(engine: *Engine, value: V) !*const runtime.Tagged {
    return if (value == .tagged) value.tagged else incorrect(engine, "Tagged", value);
}
fn field(engine: *Engine, value: V, name: []const u8) !V {
    if (value != .record) return incorrect(engine, "Record", value);
    for (value.record) |entry| if (eq(entry.name, name)) return entry.value;
    engine.failure = .{ .missing_field = name };
    return error.Runtime;
}
fn record(engine: *Engine, fields: []const runtime.Field) !V {
    return .{ .record = try engine.allocator.dupe(runtime.Field, fields) };
}
fn list(engine: *Engine, values: []const V) !V {
    var tail: ?*const runtime.List = null;
    var i = values.len;
    while (i > 0) {
        i -= 1;
        tail = (try engine.cons(values[i], tail)).list;
    }
    return .{ .list = tail };
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn parseEyg(engine: *Engine, source: []const u8) !V {
    const code = if (std.mem.startsWith(u8, source, "#!")) source[(if (std.mem.indexOfScalar(u8, source, '\n')) |i| i + 1 else source.len)..] else source;
    const parsed = std.json.parseFromSlice(J, engine.allocator, code, .{ .allocate = .alloc_always }) catch null;
    if (parsed) |value| if (runtime.validIr(value.value)) {
        if (flatten(engine, value.value)) |ast| return engine.tag("Ok", ast) else |err| {
            if (err != error.InvalidIR) return err;
        }
    };
    const ir = parser.parseExpression(engine.allocator, code) catch return engine.tag("Error", .{ .string = try parser.diagnostic(engine.allocator, code) });
    return engine.tag("Ok", try flatten(engine, ir));
}

fn attribute(ir: J, key: []const u8) !J {
    if (ir != .object) return error.InvalidIR;
    return ir.object.get(key) orelse error.InvalidIR;
}
fn textAttribute(ir: J, key: []const u8) ![]const u8 {
    const value = try attribute(ir, key);
    return if (value == .string) value.string else error.InvalidIR;
}
fn reference(engine: *Engine, ir: J, code: []const u8) !V {
    if (eq(code, ".")) return engine.tag("Relative", .{ .string = try textAttribute(ir, "i") });
    if (eq(code, "#")) return engine.tag("Content", .{ .string = try codec.canonicalCid(engine.allocator, try textAttribute(try attribute(ir, "l"), "/")) });
    const package = try textAttribute(ir, "p");
    if (ir.object.get("r")) |version| {
        const number = codec.jsonInteger(version) orelse return error.InvalidIR;
        const version_value = runtime.numberValue(number);
        if (ir.object.get("l")) |cid| return engine.tag("Release", try record(engine, &.{
            .{ .name = "package", .value = .{ .string = package } },
            .{ .name = "version", .value = version_value },
            .{ .name = "cid", .value = .{ .string = try codec.canonicalCid(engine.allocator, try textAttribute(cid, "/")) } },
        }));
        return engine.tag("Version", try record(engine, &.{
            .{ .name = "package", .value = .{ .string = package } },
            .{ .name = "version", .value = version_value },
        }));
    }
    return engine.tag("Package", .{ .string = package });
}

fn flatten(engine: *Engine, ir: J) anyerror!V {
    var pending = std.ArrayList(J).init(engine.allocator);
    var flat = std.ArrayList(V).init(engine.allocator);
    try pending.append(ir);
    while (pending.pop()) |current| {
        const code = try textAttribute(current, "0");
        const descriptor: struct { []const u8, V } = if (eq(code, "a")) blk: {
            try pending.append(try attribute(current, "a"));
            try pending.append(try attribute(current, "f"));
            break :blk .{ "Apply", runtime.unit() };
        } else if (eq(code, "l")) blk: {
            try pending.append(try attribute(current, "t"));
            try pending.append(try attribute(current, "v"));
            break :blk .{ "Let", .{ .string = try textAttribute(current, "l") } };
        } else if (eq(code, "f")) blk: {
            try pending.append(try attribute(current, "b"));
            break :blk .{ "Lambda", .{ .string = try textAttribute(current, "l") } };
        } else if (eq(code, "i")) blk: {
            const n = try attribute(current, "v");
            const number = codec.jsonInteger(n) orelse return error.InvalidIR;
            if (number < -runtime.safe_integer or number > runtime.safe_integer) return error.InvalidIR;
            break :blk .{ "Integer", .{ .integer = @intFromFloat(number) } };
        } else if (eq(code, "s")) .{ "String", .{ .string = try textAttribute(current, "v") } } else if (eq(code, "x")) .{ "Binary", .{ .binary = runtime.decodeBytes(engine.allocator, try attribute(current, "v")) catch return error.InvalidIR } } else if (eq(code, "#") or eq(code, ".") or eq(code, "@")) .{ "Reference", try reference(engine, current, code) } else blk: {
            const names = .{
                .{ "v", "Variable" }, .{ "e", "Extend" }, .{ "g", "Select" },  .{ "o", "Overwrite" },
                .{ "t", "Tag" },      .{ "m", "Case" },   .{ "p", "Perform" }, .{ "h", "Handle" },
                .{ "b", "Builtin" },
            };
            inline for (names) |item| if (eq(code, item[0])) break :blk .{ item[1], .{ .string = try textAttribute(current, "l") } };
            const constants = .{ .{ "ta", "Tail" }, .{ "c", "Cons" }, .{ "z", "Vacant" }, .{ "u", "Empty" }, .{ "n", "NoCases" } };
            inline for (constants) |item| if (eq(code, item[0])) break :blk .{ item[1], runtime.unit() };
            return error.InvalidIR;
        };
        try flat.append(try engine.tag(descriptor[0], descriptor[1]));
    }
    return list(engine, flat.items);
}

const Container = enum { array, object };
fn describeBits(a: A, bytes: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(a);
    try output.appendSlice("<<");
    for (bytes, 0..) |byte, i| {
        if (i > 0) try output.appendSlice(", ");
        try output.writer().print("{d}", .{byte});
    }
    try output.appendSlice(">>");
    return output.toOwnedSlice();
}

const JsonDecoder = struct {
    engine: *Engine,
    input: []const u8,
    at: usize = 0,
    terms: std.ArrayList(V),
    stack: std.ArrayList(Container),
    reason: ?[]const u8 = null,

    fn fail(self: *JsonDecoder, reason: []const u8) error{InvalidJson} {
        self.reason = reason;
        return error.InvalidJson;
    }
    fn unexpected(self: *JsonDecoder, bytes: []const u8) anyerror {
        if (std.unicode.utf8ValidateSlice(bytes)) return self.fail(bytes);
        const description = describeBits(self.engine.allocator, bytes) catch |err| return err;
        return self.fail(description);
    }
    fn whitespace(self: *JsonDecoder) void {
        while (self.at < self.input.len and std.mem.indexOfScalar(u8, " \t\r\n", self.input[self.at]) != null) self.at += 1;
    }
    fn emit(self: *JsonDecoder, tag: []const u8, value: V) !void {
        try self.terms.append(try record(self.engine, &.{
            .{ .name = "term", .value = try self.engine.tag(tag, value) },
            .{ .name = "depth", .value = .{ .integer = @intCast(self.stack.items.len) } },
        }));
    }
    fn string(self: *JsonDecoder) anyerror![]const u8 {
        self.at += 1;
        var bytes = std.ArrayList(u8).init(self.engine.allocator);
        while (self.at < self.input.len) {
            const c = self.input[self.at];
            self.at += 1;
            if (c == '"') {
                if (!std.unicode.utf8ValidateSlice(bytes.items)) {
                    return self.unexpected(bytes.items);
                }
                return bytes.toOwnedSlice();
            }
            if (c != '\\') {
                try bytes.append(c);
                continue;
            }
            const original = self.at - 1;
            if (self.at == self.input.len) {
                return self.unexpected(self.input[original..]);
            }
            const escape = self.input[self.at];
            self.at += 1;
            switch (escape) {
                '"', '\\', '/' => try bytes.append(escape),
                'b' => try bytes.append(8),
                'f' => try bytes.append(12),
                'n' => try bytes.append(10),
                'r' => try bytes.append(13),
                't' => try bytes.append(9),
                'u' => {
                    const high = try self.hex4(original);
                    const cp: u21 = if (high >= 0xd800 and high <= 0xdbff) blk: {
                        if (!std.mem.startsWith(u8, self.input[self.at..], "\\u")) {
                            return self.unexpected(self.input[original..]);
                        }
                        self.at += 2;
                        const low = try self.hex4(original);
                        if (low < 0xdc00 or low > 0xdfff) {
                            return self.unexpected(self.input[original..]);
                        }
                        break :blk 0x10000 + (@as(u21, high) - 0xd800) * 0x400 + (@as(u21, low) - 0xdc00);
                    } else if (high >= 0xdc00 and high <= 0xdfff) {
                        return self.unexpected(self.input[original..]);
                    } else high;
                    var encoded: [4]u8 = undefined;
                    const size = try std.unicode.utf8Encode(cp, &encoded);
                    try bytes.appendSlice(encoded[0..size]);
                },
                else => {
                    return self.unexpected(self.input[original..]);
                },
            }
        }
        return self.fail("unexpected end of JSON");
    }
    fn hex4(self: *JsonDecoder, original: usize) !u16 {
        if (self.input.len - self.at < 4) return self.fail("unexpected end of JSON");
        for (self.input[self.at..][0..4]) |c| if (!std.ascii.isHex(c)) {
            return self.unexpected(self.input[original..]);
        };
        const n = std.fmt.parseInt(u16, self.input[self.at..][0..4], 16) catch {
            return self.unexpected(self.input[original..]);
        };
        self.at += 4;
        return n;
    }
    fn digits(self: *JsonDecoder) !struct { value: f64, size: usize } {
        @setFloatMode(.strict);
        const start = self.at;
        var n: f64 = 0;
        while (self.at < self.input.len and std.ascii.isDigit(self.input[self.at])) : (self.at += 1) n = n * 10 + @as(f64, @floatFromInt(self.input[self.at] - '0'));
        return .{ .value = n, .size = self.at - start };
    }
    fn number(self: *JsonDecoder) !void {
        const negative = self.input[self.at] == '-';
        if (negative) self.at += 1;
        if (self.at == self.input.len or !std.ascii.isDigit(self.input[self.at])) {
            return self.unexpected(self.input[self.at - @as(usize, if (negative) 1 else 0) ..]);
        }
        const whole = if (self.input[self.at] == '0') blk: {
            self.at += 1;
            break :blk @as(f64, 0);
        } else (try self.digits()).value;
        var decimal: f64 = 0;
        var places: usize = 0;
        var exponent: f64 = 0;
        var lexical_number = false;
        if (self.at < self.input.len and self.input[self.at] == '.') {
            lexical_number = true;
            self.at += 1;
            const fraction = try self.digits();
            if (fraction.size == 0) return self.fail("missing digits in number");
            decimal = fraction.value;
            places = fraction.size;
        }
        if (self.at < self.input.len and (self.input[self.at] == 'e' or self.input[self.at] == 'E')) {
            lexical_number = true;
            self.at += 1;
            var exp_negative = false;
            if (self.at < self.input.len and (self.input[self.at] == '+' or self.input[self.at] == '-')) {
                exp_negative = self.input[self.at] == '-';
                self.at += 1;
            }
            const exp = try self.digits();
            if (exp.size == 0) return self.fail("missing digits in number");
            exponent = if (exp_negative) -exp.value else exp.value;
        }
        if (!lexical_number) return self.emit("Integer", runtime.numberValue(if (negative) -whole else whole));
        try self.emit("Number", try record(self.engine, &.{
            .{ .name = "sign", .value = try self.engine.tag(if (negative) "Negative" else "Positive", runtime.unit()) },
            .{ .name = "integer", .value = runtime.numberValue(whole) },
            .{ .name = "decimal", .value = try record(self.engine, &.{
                .{ .name = "numerator", .value = runtime.numberValue(decimal) },
                .{ .name = "size", .value = .{ .integer = @intCast(places) } },
            }) },
            .{ .name = "exponent", .value = runtime.numberValue(exponent) },
        }));
    }
    fn parse(self: *JsonDecoder) anyerror!V {
        var state: enum { value, key, separator, continuation } = .value;
        while (true) {
            self.whitespace();
            if (state == .continuation and self.stack.items.len == 0) return list(self.engine, self.terms.items);
            if (self.at == self.input.len) return self.fail("unexpected end of JSON");
            const c = self.input[self.at];
            switch (state) {
                .value => {
                    if (c == '[' or c == '{') {
                        try self.emit(if (c == '[') "Array" else "Object", runtime.unit());
                        try self.stack.append(if (c == '[') .array else .object);
                        state = if (c == '[') .value else .key;
                        self.at += 1;
                        continue;
                    }
                    if (c == ']' and self.stack.items.len > 0 and self.stack.items[self.stack.items.len - 1] == .array) {
                        _ = self.stack.pop();
                        self.at += 1;
                    } else if (c == '"') {
                        try self.emit("String", .{ .string = try self.string() });
                    } else if (std.mem.startsWith(u8, self.input[self.at..], "true")) {
                        self.at += 4;
                        try self.emit("True", runtime.unit());
                    } else if (std.mem.startsWith(u8, self.input[self.at..], "false")) {
                        self.at += 5;
                        try self.emit("False", runtime.unit());
                    } else if (std.mem.startsWith(u8, self.input[self.at..], "null")) {
                        self.at += 4;
                        try self.emit("Null", runtime.unit());
                    } else if (c == '-' or std.ascii.isDigit(c)) {
                        try self.number();
                    } else return self.unexpected(self.input[self.at..]);
                    state = .continuation;
                },
                .key => {
                    if (c == '}') {
                        _ = self.stack.pop();
                        self.at += 1;
                        state = .continuation;
                    } else if (c == '"') {
                        try self.emit("Field", .{ .string = try self.string() });
                        state = .separator;
                    } else return self.unexpected(self.input[self.at..]);
                },
                .separator => {
                    if (c != ':') return self.unexpected(self.input[self.at..]);
                    self.at += 1;
                    state = .value;
                },
                .continuation => {
                    const container = self.stack.items[self.stack.items.len - 1];
                    if ((container == .array and c == ']') or (container == .object and c == '}')) {
                        _ = self.stack.pop();
                        self.at += 1;
                    } else if (c == ',') {
                        self.at += 1;
                        state = if (container == .array) .value else .key;
                    } else return self.unexpected(self.input[self.at..]);
                },
            }
        }
    }
};

test "lexical JSON, flattened AST and RFC8032 Ed25519 signature" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var engine = Engine.init(arena.allocator());
    const json = try effect(&engine, "DecodeJSON", .{ .binary = "{\"x\":[-1.020e-3,true,null]}" });
    try std.testing.expectEqualStrings("Ok", json.tagged.label);
    try std.testing.expectEqualStrings("Object", json.tagged.value.list.?.head.record[0].value.tagged.label);
    const ast = try effect(&engine, "EYGParse", .{ .string = "!int_add(20, 22)" });
    try std.testing.expectEqualStrings("Apply", ast.tagged.value.list.?.head.tagged.label);
    var seed: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&seed, "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
    const signature = try effect(&engine, "Sign", try record(&engine, &.{
        .{ .name = "key", .value = try engine.tag("Eddsa", try record(&engine, &.{.{ .name = "d", .value = .{ .binary = &seed } }})) },
        .{ .name = "data", .value = .{ .binary = "" } },
    }));
    const hex = std.fmt.bytesToHex(signature.tagged.value.binary[0..64].*, .lower);
    try std.testing.expectEqualStrings("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b", &hex);
}
