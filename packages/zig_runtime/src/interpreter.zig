//! EYG's native evaluator. The control loop and continuations are explicit so
//! tail calls and delimited, multi-shot effect continuations do not use the
//! host stack. All runtime objects belong to the caller's allocator (normally
//! a session arena).
const std = @import("std");
const Allocator = std.mem.Allocator;
const codec = @import("ir_codec.zig");
pub const InspectionMeta = @import("inspection.zig").Meta;
pub const Json = std.json.Value;
pub const safe_integer: i64 = 9007199254740991;

pub const Value = union(enum) {
    integer: i64,
    /// JavaScript Integer values outside the native integer representation.
    javascript_integer: f64,
    string: []const u8,
    binary: []const u8,
    list: ?*const List,
    record: []const Field,
    tagged: *const Tagged,
    closure: *const Closure,
    partial: *const Partial,
    @"resume": *const Resumption,
};
pub const List = struct { head: Value, tail: ?*const List };
pub const Field = struct { name: []const u8, value: Value };
pub const Tagged = struct { label: []const u8, value: Value };
pub const Binding = struct { name: []const u8, value: Value, next: ?*const Binding };
pub const Closure = struct { param: []const u8, body: Json, env: ?*const Binding, origin: ?[]const u8, inspection_meta: InspectionMeta = .none };
pub const Partial = struct { kind: Kind, label: []const u8, args: []const Value, origin: ?[]const u8 };
pub const Kind = enum { cons, extend, overwrite, select, tag, match, no_cases, perform, handle, builtin };
pub const Resumption = struct { head: ?*const Kont, stop: ?*const Kont, env: ?*const Binding };
pub const Kont = struct {
    next: ?*const Kont,
    env: ?*const Binding,
    origin: ?[]const u8,
    inspection_meta: InspectionMeta = .none,
    action: union(enum) {
        argument: Json,
        apply: Value,
        assign: struct { name: []const u8, then: Json },
        call_with: Value,
        delimit: struct { label: []const u8, handler: Value },
        trace: Value,
    },
};
const Control = union(enum) { expression: Json, value: Value };
pub const Reason = union(enum) {
    undefined_variable: []const u8,
    undefined_builtin: []const u8,
    undefined_reference: Json,
    vacant,
    not_a_function: Value,
    no_match: Value,
    missing_field: []const u8,
    incorrect_term: struct { expected: []const u8, got: Value },
    unhandled_effect: struct { label: []const u8, value: Value },
    unrepresentable: struct { builtin: []const u8, args: []const Value },
    step_limit,
};
pub const ReferenceHandler = *const fn (?*anyopaque, *Engine, Json) anyerror!Value;
pub const EffectHandler = *const fn (?*anyopaque, *Engine, []const u8, Value) anyerror!Value;

pub const Engine = struct {
    allocator: Allocator,
    scope: ?*const Binding = null,
    origin: ?[]const u8 = null,
    /// Generic Gleam inspector metadata, independent of native source origins.
    /// Pure IR uses Nil; the structural REPL annotates its whole draft as Json.
    inspection_meta: InspectionMeta = .none,
    effect_origin: ?[]const u8 = null,
    failure: ?Reason = null,
    effect_handler: ?EffectHandler = null,
    effect_context: ?*anyopaque = null,
    reference_handler: ?ReferenceHandler = null,
    reference_context: ?*anyopaque = null,
    max_steps: usize = 10_000_000,
    /// Zero disables cooperative yielding (the pure/oracle default).
    time_budget_ns: u64 = 0,
    steps: usize = 0,
    env: ?*const Binding = null,
    k: ?*const Kont = null,
    control: Control = .{ .value = unit() },

    pub fn init(allocator: Allocator) Engine {
        return .{ .allocator = allocator };
    }
    fn create(self: *Engine, comptime T: type, value: T) !*T {
        const p = try self.allocator.create(T);
        p.* = value;
        return p;
    }
    pub fn bind(self: *Engine, name: []const u8, value: Value) !void {
        self.scope = try self.create(Binding, .{ .name = name, .value = value, .next = self.scope });
    }
    fn fail(self: *Engine, reason: Reason) error{Runtime} {
        self.failure = reason;
        return error.Runtime;
    }
    fn push(self: *Engine, action: @FieldType(Kont, "action"), env: ?*const Binding) !void {
        self.k = try self.create(Kont, .{ .next = self.k, .env = env, .origin = self.origin, .inspection_meta = self.inspection_meta, .action = action });
    }
    pub fn eval(self: *Engine, ir: Json) anyerror!Value {
        self.failure = null;
        if (!validIr(ir)) return error.InvalidIR;
        return self.evalTrusted(ir);
    }
    /// Evaluate already constructed IR, as the structural editor does. The
    /// serialized DAG-JSON boundary remains strict through eval/evaluate.
    pub fn evalTrusted(self: *Engine, ir: Json) anyerror!Value {
        self.failure = null;
        self.steps = 0;
        self.env = self.scope;
        self.k = null;
        self.control = .{ .expression = ir };
        return self.run();
    }
    pub fn @"resume"(self: *Engine, reply: Value) anyerror!Value {
        self.failure = null;
        self.control = .{ .value = reply };
        return self.run();
    }
    pub fn call(self: *Engine, func: Value, args: []const Value) anyerror!Value {
        self.failure = null;
        self.steps = 0;
        self.env = self.scope;
        self.k = null;
        var i = args.len;
        while (i > 0) {
            i -= 1;
            try self.push(.{ .call_with = args[i] }, self.env);
        }
        self.control = .{ .value = func };
        return self.run();
    }
    /// Continue a VM paused by error.Yield without replacing its control value.
    pub fn continueRun(self: *Engine) anyerror!Value {
        return self.run();
    }
    fn run(self: *Engine) anyerror!Value {
        var timer: ?std.time.Timer = if (self.time_budget_ns > 0) try std.time.Timer.start() else null;
        const initial_steps = self.steps;
        while (true) {
            // A resumed slice always makes progress. Checking at VM boundaries
            // preserves a complete control/env/continuation state for its host.
            if (timer) |*clock| if (self.steps != initial_steps and self.steps & 127 == 0 and clock.read() >= self.time_budget_ns) {
                self.failure = null;
                return error.Yield;
            };
            self.steps += 1;
            if (self.steps > self.max_steps) return self.fail(.step_limit);
            switch (self.control) {
                .expression => |ir| try self.expression(ir),
                .value => |value| {
                    const kont = self.k orelse return value;
                    self.k = kont.next;
                    switch (kont.action) {
                        .argument => |arg| {
                            self.env = kont.env;
                            self.origin = kont.origin;
                            self.inspection_meta = kont.inspection_meta;
                            try self.push(.{ .apply = value }, kont.env);
                            self.control = .{ .expression = arg };
                        },
                        .apply => |func| {
                            self.env = kont.env;
                            self.origin = kont.origin;
                            self.inspection_meta = kont.inspection_meta;
                            try self.apply(func, value);
                        },
                        .call_with => |arg| {
                            self.env = kont.env;
                            self.origin = kont.origin;
                            self.inspection_meta = kont.inspection_meta;
                            try self.apply(value, arg);
                        },
                        .assign => |assign| {
                            self.env = try self.create(Binding, .{ .name = assign.name, .value = value, .next = kont.env });
                            self.origin = kont.origin;
                            self.inspection_meta = kont.inspection_meta;
                            self.control = .{ .expression = assign.then };
                        },
                        .trace, .delimit => {
                            self.env = kont.env;
                            self.origin = kont.origin;
                            self.inspection_meta = kont.inspection_meta;
                            self.control = .{ .value = value };
                        },
                    }
                },
            }
        }
    }
    fn expression(self: *Engine, ir: Json) anyerror!void {
        self.inspection_meta = self.inspection_meta.at(ir);
        const code = stringField(ir, "0") orelse return self.fail(.vacant);
        const label = stringField(ir, "l") orelse "";
        if (eq(code, "a")) {
            try self.push(.{ .argument = field(ir, "a") }, self.env);
            self.control = .{ .expression = field(ir, "f") };
            return;
        }
        if (eq(code, "l")) {
            try self.push(.{ .assign = .{ .name = label, .then = field(ir, "t") } }, self.env);
            self.control = .{ .expression = field(ir, "v") };
            return;
        }
        const value: Value = if (eq(code, "i")) numberValue(switch (field(ir, "v")) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            .number_string => |text| std.fmt.parseFloat(f64, text) catch return self.fail(.vacant),
            else => return self.fail(.vacant),
        }) else if (eq(code, "s")) .{ .string = stringField(ir, "v") orelse "" } else if (eq(code, "x")) .{ .binary = try decodeBytes(self.allocator, field(ir, "v")) } else if (eq(code, "u")) unit() else if (eq(code, "ta")) .{ .list = null } else if (eq(code, "f")) .{ .closure = try self.create(Closure, .{ .param = label, .body = field(ir, "b"), .env = self.env, .origin = self.origin, .inspection_meta = self.inspection_meta }) } else if (eq(code, "v")) blk: {
            var env = self.env;
            while (env) |binding| : (env = binding.next) {
                if (eq(binding.name, label)) break :blk binding.value;
            }
            return self.fail(.{ .undefined_variable = label });
        } else if (eq(code, "z")) return self.fail(.vacant) else if (eq(code, "#") or eq(code, "@") or eq(code, ".")) blk: {
            const reference = try canonicalReference(self.allocator, ir);
            if (self.reference_handler) |handler| break :blk try handler(self.reference_context, self, reference);
            return self.fail(.{ .undefined_reference = reference });
        } else blk: {
            const kind: Kind = if (eq(code, "c")) .cons else if (eq(code, "e")) .extend else if (eq(code, "o")) .overwrite else if (eq(code, "g")) .select else if (eq(code, "t")) .tag else if (eq(code, "m")) .match else if (eq(code, "n")) .no_cases else if (eq(code, "p")) .perform else if (eq(code, "h")) .handle else if (eq(code, "b")) .builtin else return self.fail(.vacant);
            if (kind == .builtin and builtinMap.get(label) == null) return self.fail(.{ .undefined_builtin = label });
            break :blk try self.partial(kind, label, &.{});
        };
        self.control = .{ .value = value };
    }
    pub fn partial(self: *Engine, kind: Kind, label: []const u8, args: []const Value) !Value {
        return .{ .partial = try self.create(Partial, .{ .kind = kind, .label = label, .args = args, .origin = self.origin }) };
    }
    pub fn tag(self: *Engine, label: []const u8, value: Value) !Value {
        return .{ .tagged = try self.create(Tagged, .{ .label = label, .value = value }) };
    }
    pub fn boolean(self: *Engine, value: bool) !Value {
        return self.tag(if (value) "True" else "False", unit());
    }
    pub fn cons(self: *Engine, head: Value, tail: ?*const List) !Value {
        return .{ .list = try self.create(List, .{ .head = head, .tail = tail }) };
    }
    fn trace(self: *Engine, arg: Value) !void {
        if (self.k) |previous| if (previous.action == .trace) {
            var replacement = previous.*;
            replacement.action = .{ .trace = arg };
            replacement.inspection_meta = self.inspection_meta;
            self.k = try self.create(Kont, replacement);
            return;
        };
        try self.push(.{ .trace = arg }, self.env);
    }
    fn apply(self: *Engine, func: Value, arg: Value) anyerror!void {
        switch (func) {
            .closure => |closure| {
                // A tail call replaces the trace rather than accumulating one.
                try self.trace(arg);
                self.origin = closure.origin;
                self.inspection_meta = closure.inspection_meta;
                self.env = try self.create(Binding, .{ .name = closure.param, .value = arg, .next = closure.env });
                self.control = .{ .expression = closure.body };
            },
            .@"resume" => |captured| {
                // Continuations are immutable. Copy the captured prefix to attach
                // it to this caller; the same resumption can be called repeatedly.
                try self.trace(arg);
                var stack = std.ArrayList(*const Kont).init(self.allocator);
                var k = captured.head;
                while (k != captured.stop) {
                    const current = k orelse break;
                    try stack.append(current);
                    k = current.next;
                }
                var i = stack.items.len;
                while (i > 0) {
                    i -= 1;
                    const saved_origin = self.origin;
                    const saved_meta = self.inspection_meta;
                    self.origin = stack.items[i].origin;
                    self.inspection_meta = stack.items[i].inspection_meta;
                    try self.push(stack.items[i].action, stack.items[i].env);
                    self.origin = saved_origin;
                    self.inspection_meta = saved_meta;
                }
                self.env = captured.env;
                self.control = .{ .value = arg };
            },
            .partial => |p| {
                self.origin = p.origin;
                const args = try self.allocator.alloc(Value, p.args.len + 1);
                @memcpy(args[0..p.args.len], p.args);
                args[p.args.len] = arg;
                const arity: usize = switch (p.kind) {
                    .cons, .extend, .overwrite, .handle => 2,
                    .match => 3,
                    .select, .tag, .no_cases, .perform => 1,
                    .builtin => builtinArity(builtinMap.get(p.label) orelse return self.fail(.{ .undefined_builtin = p.label })),
                };
                if (args.len < arity) {
                    self.control = .{ .value = try self.partial(p.kind, p.label, args) };
                    return;
                }
                switch (p.kind) {
                    .cons => self.control = .{ .value = try self.cons(args[0], try self.asList(args[1])) },
                    .extend, .overwrite => {
                        const fields = try self.asRecord(args[1]);
                        var index: ?usize = null;
                        for (fields, 0..) |f, i| {
                            if (eq(f.name, p.label)) {
                                index = i;
                                break;
                            }
                        }
                        if (index == null and p.kind == .overwrite) return self.fail(.{ .missing_field = p.label });
                        const output = try self.allocator.alloc(Field, fields.len + @as(usize, if (index == null) 1 else 0));
                        @memcpy(output[0..fields.len], fields);
                        output[index orelse fields.len] = .{ .name = p.label, .value = args[0] };
                        self.control = .{ .value = .{ .record = output } };
                    },
                    .select => {
                        for (try self.asRecord(arg)) |f| {
                            if (eq(f.name, p.label)) {
                                self.control = .{ .value = f.value };
                                return;
                            }
                        }
                        return self.fail(.{ .missing_field = p.label });
                    },
                    .tag => self.control = .{ .value = try self.tag(p.label, arg) },
                    .match => {
                        const tagged = try self.asTagged(arg);
                        try self.apply(if (eq(tagged.label, p.label)) args[0] else args[1], if (eq(tagged.label, p.label)) tagged.value else arg);
                    },
                    .no_cases => return self.fail(.{ .no_match = arg }),
                    .perform => try self.perform(p.label, arg),
                    .handle => {
                        try self.push(.{ .delimit = .{ .label = p.label, .handler = args[0] } }, self.env);
                        try self.apply(arg, unit());
                    },
                    .builtin => try self.builtin(builtinMap.get(p.label).?, p.label, args),
                }
            },
            else => return self.fail(.{ .not_a_function = func }),
        }
    }
    fn perform(self: *Engine, label: []const u8, lift: Value) anyerror!void {
        var search = self.k;
        while (search) |k| : (search = k.next) {
            if (k.action == .delimit and eq(k.action.delimit.label, label)) {
                const continuation: Value = .{ .@"resume" = try self.create(Resumption, .{ .head = self.k, .stop = k.next, .env = self.env }) };
                self.k = k.next;
                self.env = k.env;
                self.origin = k.origin;
                self.inspection_meta = k.inspection_meta;
                try self.push(.{ .call_with = continuation }, k.env);
                try self.apply(k.action.delimit.handler, lift);
                return;
            }
        }
        self.effect_origin = self.origin;
        if (self.effect_handler) |handler| {
            self.control = .{ .value = try handler(self.effect_context, self, label, lift) };
            return;
        }
        return self.fail(.{ .unhandled_effect = .{ .label = label, .value = lift } });
    }
    fn asNumber(self: *Engine, value: Value) anyerror!f64 {
        return numberFloat(value) orelse self.fail(.{ .incorrect_term = .{ .expected = "Integer", .got = value } });
    }
    fn asString(self: *Engine, value: Value) anyerror![]const u8 {
        return switch (value) {
            .string => |v| v,
            else => self.fail(.{ .incorrect_term = .{ .expected = "String", .got = value } }),
        };
    }
    fn asBinary(self: *Engine, value: Value) anyerror![]const u8 {
        return switch (value) {
            .binary => |v| v,
            else => self.fail(.{ .incorrect_term = .{ .expected = "Binary", .got = value } }),
        };
    }
    fn asList(self: *Engine, value: Value) anyerror!?*const List {
        return switch (value) {
            .list => |v| v,
            else => self.fail(.{ .incorrect_term = .{ .expected = "List", .got = value } }),
        };
    }
    fn asRecord(self: *Engine, value: Value) anyerror![]const Field {
        return switch (value) {
            .record => |v| v,
            else => self.fail(.{ .incorrect_term = .{ .expected = "Record", .got = value } }),
        };
    }
    fn asTagged(self: *Engine, value: Value) anyerror!*const Tagged {
        return switch (value) {
            .tagged => |v| v,
            else => self.fail(.{ .incorrect_term = .{ .expected = "Tagged", .got = value } }),
        };
    }
    fn record2(self: *Engine, a: []const u8, av: Value, b: []const u8, bv: Value) !Value {
        const fields = try self.allocator.alloc(Field, 2);
        fields[0] = .{ .name = a, .value = av };
        fields[1] = .{ .name = b, .value = bv };
        return .{ .record = fields };
    }
    fn builtin(self: *Engine, op: Builtin, label: []const u8, a: []const Value) anyerror!void {
        const value: Value = switch (op) {
            .equal => try self.boolean(equal(a[0], a[1])),
            .fix => {
                const builder_args = try self.allocator.dupe(Value, &.{a[0]});
                try self.apply(a[0], try self.partial(.builtin, "fixed", builder_args));
                return;
            },
            .fixed => {
                try self.push(.{ .call_with = a[1] }, self.env);
                const builder_args = try self.allocator.dupe(Value, &.{a[0]});
                try self.apply(a[0], try self.partial(.builtin, "fixed", builder_args));
                return;
            },
            .never => return self.fail(.{ .incorrect_term = .{ .expected = "Never", .got = a[0] } }),
            .int_compare => blk: {
                if (safeNative(a[0]) and safeNative(a[1])) break :blk try self.tag(if (a[0].integer == a[1].integer) "Eq" else if (a[0].integer < a[1].integer) "Lt" else "Gt", unit());
                const left = try self.asNumber(a[0]);
                const right = try self.asNumber(a[1]);
                break :blk try self.tag(if (left == right) "Eq" else if (left < right) "Lt" else "Gt", unit());
            },
            .int_add, .int_subtract, .int_multiply => blk: {
                if (safeNative(a[0]) and safeNative(a[1])) {
                    const left: i128 = a[0].integer;
                    const right: i128 = a[1].integer;
                    const result = switch (op) {
                        .int_add => left + right,
                        .int_subtract => left - right,
                        .int_multiply => left * right,
                        else => unreachable,
                    };
                    if (result < -safe_integer or result > safe_integer) return self.fail(.{ .unrepresentable = .{ .builtin = label, .args = a } });
                    break :blk .{ .integer = @intCast(result) };
                }
                const left = try self.asNumber(a[0]);
                const right = try self.asNumber(a[1]);
                const result = switch (op) {
                    .int_add => left + right,
                    .int_subtract => left - right,
                    .int_multiply => left * right,
                    else => unreachable,
                };
                if (!std.math.isFinite(result) or @trunc(result) != result or @abs(result) > safe_integer) return self.fail(.{ .unrepresentable = .{ .builtin = label, .args = a } });
                break :blk numberValue(result);
            },
            .int_divide => blk: {
                if (safeNative(a[0]) and safeNative(a[1])) break :blk if (a[1].integer == 0) try self.tag("Error", unit()) else try self.tag("Ok", .{ .integer = @divTrunc(a[0].integer, a[1].integer) });
                const left = try self.asNumber(a[0]);
                const right = try self.asNumber(a[1]);
                break :blk if (right == 0) try self.tag("Error", unit()) else try self.tag("Ok", numberValue(@trunc(left / right)));
            },
            .int_absolute => if (safeNative(a[0])) .{ .integer = @intCast(@abs(a[0].integer)) } else numberValue(@abs(try self.asNumber(a[0]))),
            .int_parse => blk: {
                const text = try self.asString(a[0]);
                if (!validIntegerText(text)) break :blk try self.tag("Error", unit());
                const number = std.fmt.parseInt(i128, text, 10) catch return self.fail(.{ .unrepresentable = .{ .builtin = label, .args = a } });
                if (number < -safe_integer or number > safe_integer) return self.fail(.{ .unrepresentable = .{ .builtin = label, .args = a } });
                break :blk try self.tag("Ok", .{ .integer = @intCast(number) });
            },
            .int_to_string => .{ .string = if (a[0] == .integer) try integerText(self.allocator, a[0].integer) else try numberText(self.allocator, try self.asNumber(a[0])) },
            .string_append => .{ .string = try std.mem.concat(self.allocator, u8, &.{ try self.asString(a[0]), try self.asString(a[1]) }) },
            .string_split => blk: {
                const text = try self.asString(a[0]);
                const pattern = try self.asString(a[1]);
                var parts = std.ArrayList([]const u8).init(self.allocator);
                if (pattern.len == 0) {
                    var index: usize = 0;
                    while (index < text.len) {
                        const end = graphemeEnd(text, index);
                        try parts.append(text[index..end]);
                        index = end;
                    }
                } else {
                    var iter = std.mem.splitSequence(u8, text, pattern);
                    while (iter.next()) |part| try parts.append(part);
                }
                var tail: ?*const List = null;
                var index = parts.items.len;
                while (index > 1) {
                    index -= 1;
                    tail = (try self.cons(.{ .string = parts.items[index] }, tail)).list;
                }
                break :blk try self.record2("head", .{ .string = if (parts.items.len > 0) parts.items[0] else "" }, "tail", .{ .list = tail });
            },
            .string_split_once => blk: {
                const text = try self.asString(a[0]);
                const pattern = try self.asString(a[1]);
                const i = std.mem.indexOf(u8, text, pattern) orelse break :blk try self.tag("Error", unit());
                break :blk try self.tag("Ok", try self.record2("pre", .{ .string = text[0..i] }, "post", .{ .string = text[i + pattern.len ..] }));
            },
            .string_replace => blk: {
                const text = try self.asString(a[0]);
                const from = try self.asString(a[1]);
                const to = try self.asString(a[2]);
                var output = std.ArrayList(u8).init(self.allocator);
                if (from.len == 0) {
                    try output.appendSlice(to);
                    var index: usize = 0;
                    while (index < text.len) {
                        const end = graphemeEnd(text, index);
                        try output.appendSlice(text[index..end]);
                        try output.appendSlice(to);
                        index = end;
                    }
                } else {
                    var iter = std.mem.splitSequence(u8, text, from);
                    var first = true;
                    while (iter.next()) |part| {
                        if (!first) try output.appendSlice(to);
                        try output.appendSlice(part);
                        first = false;
                    }
                }
                break :blk .{ .string = try output.toOwnedSlice() };
            },
            .string_uppercase, .string_lowercase => .{ .string = try changeCase(self.allocator, try self.asString(a[0]), op == .string_uppercase) },
            .string_starts_with => try self.boolean(std.mem.startsWith(u8, try self.asString(a[0]), try self.asString(a[1]))),
            .string_ends_with => try self.boolean(std.mem.endsWith(u8, try self.asString(a[0]), try self.asString(a[1]))),
            .string_length => blk: {
                const text = try self.asString(a[0]);
                var length: i64 = 0;
                var index: usize = 0;
                while (index < text.len) : (length += 1) index = graphemeEnd(text, index);
                break :blk .{ .integer = length };
            },
            .string_to_binary => .{ .binary = try self.asString(a[0]) },
            .string_from_binary => blk: {
                const bytes = try self.asBinary(a[0]);
                break :blk if (std.unicode.utf8ValidateSlice(bytes)) try self.tag("Ok", .{ .string = bytes }) else try self.tag("Error", unit());
            },
            .binary_from_integers => blk: {
                var list = try self.asList(a[0]);
                var bytes = std.ArrayList(u8).init(self.allocator);
                while (list) |cell| : (list = cell.tail) try bytes.append(if (safeNative(cell.head)) @truncate(@as(u64, @bitCast(cell.head.integer))) else toUint8(try self.asNumber(cell.head)));
                break :blk .{ .binary = try bytes.toOwnedSlice() };
            },
            .binary_size => .{ .integer = @intCast((try self.asBinary(a[0])).len) },
            .binary_concat => .{ .binary = try std.mem.concat(self.allocator, u8, &.{ try self.asBinary(a[0]), try self.asBinary(a[1]) }) },
            .binary_compare => try self.tag(switch (std.mem.order(u8, try self.asBinary(a[0]), try self.asBinary(a[1]))) {
                .lt => "Lt",
                .eq => "Eq",
                .gt => "Gt",
            }, unit()),
            .list_pop => blk: {
                const list = try self.asList(a[0]);
                break :blk if (list) |cell| try self.tag("Ok", try self.record2("head", cell.head, "tail", .{ .list = cell.tail })) else try self.tag("Error", unit());
            },
            .list_fold, .binary_fold => {
                const head: Value, const rest: Value = if (op == .list_fold) blk: {
                    const list = try self.asList(a[0]) orelse {
                        self.control = .{ .value = a[1] };
                        return;
                    };
                    break :blk .{ list.head, Value{ .list = list.tail } };
                } else blk: {
                    const bytes = try self.asBinary(a[0]);
                    if (bytes.len == 0) {
                        self.control = .{ .value = a[1] };
                        return;
                    }
                    break :blk .{ Value{ .integer = bytes[0] }, Value{ .binary = bytes[1..] } };
                };
                try self.push(.{ .call_with = a[2] }, self.env);
                const args = try self.allocator.dupe(Value, &.{rest});
                try self.push(.{ .apply = try self.partial(.builtin, label, args) }, self.env);
                try self.push(.{ .call_with = a[1] }, self.env);
                try self.apply(a[2], head);
                return;
            },
        };
        self.control = .{ .value = value };
    }
    pub fn evaluate(self: *Engine, ir: Json) anyerror!Json {
        const value = self.eval(ir) catch |err| {
            if (err == error.Runtime) return object(self.allocator, &.{.{ "break", try self.reasonJson(self.failure.?) }});
            if (err == error.InvalidIR) return object(self.allocator, &.{.{ "decode_error", .{ .bool = true } }});
            return err;
        };
        return object(self.allocator, &.{.{ "value", try self.toJson(value) }});
    }
    pub fn toJson(self: *Engine, value: Value) anyerror!Json {
        const a = self.allocator;
        return switch (value) {
            .integer => |i| object(a, &.{.{ "integer", if (i >= -safe_integer and i <= safe_integer) .{ .integer = i } else try numberJson(a, @floatFromInt(i)) }}),
            .javascript_integer => |f| object(a, &.{.{ "integer", try numberJson(a, f) }}),
            .string => |s| object(a, &.{.{ "string", .{ .string = s } }}),
            .binary => |s| object(a, &.{.{ "binary", try encodeBytes(a, s) }}),
            .list => |head| blk: {
                var list = std.ArrayList(Json).init(a);
                var cursor = head;
                while (cursor) |cell| : (cursor = cell.tail) try list.append(try self.toJson(cell.head));
                break :blk object(a, &.{.{ "list", .{ .array = list } }});
            },
            .record => |fields| blk: {
                var result = std.json.ObjectMap.init(a);
                for (fields) |f| try result.put(f.name, try self.toJson(f.value));
                break :blk object(a, &.{.{ "record", .{ .object = result } }});
            },
            .tagged => |t| object(a, &.{.{ "tagged", try object(a, &.{ .{ "label", .{ .string = t.label } }, .{ "value", try self.toJson(t.value) } }) }}),
            .closure, .partial, .@"resume" => object(a, &.{.{ "function", .{ .bool = true } }}),
        };
    }
    /// Decode the stable fixture/effect value format at the host boundary.
    /// Validate the JSON union before accessing it, including in ReleaseFast.
    pub fn fromJson(self: *Engine, input: Json) anyerror!Value {
        if (input != .object or input.object.count() != 1) return error.InvalidValue;
        if (input.object.get("integer")) |i| {
            const value = codec.jsonInteger(i) orelse return error.InvalidValue;
            return numberValue(value);
        }
        if (input.object.get("string")) |s| {
            if (s != .string) return error.InvalidValue;
            return .{ .string = s.string };
        }
        if (input.object.get("binary")) |b| return .{ .binary = try decodeBytes(self.allocator, b) };
        if (input.object.get("tagged")) |t| {
            const label = stringField(t, "label") orelse return error.InvalidValue;
            return self.tag(label, try self.fromJson(field(t, "value")));
        }
        if (input.object.get("record")) |r| {
            if (r != .object) return error.InvalidValue;
            const fields = try self.allocator.alloc(Field, r.object.count());
            var it = r.object.iterator();
            var i: usize = 0;
            while (it.next()) |f| : (i += 1) fields[i] = .{ .name = f.key_ptr.*, .value = try self.fromJson(f.value_ptr.*) };
            return .{ .record = fields };
        }
        if (input.object.get("list")) |r| {
            if (r != .array) return error.InvalidValue;
            var list: ?*const List = null;
            var i = r.array.items.len;
            while (i > 0) {
                i -= 1;
                list = (try self.cons(try self.fromJson(r.array.items[i]), list)).list;
            }
            return .{ .list = list };
        }
        return error.InvalidValue;
    }
    pub fn toPlainJson(self: *Engine, value: Value) anyerror!Json {
        return switch (value) {
            .integer => |i| if (i >= -safe_integer and i <= safe_integer) .{ .integer = i } else try numberJson(self.allocator, @floatFromInt(i)),
            .javascript_integer => |f| try numberJson(self.allocator, f),
            .string, .binary => |s| .{ .string = s },
            .list => |head| blk: {
                var list = std.ArrayList(Json).init(self.allocator);
                var cursor = head;
                while (cursor) |cell| : (cursor = cell.tail) try list.append(try self.toPlainJson(cell.head));
                break :blk .{ .array = list };
            },
            .record => |fields| blk: {
                var result = std.json.ObjectMap.init(self.allocator);
                for (fields) |f| try result.put(f.name, try self.toPlainJson(f.value));
                break :blk .{ .object = result };
            },
            .tagged => |t| if (eq(t.label, "True")) .{ .bool = true } else if (eq(t.label, "False")) .{ .bool = false } else try object(self.allocator, &.{ .{ "label", .{ .string = t.label } }, .{ "value", try self.toPlainJson(t.value) } }),
            else => .null,
        };
    }
    pub fn fromPlainJson(self: *Engine, input: Json) anyerror!Value {
        return switch (input) {
            .integer => |i| numberValue(@floatFromInt(i)),
            .float => |f| blk: {
                if (!std.math.isFinite(f) or @trunc(f) != f) return error.InvalidValue;
                break :blk numberValue(f);
            },
            .number_string => |s| numberValue(codec.jsonInteger(.{ .number_string = s }) orelse return error.InvalidValue),
            .string => |s| .{ .string = s },
            .bool => |b| self.boolean(b),
            .null => unit(),
            .array => |list| blk: {
                var tail: ?*const List = null;
                var i = list.items.len;
                while (i > 0) {
                    i -= 1;
                    tail = (try self.cons(try self.fromPlainJson(list.items[i]), tail)).list;
                }
                break :blk .{ .list = tail };
            },
            .object => |map| blk: {
                const fields = try self.allocator.alloc(Field, map.count());
                var it = map.iterator();
                var i: usize = 0;
                while (it.next()) |f| : (i += 1) fields[i] = .{ .name = f.key_ptr.*, .value = try self.fromPlainJson(f.value_ptr.*) };
                break :blk .{ .record = fields };
            },
        };
    }
    pub fn reasonJson(self: *Engine, reason: Reason) anyerror!Json {
        const a = self.allocator;
        return switch (reason) {
            .undefined_variable => |s| object(a, &.{.{ "UndefinedVariable", .{ .string = s } }}),
            .undefined_builtin => |s| object(a, &.{.{ "UndefinedBuiltin", .{ .string = s } }}),
            .undefined_reference => |r| object(a, &.{.{ "UndefinedReference", r }}),
            .vacant => object(a, &.{.{ "NotImplemented", .{ .string = "" } }}),
            .step_limit => object(a, &.{.{ "StepLimit", .{ .integer = @intCast(self.max_steps) } }}),
            .not_a_function => |v| object(a, &.{.{ "NotAFunction", try self.toJson(v) }}),
            .no_match => |v| object(a, &.{.{ "NoMatch", try self.toJson(v) }}),
            .missing_field => |s| object(a, &.{.{ "MissingField", .{ .string = s } }}),
            .incorrect_term => |t| object(a, &.{.{ "IncorrectTerm", try object(a, &.{ .{ "expected", .{ .string = t.expected } }, .{ "got", try self.toJson(t.got) } }) }}),
            .unhandled_effect => |t| object(a, &.{.{ "UnhandledEffect", try object(a, &.{ .{ "label", .{ .string = t.label } }, .{ "value", try self.toJson(t.value) } }) }}),
            .unrepresentable => |u| blk: {
                var args = std.ArrayList(Json).init(a);
                for (u.args) |v| try args.append(try self.toJson(v));
                break :blk object(a, &.{.{ "Unrepresentable", try object(a, &.{ .{ "builtin", .{ .string = u.builtin } }, .{ "args", .{ .array = args } } }) }});
            },
        };
    }
    pub fn describe(self: *Engine) anyerror![]const u8 {
        const a = self.allocator;
        const r = self.failure orelse return "unknown interpreter error";
        return switch (r) {
            .vacant => "tried to run a todo",
            .undefined_variable => |s| std.fmt.allocPrint(a, "variable undefined: {s}", .{s}),
            .undefined_builtin => |s| std.fmt.allocPrint(a, "builtin undefined: !{s}", .{s}),
            .undefined_reference => |ir| blk: {
                const code = stringField(ir, "0") orelse "";
                if (eq(code, ".")) break :blk std.fmt.allocPrint(a, "relative location undefined: {s}", .{stringField(ir, "i") orelse ""});
                if (eq(code, "@")) {
                    const package = stringField(ir, "p") orelse "";
                    const version = field(ir, "r");
                    if (version == .integer) break :blk std.fmt.allocPrint(a, "{s} undefined: @{s}:{d}", .{ if (field(ir, "l") == .null) "version" else "release", package, version.integer });
                    break :blk std.fmt.allocPrint(a, "package undefined: @{s}", .{package});
                }
                break :blk std.fmt.allocPrint(a, "reference undefined: #{s}", .{stringField(field(ir, "l"), "/") orelse ""});
            },
            .not_a_function => |v| std.fmt.allocPrint(a, "function expected got: {s}", .{try self.inspect(v)}),
            .no_match => |v| std.fmt.allocPrint(a, "no cases matched for: {s}", .{try self.inspect(v)}),
            .missing_field => |s| std.fmt.allocPrint(a, "missing record field: {s}", .{s}),
            .incorrect_term => |v| std.fmt.allocPrint(a, "unexpected term, expected: {s} got: {s}", .{ v.expected, try self.inspect(v.got) }),
            .unhandled_effect => |v| if (eq(v.label, "Abort")) std.fmt.allocPrint(a, "Aborted with reason: {s}", .{try self.inspect(v.value)}) else std.fmt.allocPrint(a, "unhandled effect {s}({s})", .{ v.label, try self.inspect(v.value) }),
            .unrepresentable => "integer out of range",
            .step_limit => "evaluation step limit exceeded",
        };
    }
    pub fn inspect(self: *Engine, value: Value) anyerror![]const u8 {
        return self.render(value, 80);
    }
    pub fn render(self: *Engine, value: Value, width: usize) anyerror![]const u8 {
        return @import("pretty.zig").render(self.allocator, value, width);
    }
};

pub fn evaluate(allocator: Allocator, ir: Json) anyerror!Json {
    var engine = Engine.init(allocator);
    return engine.evaluate(ir);
}
pub fn evaluateFixture(allocator: Allocator, fixture: Json) anyerror!Json {
    var engine = Engine.init(allocator);
    var result: ?Value = engine.eval(field(fixture, "source")) catch |err| blk: {
        if (err == error.InvalidIR) return object(allocator, &.{.{ "decode_error", .{ .bool = true } }});
        if (err != error.Runtime) return err;
        break :blk null;
    };
    const effects = field(fixture, "effects");
    if (effects == .array) for (effects.array.items) |effect| {
        if (result != null or engine.failure == null or engine.failure.? != .unhandled_effect) return error.EffectMismatch;
        const raised = engine.failure.?.unhandled_effect;
        if (!eq(raised.label, stringField(effect, "label") orelse "")) return error.EffectMismatch;
        if (!equal(raised.value, try engine.fromJson(field(effect, "lift")))) return error.EffectMismatch;
        result = engine.@"resume"(try engine.fromJson(field(effect, "reply"))) catch |err| blk: {
            if (err != error.Runtime) return err;
            break :blk null;
        };
    };
    return if (result) |v| object(allocator, &.{.{ "value", try engine.toJson(v) }}) else object(allocator, &.{.{ "break", try engine.reasonJson(engine.failure.?) }});
}
/// Validate the stable IR boundary before evaluation, as the oracle decoder
/// does. Unknown builtins and references are valid IR and break during eval.
pub fn validIr(ir: Json) bool {
    const code = stringField(ir, "0") orelse return false;
    if (eq(code, "a")) return validIr(field(ir, "f")) and validIr(field(ir, "a"));
    if (eq(code, "l")) return stringField(ir, "l") != null and validIr(field(ir, "v")) and validIr(field(ir, "t"));
    if (eq(code, "f")) return stringField(ir, "l") != null and validIr(field(ir, "b"));
    if (eq(code, "i")) {
        const value = codec.jsonInteger(field(ir, "v")) orelse return false;
        return value >= -safe_integer and value <= safe_integer;
    }
    if (eq(code, "s")) return stringField(ir, "v") != null;
    if (eq(code, "x")) {
        const bytes = stringField(field(field(ir, "v"), "/"), "bytes") orelse return false;
        return codec.base64Size(bytes) != null;
    }
    if (eq(code, ".")) return stringField(ir, "i") != null;
    if (eq(code, "#")) return codec.validCid(stringField(field(ir, "l"), "/") orelse return false);
    if (eq(code, "@")) {
        if (stringField(ir, "p") == null) return false;
        const version = field(ir, "r");
        const module = field(ir, "l");
        if (ir.object.contains("r") and codec.jsonInteger(version) == null) return false;
        if (ir.object.contains("l") and (!ir.object.contains("r") or !codec.validCid(stringField(module, "/") orelse return false))) return false;
        return true;
    }
    if (eq(code, "u") or eq(code, "ta") or eq(code, "c") or eq(code, "z") or eq(code, "n")) return true;
    if (eq(code, "e") or eq(code, "o") or eq(code, "g") or eq(code, "t") or eq(code, "m") or eq(code, "p") or eq(code, "h") or eq(code, "b") or eq(code, "v")) return stringField(ir, "l") != null;
    return false;
}
fn canonicalReference(allocator: Allocator, ir: Json) !Json {
    const code = stringField(ir, "0").?;
    if (eq(code, ".")) return object(allocator, &.{ .{ "0", .{ .string = "." } }, .{ "i", field(ir, "i") } });
    const cid = if (ir.object.contains("l")) try object(allocator, &.{.{ "/", .{ .string = try codec.canonicalCid(allocator, stringField(field(ir, "l"), "/").?) } }}) else Json.null;
    if (eq(code, "#")) return object(allocator, &.{ .{ "0", .{ .string = "#" } }, .{ "l", cid } });
    var reference = try object(allocator, &.{ .{ "0", .{ .string = "@" } }, .{ "p", field(ir, "p") } });
    if (ir.object.contains("r")) {
        const number = codec.jsonInteger(field(ir, "r")).?;
        const version: Json = if (number >= -9007199254740991 and number <= 9007199254740991) .{ .integer = @intFromFloat(number) } else if (@abs(number) < 1e21) .{ .number_string = try std.fmt.allocPrint(allocator, "{d}", .{number}) } else .{ .float = number };
        try reference.object.put("r", version);
    }
    if (cid != .null) try reference.object.put("l", cid);
    return reference;
}
/// Keep the native representation for ordinary integral values. Every value
/// is first interpreted as a JavaScript Number at this host boundary.
// The oracle gives each Integer object an identity. Only NaN makes that
// identity observable through structural equality. Quiet-NaN payloads retain
// it across value copies without boxing ordinary numbers or enlarging Value.
var next_nan_identity = std.atomic.Value(u64).init(1);
pub fn numberValue(value: f64) Value {
    if (std.math.isNan(value)) {
        const identity = next_nan_identity.fetchAdd(1, .monotonic) & 0x0007ffffffffffff;
        return .{ .javascript_integer = @bitCast(@as(u64, 0x7ff8000000000000) | identity) };
    }
    if (std.math.isFinite(value) and @trunc(value) == value and value >= -0x1p63 and value < 0x1p63) return .{ .integer = @intFromFloat(value) };
    return .{ .javascript_integer = value };
}
pub fn numberFloat(value: Value) ?f64 {
    return switch (value) {
        .integer => |i| @floatFromInt(i),
        .javascript_integer => |f| f,
        else => null,
    };
}
fn safeNative(value: Value) bool {
    return value == .integer and value.integer >= -safe_integer and value.integer <= safe_integer;
}
pub fn numberText(allocator: Allocator, value: f64) ![]const u8 {
    return codec.ecmaNumber(allocator, value);
}
pub fn integerText(allocator: Allocator, value: i64) ![]const u8 {
    return if (value >= -safe_integer and value <= safe_integer) std.fmt.allocPrint(allocator, "{d}", .{value}) else numberText(allocator, @floatFromInt(value));
}
pub fn numberJson(allocator: Allocator, value: f64) !Json {
    return if (std.math.isFinite(value)) .{ .number_string = try numberText(allocator, value) } else .null;
}
fn toUint8(value: f64) u8 {
    if (!std.math.isFinite(value) or value == 0) return 0;
    return @intFromFloat(@mod(@trunc(value), 256.0));
}
pub fn unit() Value {
    return .{ .record = &.{} };
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn field(value: Json, name: []const u8) Json {
    return if (value == .object) value.object.get(name) orelse .null else .null;
}
pub fn stringField(value: Json, name: []const u8) ?[]const u8 {
    const v = field(value, name);
    return if (v == .string) v.string else null;
}
pub fn object(allocator: Allocator, fields: []const struct { []const u8, Json }) !Json {
    var map = std.json.ObjectMap.init(allocator);
    for (fields) |f| try map.put(f[0], f[1]);
    return .{ .object = map };
}
pub fn encodeBase64(allocator: Allocator, bytes: []const u8) ![]const u8 {
    const encoder = std.base64.standard_no_pad.Encoder;
    const output = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    return encoder.encode(output, bytes);
}
pub fn encodeBytes(allocator: Allocator, bytes: []const u8) !Json {
    return object(allocator, &.{.{ "/", try object(allocator, &.{.{ "bytes", .{ .string = try encodeBase64(allocator, bytes) } }}) }});
}
pub fn decodeBytes(allocator: Allocator, value: Json) ![]const u8 {
    const text = stringField(field(value, "/"), "bytes") orelse return error.InvalidBinary;
    return codec.decodeBase64(allocator, text);
}
pub fn equal(a: Value, b: Value) bool {
    if (safeNative(a) and safeNative(b)) return a.integer == b.integer;
    if (numberFloat(a)) |left| {
        const right = numberFloat(b) orelse return false;
        if (std.math.isNan(left) and std.math.isNan(right)) return @as(u64, @bitCast(left)) == @as(u64, @bitCast(right));
        return left == right;
    }
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .integer => |v| v == b.integer,
        .javascript_integer => |v| v == b.javascript_integer,
        .string => |v| eq(v, b.string),
        .binary => |v| eq(v, b.binary),
        .tagged => |v| eq(v.label, b.tagged.label) and equal(v.value, b.tagged.value),
        .list => |v| blk: {
            var x = v;
            var y = b.list;
            while (x) |cx| {
                const cy = y orelse break :blk false;
                if (!equal(cx.head, cy.head)) break :blk false;
                x = cx.tail;
                y = cy.tail;
            }
            break :blk y == null;
        },
        .record => |fields| blk: {
            if (fields.len != b.record.len) break :blk false;
            for (fields) |f| {
                var found = false;
                for (b.record) |g| if (eq(f.name, g.name)) {
                    if (!equal(f.value, g.value)) break :blk false;
                    found = true;
                    break;
                };
                if (!found) break :blk false;
            }
            break :blk true;
        },
        .partial => |p| blk: {
            const q = b.partial;
            if (p.kind != q.kind or !eq(p.label, q.label) or p.args.len != q.args.len) break :blk false;
            for (p.args, q.args) |x, y| if (!equal(x, y)) break :blk false;
            break :blk true;
        },
        .closure => |c| eq(c.param, b.closure.param) and irEqual(c.body, b.closure.body) and envEqual(c.env, b.closure.env),
        .@"resume" => |r| r == b.@"resume",
    };
}
/// The oracle decoder discards non-IR fields and normalizes encoded data.
/// Editor annotations and accepted aliases must not change closure equality.
fn irEqual(left: Json, right: Json) bool {
    const code = stringField(left, "0") orelse return false;
    if (!eq(code, stringField(right, "0") orelse return false)) return false;
    if (left == .object and right == .object and left.object.keys().ptr == right.object.keys().ptr and left.object.count() == right.object.count()) return true;
    if (eq(code, "a")) return irEqual(field(left, "f"), field(right, "f")) and irEqual(field(left, "a"), field(right, "a"));
    if (eq(code, "l")) return eq(stringField(left, "l").?, stringField(right, "l").?) and irEqual(field(left, "v"), field(right, "v")) and irEqual(field(left, "t"), field(right, "t"));
    if (eq(code, "f")) return eq(stringField(left, "l").?, stringField(right, "l").?) and irEqual(field(left, "b"), field(right, "b"));
    if (eq(code, "i")) {
        const a: f64 = switch (field(left, "v")) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            .number_string => |text| std.fmt.parseFloat(f64, text) catch return false,
            else => return false,
        };
        const b: f64 = switch (field(right, "v")) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            .number_string => |text| std.fmt.parseFloat(f64, text) catch return false,
            else => return false,
        };
        return a == b;
    }
    if (eq(code, "s")) return eq(stringField(left, "v").?, stringField(right, "v").?);
    if (eq(code, "x")) return codec.base64Equal(stringField(field(field(left, "v"), "/"), "bytes").?, stringField(field(field(right, "v"), "/"), "bytes").?);
    if (eq(code, "#")) return codec.cidEqual(stringField(field(left, "l"), "/").?, stringField(field(right, "l"), "/").?);
    if (eq(code, ".")) return eq(stringField(left, "i").?, stringField(right, "i").?);
    if (eq(code, "@")) {
        if (!eq(stringField(left, "p").?, stringField(right, "p").?)) return false;
        if (left.object.contains("r") != right.object.contains("r") or left.object.contains("l") != right.object.contains("l")) return false;
        if (left.object.contains("r") and codec.jsonInteger(field(left, "r")) != codec.jsonInteger(field(right, "r"))) return false;
        return !left.object.contains("l") or codec.cidEqual(stringField(field(left, "l"), "/").?, stringField(field(right, "l"), "/").?);
    }
    if (eq(code, "u") or eq(code, "ta") or eq(code, "c") or eq(code, "n") or eq(code, "z")) return true;
    return eq(stringField(left, "l").?, stringField(right, "l").?);
}
fn envEqual(a: ?*const Binding, b: ?*const Binding) bool {
    var x = a;
    var y = b;
    while (x) |cx| {
        const cy = y orelse return false;
        if (!eq(cx.name, cy.name) or !equal(cx.value, cy.value)) return false;
        x = cx.next;
        y = cy.next;
    }
    return y == null;
}
pub fn jsonEqual(a: Json, b: Json) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => |v| v == b.bool,
        .integer => |v| v == b.integer,
        .float => |v| v == b.float,
        .string => |v| eq(v, b.string),
        .number_string => |v| eq(v, b.number_string),
        .array => |v| blk: {
            if (v.items.len != b.array.items.len) break :blk false;
            for (v.items, b.array.items) |x, y| if (!jsonEqual(x, y)) break :blk false;
            break :blk true;
        },
        .object => |v| blk: {
            if (v.count() != b.object.count()) break :blk false;
            var it = v.iterator();
            while (it.next()) |f| if (!jsonEqual(f.value_ptr.*, b.object.get(f.key_ptr.*) orelse break :blk false)) break :blk false;
            break :blk true;
        },
    };
}
fn validIntegerText(text: []const u8) bool {
    if (text.len == 0) return false;
    const start: usize = if (text[0] == '-' or text[0] == '+') 1 else 0;
    if (start == text.len) return false;
    for (text[start..]) |c| if (c < '0' or c > '9') return false;
    return true;
}

const Builtin = enum {
    equal,
    fix,
    fixed,
    never,
    int_compare,
    int_add,
    int_subtract,
    int_multiply,
    int_divide,
    int_absolute,
    int_parse,
    int_to_string,
    string_append,
    string_split,
    string_split_once,
    string_replace,
    string_uppercase,
    string_lowercase,
    string_starts_with,
    string_ends_with,
    string_length,
    string_to_binary,
    string_from_binary,
    binary_from_integers,
    binary_size,
    binary_concat,
    binary_compare,
    binary_fold,
    list_pop,
    list_fold,
};
const builtinMap = blk: {
    var entries: [std.meta.fields(Builtin).len]struct { []const u8, Builtin } = undefined;
    for (std.meta.fields(Builtin), 0..) |f, i| entries[i] = .{ f.name, @enumFromInt(f.value) };
    break :blk std.StaticStringMap(Builtin).initComptime(entries);
};
fn builtinArity(op: Builtin) usize {
    return switch (op) {
        .equal, .fixed, .int_compare, .int_add, .int_subtract, .int_multiply, .int_divide, .string_append, .string_split, .string_split_once, .string_starts_with, .string_ends_with, .binary_concat, .binary_compare => 2,
        .string_replace, .binary_fold, .list_fold => 3,
        else => 1,
    };
}

// Grapheme and case tables are implemented in the companion Unicode module.
const unicode = @import("unicode.zig");
pub fn graphemeEnd(text: []const u8, start: usize) usize {
    return unicode.graphemeEnd(text, start);
}
fn changeCase(allocator: Allocator, text: []const u8, upper: bool) ![]const u8 {
    return unicode.changeCase(allocator, text, upper);
}

test "core spec and builtin/effect suites" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for ([_][]const u8{ "core_suite.json", "builtins_suite.json", "effects_suite.json" }) |filename| {
        const path = try std.fmt.allocPrint(allocator, "tests/fixtures/evaluation/{s}", .{filename});
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024);
        const parsed = try std.json.parseFromSlice(Json, allocator, source, .{ .allocate = .alloc_always });
        for (parsed.value.array.items) |fixture| {
            const actual = try evaluateFixture(allocator, fixture);
            const expected = if (field(fixture, "value") != .null) try object(allocator, &.{.{ "value", field(fixture, "value") }}) else try object(allocator, &.{.{ "break", field(fixture, "break") }});
            if (!jsonEqual(actual, expected)) {
                std.debug.print("\nfixture {s}:\nactual {s}\nexpected {s}\n", .{ stringField(fixture, "name") orelse "", try std.json.stringifyAlloc(allocator, actual, .{}), try std.json.stringifyAlloc(allocator, expected, .{}) });
                return error.TestExpectedEqual;
            }
        }
    }
}

test "host values reject malformed JSON without tagged union traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var engine = Engine.init(arena.allocator());
    for ([_][]const u8{ "{\"integer\":\"bad\"}", "{\"record\":[]}", "{\"list\":{}}", "{\"tagged\":{\"label\":1,\"value\":{}}}" }) |text| {
        const input = try std.json.parseFromSlice(Json, arena.allocator(), text, .{});
        try std.testing.expectError(error.InvalidValue, engine.fromJson(input.value));
    }
}

test "cooperative slices preserve recursive evaluation and effect resumption" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parser = @import("parser.zig");
    const source = "let sum = !fix((self, n) -> { match !int_compare(n, 0) { Eq(_) -> { 0 } | (_) -> { !int_add(n, self(!int_subtract(n, 1))) } } }) !int_add(perform Probe(sum(200)), 1)";
    const program = try parser.parse(a, source);
    var engine = Engine.init(a);
    engine.time_budget_ns = 1;
    var yielded: usize = 0;
    var stopped: anyerror = error.Yield;
    _ = engine.eval(program) catch |err| blk: {
        stopped = err;
        break :blk unit();
    };
    while (stopped == error.Yield) {
        yielded += 1;
        try std.testing.expect(engine.failure == null);
        _ = engine.continueRun() catch |err| {
            stopped = err;
            continue;
        };
        return error.TestExpectedUnhandledEffect;
    }
    try std.testing.expect(yielded > 0);
    try std.testing.expectEqual(error.Runtime, stopped);
    try std.testing.expect(engine.failure.? == .unhandled_effect);
    try std.testing.expectEqualStrings("Probe", engine.failure.?.unhandled_effect.label);
    try std.testing.expectEqual(@as(i64, 20100), engine.failure.?.unhandled_effect.value.integer);
    var result: ?Value = engine.@"resume"(.{ .integer = 41 }) catch |err| blk: {
        try std.testing.expectEqual(error.Yield, err);
        break :blk null;
    };
    while (result == null) {
        result = engine.continueRun() catch |err| {
            try std.testing.expectEqual(error.Yield, err);
            continue;
        };
    }
    try std.testing.expectEqual(@as(i64, 42), result.?.integer);
}

test "closure equality ignores editor metadata and normalizes IR aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pairs = [_][2][]const u8{
        .{ "{\"0\":\"v\",\"l\":\"x\",\"_native_node\":1}", "{\"0\":\"v\",\"l\":\"x\",\"_native_node\":2}" },
        .{ "{\"0\":\"x\",\"v\":{\"/\":{\"bytes\":\"AQ\"}}}", "{\"0\":\"x\",\"v\":{\"/\":{\"bytes\":\"AR==\"}}}" },
        .{ "{\"0\":\"i\",\"v\":1}", "{\"0\":\"i\",\"v\":1.0,\"ignored\":true}" },
    };
    var engine = Engine.init(a);
    for (pairs) |pair| {
        const left = try std.json.parseFromSlice(Json, a, pair[0], .{});
        const right = try std.json.parseFromSlice(Json, a, pair[1], .{});
        const left_function = try object(a, &.{ .{ "0", .{ .string = "f" } }, .{ "l", .{ .string = "x" } }, .{ "b", left.value } });
        const right_function = try object(a, &.{ .{ "0", .{ .string = "f" } }, .{ "l", .{ .string = "x" } }, .{ "b", right.value } });
        const x = try engine.eval(left_function);
        const y = try engine.eval(right_function);
        try std.testing.expect(equal(x, y));
    }
}

test "JavaScript integer slow path preserves wide and nonfinite values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parser = @import("parser.zig");
    var engine = Engine.init(a);
    try engine.bind("large", numberValue(1e100));
    try engine.bind("infinite", numberValue(std.math.inf(f64)));
    try engine.bind("nan", numberValue(std.math.nan(f64)));
    try engine.bind("minimum", .{ .integer = std.math.minInt(i64) });
    const subtract = try engine.eval(try parser.parse(a, "!int_subtract(large, large)"));
    try std.testing.expectEqual(@as(i64, 0), subtract.integer);
    const multiply = try engine.eval(try parser.parse(a, "!int_multiply(large, 0)"));
    try std.testing.expectEqual(@as(i64, 0), multiply.integer);
    try std.testing.expectError(error.Runtime, engine.eval(try parser.parse(a, "!int_add(large, 1)")));
    try std.testing.expect(engine.failure.? == .unrepresentable);
    const quotient = try engine.eval(try parser.parse(a, "!int_divide(large, large)"));
    try std.testing.expectEqual(@as(i64, 1), quotient.tagged.value.integer);
    const nonfinite = try engine.eval(try parser.parse(a, "!int_divide(infinite, infinite)"));
    try std.testing.expect(std.math.isNan(nonfinite.tagged.value.javascript_integer));
    try std.testing.expectEqualStrings("{\"tagged\":{\"label\":\"Ok\",\"value\":{\"integer\":null}}}", try std.json.stringifyAlloc(a, try engine.toJson(nonfinite), .{}));
    const absolute = try engine.eval(try parser.parse(a, "!int_absolute(minimum)"));
    try std.testing.expectEqual(@as(f64, 0x1p63), absolute.javascript_integer);
    try std.testing.expectEqualStrings("9223372036854776000", try engine.inspect(absolute));
    const text = try engine.eval(try parser.parse(a, "!int_to_string(large)"));
    try std.testing.expectEqualStrings("1e+100", text.string);
    const comparison = try engine.eval(try parser.parse(a, "!int_compare(nan, 0)"));
    try std.testing.expectEqualStrings("Gt", comparison.tagged.label);
    try std.testing.expect(!equal(numberValue(std.math.nan(f64)), numberValue(std.math.nan(f64))));
    const shared_nan = numberValue(std.math.nan(f64));
    try std.testing.expect(equal(shared_nan, shared_nan));
    try std.testing.expect(!equal(shared_nan, numberValue(std.math.nan(f64))));
    try std.testing.expect(equal(.{ .integer = 42 }, .{ .javascript_integer = 42 }));
    const bytes = try engine.eval(try parser.parse(a, "!binary_from_integers([infinite, nan, 255, -1, large])"));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255, 0 }, bytes.binary);
    const literal = try object(a, &.{ .{ "0", .{ .string = "i" } }, .{ "v", .{ .float = 1e100 } } });
    try std.testing.expectError(error.InvalidIR, engine.eval(literal));
    try std.testing.expectEqual(@as(f64, 1e100), (try engine.evalTrusted(literal)).javascript_integer);
}
