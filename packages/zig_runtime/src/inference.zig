//! Level-based Hindley–Milner inference with open record, union and effect rows.
//! This follows next-tui's contextual checker, including best-effort bindings
//! retained on errors. Runtime values and type variables live in separate graphs.
const std = @import("std");
const runtime = @import("interpreter.zig");
const pretty = @import("pretty.zig");
const A = std.mem.Allocator;
const J = std.json.Value;
const T = *Type;
const Type = union(enum) {
    variable: *Variable,
    quantified: usize,
    integer,
    string,
    binary,
    empty,
    never,
    dynamic,
    list: T,
    record: T,
    tagged: T,
    promise: T,
    function: struct { arg: T, eff: T, ret: T },
    row: struct { label: []const u8, field: T, tail: T },
    effect: struct { label: []const u8, lift: T, reply: T, tail: T },
};
const Variable = struct { id: usize, level: i32, link: ?T = null };
const Env = struct { name: []const u8, scheme: T, next: ?*const Env };
const Reason = union(enum) {
    todo,
    missing_variable: []const u8,
    missing_builtin: []const u8,
    missing_reference: J,
    missing_row: []const u8,
    mismatch: struct { expected: T, given: T },
    recursive,
    same_tail: struct { expected: T, given: T },
};
const RawInfo = struct { node: usize, ty: T, effect: T, env: ?*const Env, reason: ?Reason, depth: usize, ordinal: usize, loading: bool = false, path: []const usize = &.{}, annotated: bool = false };
pub const Info = struct {
    type_text: []const u8,
    problem: ?[]const u8,
    effect_text: []const u8,
    scope: []const ScopeItem,
    loading: bool = false,
    fields: []const ScopeItem = &.{},
    variants: []const ScopeItem = &.{},
};
pub const ScopeItem = struct { name: []const u8, type_text: []const u8 };
const PathInfo = struct { path: []const usize, info: Info, ordinal: usize };
pub const Analysis = struct {
    info: std.AutoHashMap(usize, Info),
    error_count: usize,
    loading_count: usize,
    root_type: []const u8,
    error_paths: []const []const usize = &.{},
    path_info: []const PathInfo = &.{},

    /// The pinned checker selects the first preorder occurrence of an original
    /// annotation. Lowering can give several IR nodes the same editable path.
    pub fn infoAtPath(self: *const Analysis, path: []const usize) ?Info {
        for (self.path_info) |entry| if (std.mem.eql(usize, path, entry.path)) return entry.info;
        return null;
    }
};
pub const ReferenceResolver = *const fn (?*anyopaque, A, J) anyerror!?J;
pub const Options = struct {
    reference_resolver: ?ReferenceResolver = null,
    reference_loading: ?*const fn (?*anyopaque, J) bool = null,
    reference_context: ?*anyopaque = null,
    scope_cache: ?*ScopeCache = null,
    collect_scope: bool = true,
    collect_effects: bool = true,
    collect_paths: bool = false,
    /// Native-only foreign capabilities are absent in the oracle profile.
    native_effects: bool = false,
};
const FrozenScope = struct { env: ?*const Env, next_id: usize };
/// Immutable runtime scopes are keyed by identity. The stored type graph is
/// never unified against a draft; each analysis receives a private graph copy.
pub const ScopeCache = struct {
    allocator: A,
    contexts: std.AutoHashMap(usize, FrozenScope),
    pub fn init(allocator: A) ScopeCache {
        return .{ .allocator = allocator, .contexts = std.AutoHashMap(usize, FrozenScope).init(allocator) };
    }
    fn get(self: *ScopeCache, scope: ?*const runtime.Binding) anyerror!FrozenScope {
        const key = if (scope) |head| @intFromPtr(head) else 0;
        if (self.contexts.get(key)) |cached| return cached;
        var checker = try Checker.init(self.allocator);
        const env = try checker.environment(scope);
        const frozen = FrozenScope{ .env = env, .next_id = checker.next_id };
        try self.contexts.put(key, frozen);
        return frozen;
    }
};
const Result = struct { ty: T, eff: T };
const Checker = struct {
    allocator: A,
    next_id: usize = 0,
    next_ordinal: usize = 0,
    failure: ?Reason = null,
    infos: std.ArrayList(RawInfo),
    builtin_types: std.StringHashMap(T),
    empty: T,
    integer: T,
    string: T,
    binary: T,
    never: T,
    options: Options = .{},
    rendered_types: std.AutoHashMap(T, []const u8),
    rendered_scopes: std.AutoHashMap(usize, []const ScopeItem),

    fn init(a: A) !Checker {
        var c = Checker{ .allocator = a, .infos = std.ArrayList(RawInfo).init(a), .builtin_types = std.StringHashMap(T).init(a), .empty = undefined, .integer = undefined, .string = undefined, .binary = undefined, .never = undefined, .rendered_types = std.AutoHashMap(T, []const u8).init(a), .rendered_scopes = std.AutoHashMap(usize, []const ScopeItem).init(a) };
        c.empty = try c.make(.empty);
        c.integer = try c.make(.integer);
        c.string = try c.make(.string);
        c.binary = try c.make(.binary);
        c.never = try c.make(.never);
        const data = try std.json.parseFromSlice(J, a, @embedFile("builtin_types.json"), .{});
        var it = data.value.object.iterator();
        while (it.next()) |entry| try c.builtin_types.put(entry.key_ptr.*, try c.decode(entry.value_ptr.*));
        return c;
    }
    fn make(c: *Checker, value: Type) !T {
        const t = try c.allocator.create(Type);
        t.* = value;
        return t;
    }
    fn fresh(c: *Checker, level: i32) !T {
        const v = try c.allocator.create(Variable);
        v.* = .{ .id = c.next_id, .level = level };
        c.next_id += 1;
        return c.make(.{ .variable = v });
    }
    fn fun(c: *Checker, arg: T, eff: T, ret: T) !T {
        return c.make(.{ .function = .{ .arg = arg, .eff = eff, .ret = ret } });
    }
    fn row(c: *Checker, label: []const u8, value: T, tail: T) !T {
        return c.make(.{ .row = .{ .label = label, .field = value, .tail = tail } });
    }
    fn effect(c: *Checker, label: []const u8, lift: T, reply: T, tail: T) !T {
        return c.make(.{ .effect = .{ .label = label, .lift = lift, .reply = reply, .tail = tail } });
    }
    fn record(c: *Checker, rows: T) !T {
        return c.make(.{ .record = rows });
    }
    fn list(c: *Checker, inner: T) !T {
        return c.make(.{ .list = inner });
    }
    fn tagged(c: *Checker, rows: T) !T {
        return c.make(.{ .tagged = rows });
    }
    fn q(c: *Checker, id: usize) !T {
        return c.make(.{ .quantified = id });
    }
    fn pure1(c: *Checker, arg: T, ret: T) !T {
        return c.fun(arg, c.empty, ret);
    }
    fn pure2(c: *Checker, a: T, b: T, ret: T) !T {
        return c.pure1(a, try c.pure1(b, ret));
    }
    fn decode(c: *Checker, input: J) anyerror!T {
        const parts = input.array.items;
        const name = parts[0].string;
        if (eq(name, "Var")) return c.q(@intCast(parts[1].array.items[1].integer));
        if (eq(name, "Integer")) return c.integer;
        if (eq(name, "String")) return c.string;
        if (eq(name, "Binary")) return c.binary;
        if (eq(name, "Empty")) return c.empty;
        if (eq(name, "Never")) return c.never;
        if (eq(name, "Fun")) return c.fun(try c.decode(parts[1]), try c.decode(parts[2]), try c.decode(parts[3]));
        if (eq(name, "RowExtend")) return c.row(parts[1].string, try c.decode(parts[2]), try c.decode(parts[3]));
        if (eq(name, "EffectExtend")) return c.effect(parts[1].string, try c.decode(parts[2]), try c.decode(parts[3]), try c.decode(parts[4]));
        const inner = try c.decode(parts[1]);
        if (eq(name, "List")) return c.list(inner);
        if (eq(name, "Record")) return c.record(inner);
        if (eq(name, "Union")) return c.tagged(inner);
        if (eq(name, "Promise")) return c.make(.{ .promise = inner });
        return error.UnknownType;
    }
    fn instantiate(c: *Checker, ty: T, level: i32) anyerror!T {
        var substitutions = std.AutoHashMap(usize, T).init(c.allocator);
        return c.inst(ty, level, &substitutions);
    }
    fn inst(c: *Checker, ty: T, level: i32, subs: *std.AutoHashMap(usize, T)) anyerror!T {
        return switch (ty.*) {
            .quantified => |id| blk: {
                if (subs.get(id)) |v| break :blk v;
                const v = try c.fresh(level);
                try subs.put(id, v);
                break :blk v;
            },
            .function => |f| c.fun(try c.inst(f.arg, level, subs), try c.inst(f.eff, level, subs), try c.inst(f.ret, level, subs)),
            .list => |t| c.list(try c.inst(t, level, subs)),
            .record => |t| c.record(try c.inst(t, level, subs)),
            .tagged => |t| c.tagged(try c.inst(t, level, subs)),
            .promise => |t| c.make(.{ .promise = try c.inst(t, level, subs) }),
            .row => |r| c.row(r.label, try c.inst(r.field, level, subs), try c.inst(r.tail, level, subs)),
            .effect => |e| c.effect(e.label, try c.inst(e.lift, level, subs), try c.inst(e.reply, level, subs), try c.inst(e.tail, level, subs)),
            else => ty,
        };
    }
    fn generalize(c: *Checker, ty: T, level: i32) anyerror!T {
        const t = resolve(ty);
        return switch (t.*) {
            .variable => |v| if (v.level > level) c.q(v.id) else t,
            .function => |f| c.fun(try c.generalize(f.arg, level), try c.generalize(f.eff, level), try c.generalize(f.ret, level)),
            .list => |x| c.list(try c.generalize(x, level)),
            .record => |x| c.record(try c.generalize(x, level)),
            .tagged => |x| c.tagged(try c.generalize(x, level)),
            .promise => |x| c.make(.{ .promise = try c.generalize(x, level) }),
            .row => |r| c.row(r.label, try c.generalize(r.field, level), try c.generalize(r.tail, level)),
            .effect => |e| c.effect(e.label, try c.generalize(e.lift, level), try c.generalize(e.reply, level), try c.generalize(e.tail, level)),
            else => t,
        };
    }
    fn openEffect(c: *Checker, ty: T, level: i32) anyerror!T {
        return switch (ty.*) {
            .empty => c.fresh(level),
            .effect => |e| c.effect(e.label, e.lift, e.reply, try c.openEffect(e.tail, level)),
            else => ty,
        };
    }
    fn open(c: *Checker, ty: T, level: i32) anyerror!T {
        return switch (ty.*) {
            .function => |f| c.fun(f.arg, try c.openEffect(f.eff, level), try c.open(f.ret, level)),
            else => ty,
        };
    }
    fn close(c: *Checker, ty: T, level: i32) anyerror!T {
        const t = resolve(ty);
        if (t.* == .function) {
            const f = t.function;
            return c.fun(f.arg, try c.closeEffect(f.arg, f.eff, f.ret, level), try c.close(f.ret, level));
        }
        return ty;
    }
    fn closeEffect(c: *Checker, arg: T, eff: T, ret: T, level: i32) anyerror!T {
        const tail = effectTail(eff);
        if (tail) |v| if (v.level > level and !occurs(v.id, arg) and !occurs(v.id, ret)) return c.removeEffectTail(eff);
        return eff;
    }
    fn removeEffectTail(c: *Checker, input: T) anyerror!T {
        const t = resolve(input);
        return switch (t.*) {
            .variable => c.empty,
            .effect => |e| c.effect(e.label, e.lift, e.reply, try c.removeEffectTail(e.tail)),
            else => t,
        };
    }
    fn unify(c: *Checker, left: T, right: T, level: i32) anyerror!void {
        c.failure = null;
        c.unifyInner(left, right, level) catch |err| {
            if (err == error.TypeError and c.failure != null and c.failure.? == .mismatch) {
                const m = c.failure.?.mismatch;
                if (m.expected.* == .variable and m.given.* == .variable) c.failure = .{ .mismatch = .{ .expected = left, .given = right } };
            }
            return err;
        };
    }
    fn typeError(c: *Checker, reason: Reason) error{TypeError} {
        c.failure = reason;
        return error.TypeError;
    }
    fn unifyInner(c: *Checker, left: T, right: T, level: i32) anyerror!void {
        const a = resolve(left);
        const b = resolve(right);
        if (a == b) return;
        if (a.* == .variable) {
            try c.occursAndLevels(a.variable, b);
            a.variable.link = b;
            return;
        }
        if (b.* == .variable) {
            try c.occursAndLevels(b.variable, a);
            b.variable.link = a;
            return;
        }
        if (a.* == .dynamic or b.* == .dynamic) return;
        if (a.* == .function and b.* == .function) {
            try c.unifyInner(a.function.arg, b.function.arg, level);
            try c.unifyInner(a.function.eff, b.function.eff, level);
            try c.unifyInner(a.function.ret, b.function.ret, level);
            return;
        }
        if (a.* == .list and b.* == .list) return c.unifyInner(a.list, b.list, level);
        if (a.* == .record and b.* == .record) return c.unifyInner(a.record, b.record, level);
        if (a.* == .tagged and b.* == .tagged) return c.unifyInner(a.tagged, b.tagged, level);
        if (a.* == .promise and b.* == .promise) return c.unifyInner(a.promise, b.promise, level);
        if (a.* == .row or b.* == .row) {
            const rowtype = if (a.* == .row) a else b;
            const other = if (a.* == .row) b else a;
            const r = rowtype.row;
            const rewritten = try c.rewriteRow(r.label, other, level, r.tail);
            try c.unifyInner(r.field, rewritten.field, level);
            try c.unifyInner(r.tail, rewritten.tail, level);
            return;
        }
        if (a.* == .effect or b.* == .effect) {
            const efftype = if (a.* == .effect) a else b;
            const other = if (a.* == .effect) b else a;
            const e = efftype.effect;
            const rewritten = try c.rewriteEffect(e.label, other, level, e.tail);
            try c.unifyInner(e.lift, rewritten.lift, level);
            try c.unifyInner(e.reply, rewritten.reply, level);
            try c.unifyInner(e.tail, rewritten.tail, level);
            return;
        }
        if (std.meta.activeTag(a.*) == std.meta.activeTag(b.*)) return;
        return c.typeError(.{ .mismatch = .{ .expected = a, .given = b } });
    }
    fn occursAndLevels(c: *Checker, variable: *Variable, ty: T) anyerror!void {
        const t = resolve(ty);
        switch (t.*) {
            .variable => |v| {
                if (v.id == variable.id) return c.typeError(.recursive);
                v.level = @min(v.level, variable.level);
            },
            .function => |f| {
                try c.occursAndLevels(variable, f.arg);
                try c.occursAndLevels(variable, f.eff);
                try c.occursAndLevels(variable, f.ret);
            },
            .list, .record, .tagged, .promise => |x| try c.occursAndLevels(variable, x),
            .row => |r| {
                try c.occursAndLevels(variable, r.field);
                try c.occursAndLevels(variable, r.tail);
            },
            .effect => |e| {
                try c.occursAndLevels(variable, e.lift);
                try c.occursAndLevels(variable, e.reply);
                try c.occursAndLevels(variable, e.tail);
            },
            else => {},
        }
    }
    fn rewriteRow(c: *Checker, label: []const u8, input: T, level: i32, check: T) anyerror!struct { field: T, tail: T } {
        const t = resolve(input);
        switch (t.*) {
            .empty => return c.typeError(.{ .missing_row = label }),
            .row => |r| {
                if (eq(r.label, label)) return .{ .field = r.field, .tail = r.tail };
                const rewritten = try c.rewriteRow(label, r.tail, level, check);
                return .{ .field = rewritten.field, .tail = try c.row(r.label, r.field, rewritten.tail) };
            },
            .variable => |v| {
                if (check.* == .variable and check.variable.id == v.id) return c.typeError(.{ .same_tail = .{ .expected = t, .given = check } });
                const l = @min(level, v.level);
                const f = try c.fresh(l);
                const tail = try c.fresh(l);
                v.link = try c.row(label, f, tail);
                return .{ .field = f, .tail = tail };
            },
            else => return c.typeError(.{ .mismatch = .{ .expected = try c.row(label, try c.fresh(level), c.empty), .given = t } }),
        }
    }
    fn rewriteEffect(c: *Checker, label: []const u8, input: T, level: i32, check: T) anyerror!struct { lift: T, reply: T, tail: T } {
        const t = resolve(input);
        switch (t.*) {
            .empty => return c.typeError(.{ .missing_row = label }),
            .effect => |e| {
                if (eq(e.label, label)) return .{ .lift = e.lift, .reply = e.reply, .tail = e.tail };
                const rewritten = try c.rewriteEffect(label, e.tail, level, check);
                return .{ .lift = rewritten.lift, .reply = rewritten.reply, .tail = try c.effect(e.label, e.lift, e.reply, rewritten.tail) };
            },
            .variable => |v| {
                if (check.* == .variable and check.variable.id == v.id) return c.typeError(.{ .mismatch = .{ .expected = t, .given = check } });
                const l = @min(level, v.level);
                const lift = try c.fresh(l);
                const reply = try c.fresh(l);
                const tail = try c.fresh(l);
                v.link = try c.effect(label, lift, reply, tail);
                return .{ .lift = lift, .reply = reply, .tail = tail };
            },
            else => return c.typeError(.{ .mismatch = .{ .expected = try c.effect(label, try c.fresh(level), try c.fresh(level), c.empty), .given = t } }),
        }
    }
    fn note(c: *Checker, source: J, ty: T, eff: T, env: ?*const Env, reason: ?Reason, depth: usize, ordinal: usize) !void {
        const id = runtime.field(source, "_native_node");
        const editable_depth = runtime.field(source, "_native_depth");
        const annotated_path = runtime.field(source, "_native_path");
        var path: []const usize = &.{};
        if ((reason != null or c.options.collect_paths) and annotated_path == .array) {
            const copied = try c.allocator.alloc(usize, annotated_path.array.items.len);
            for (annotated_path.array.items, 0..) |part, index| copied[index] = if (part == .integer and part.integer >= 0) @intCast(part.integer) else 0;
            path = copied;
        }
        try c.infos.append(.{
            .node = if (id == .integer and id.integer > 0) @intCast(id.integer) else 0,
            .ty = ty,
            .effect = eff,
            .env = env,
            .reason = reason,
            .depth = if (editable_depth == .integer and editable_depth.integer >= 0) @intCast(editable_depth.integer) else depth,
            .path = path,
            .annotated = annotated_path == .array,
            .ordinal = ordinal,
        });
    }
    fn prim(c: *Checker, source: J, scheme: T, env: ?*const Env, eff: T, level: i32, depth: usize, ordinal: usize) anyerror!Result {
        const t = try c.instantiate(scheme, level);
        const opened = try c.open(t, level);
        try c.note(source, t, c.empty, env, null, depth, ordinal);
        return .{ .ty = opened, .eff = eff };
    }
    fn infer(c: *Checker, source: J, env: ?*const Env, eff: T, level: i32, depth: usize) anyerror!Result {
        const ordinal = c.next_ordinal;
        c.next_ordinal += 1;
        const code = runtime.stringField(source, "0") orelse "z";
        const label = runtime.stringField(source, "l") orelse "";
        if (eq(code, "v")) {
            var cursor = env;
            while (cursor) |entry| : (cursor = entry.next) {
                if (eq(entry.name, label)) {
                    const t = try c.open(try c.instantiate(entry.scheme, level), level);
                    try c.note(source, t, c.empty, env, null, depth, ordinal);
                    return .{ .ty = t, .eff = eff };
                }
            }
            const t = try c.fresh(level);
            try c.note(source, t, c.empty, env, .{ .missing_variable = label }, depth, ordinal);
            return .{ .ty = t, .eff = eff };
        }
        if (eq(code, "z")) {
            const t = try c.fresh(level);
            try c.note(source, t, c.empty, env, .todo, depth, ordinal);
            return .{ .ty = t, .eff = eff };
        }
        if (eq(code, "f")) {
            const arg = try c.fresh(level);
            const local = try c.allocator.create(Env);
            local.* = .{ .name = label, .scheme = arg, .next = env };
            const effect_type = try c.fresh(level + 1);
            const body = try c.infer(runtime.field(source, "b"), local, effect_type, level + 1, depth + 1);
            const t = try c.fun(arg, body.eff, body.ty);
            try c.note(source, try c.close(t, level), c.empty, env, null, depth, ordinal);
            return .{ .ty = t, .eff = eff };
        }
        if (eq(code, "a")) {
            const func = try c.infer(runtime.field(source, "f"), env, eff, level + 1, depth + 1);
            const arg = try c.infer(runtime.field(source, "a"), env, func.eff, level + 1, depth + 1);
            const ret = try c.fresh(level + 1);
            const tested = try c.fresh(level + 1);
            var reason: ?Reason = null;
            c.unify(try c.fun(arg.ty, tested, ret), func.ty, level + 1) catch |err| {
                if (err != error.TypeError) return err;
                reason = c.failure;
            };
            var raised = tested;
            if (effectTail(tested)) |tail| {
                if (tail.level > level - 1) raised = try c.removeEffectTail(tested);
            }
            c.unify(tested, arg.eff, level) catch |err| {
                if (err != error.TypeError) return err;
                if (reason == null) reason = c.failure;
            };
            try c.note(source, try c.close(ret, level), raised, env, reason, depth, ordinal);
            return .{ .ty = ret, .eff = arg.eff };
        }
        if (eq(code, "l")) {
            const val = try c.infer(runtime.field(source, "v"), env, eff, level + 1, depth + 1);
            const scheme = try c.generalize(try c.close(val.ty, level), level);
            const local = try c.allocator.create(Env);
            local.* = .{ .name = label, .scheme = scheme, .next = env };
            const then = try c.infer(runtime.field(source, "t"), local, val.eff, level, depth + 1);
            try c.note(source, then.ty, c.empty, env, null, depth, ordinal);
            return then;
        }
        if (eq(code, "i")) return c.prim(source, c.integer, env, eff, level, depth, ordinal);
        if (eq(code, "s")) return c.prim(source, c.string, env, eff, level, depth, ordinal);
        if (eq(code, "x")) return c.prim(source, c.binary, env, eff, level, depth, ordinal);
        if (eq(code, "ta")) return c.prim(source, try c.list(try c.q(0)), env, eff, level, depth, ordinal);
        if (eq(code, "u")) return c.prim(source, try c.record(c.empty), env, eff, level, depth, ordinal);
        if (eq(code, "b")) {
            if (c.builtin_types.get(label)) |scheme| return c.prim(source, scheme, env, eff, level, depth, ordinal);
            const t = try c.fresh(level);
            try c.note(source, t, c.empty, env, .{ .missing_builtin = label }, depth, ordinal);
            return .{ .ty = t, .eff = eff };
        }
        if (eq(code, "#") or eq(code, ".") or eq(code, "@")) {
            if (c.options.reference_resolver) |resolver| {
                if (try resolver(c.options.reference_context, c.allocator, source)) |module| {
                    // ImportRead infers modules in their own pure context before
                    // bringing the quantified scheme into the live draft.
                    var imported = try Checker.init(c.allocator);
                    _ = try imported.infer(module, null, imported.empty, 1, 0);
                    const scheme = try imported.generalize(imported.infos.items[imported.infos.items.len - 1].ty, 0);
                    return c.prim(source, scheme, env, eff, level, depth, ordinal);
                }
            }
            const t = try c.fresh(level);
            try c.note(source, t, c.empty, env, .{ .missing_reference = source }, depth, ordinal);
            c.infos.items[c.infos.items.len - 1].loading = if (c.options.reference_loading) |loading| loading(c.options.reference_context, source) else !(eq(code, ".") and c.options.reference_resolver != null);
            return .{ .ty = t, .eff = eff };
        }
        const q0 = try c.q(0);
        const q1 = try c.q(1);
        const q2 = try c.q(2);
        const q3 = try c.q(3);
        const scheme: T = if (eq(code, "c")) try c.pure2(q0, try c.list(q0), try c.list(q0)) else if (eq(code, "e")) try c.pure2(q0, try c.record(q1), try c.record(try c.row(label, q0, q1))) else if (eq(code, "o")) try c.pure2(q0, try c.record(try c.row(label, q1, q2)), try c.record(try c.row(label, q0, q2))) else if (eq(code, "g")) try c.pure1(try c.record(try c.row(label, q0, q1)), q0) else if (eq(code, "t")) try c.pure1(q0, try c.tagged(try c.row(label, q0, q1))) else if (eq(code, "n")) try c.pure1(try c.tagged(c.empty), q0) else if (eq(code, "m")) try c.pure2(try c.fun(q0, q1, q2), try c.fun(try c.tagged(q3), q1, q2), try c.fun(try c.tagged(try c.row(label, q0, q3)), q1, q2)) else if (eq(code, "p")) try c.fun(q0, try c.effect(label, q0, q1, c.empty), q1) else if (eq(code, "h")) blk: {
            const kont = try c.fun(q1, q2, q3);
            const handler = try c.fun(q0, c.empty, try c.fun(kont, q2, q3));
            const exec = try c.fun(try c.record(c.empty), try c.effect(label, q0, q1, q2), q3);
            break :blk try c.fun(handler, c.empty, try c.fun(exec, q2, q3));
        } else return error.InvalidIR;
        return c.prim(source, scheme, env, eff, level, depth, ordinal);
    }
    fn environment(c: *Checker, scope: ?*const runtime.Binding) anyerror!?*const Env {
        var bindings = std.ArrayList(*const runtime.Binding).init(c.allocator);
        var cursor = scope;
        while (cursor) |binding| : (cursor = binding.next) try bindings.append(binding);
        var schemes = std.ArrayList(T).init(c.allocator);
        // The oracle allocates type variables newest binding first.
        for (bindings.items) |binding| try schemes.append(try c.runtimeType(binding.value));
        var env: ?*const Env = null;
        var i = bindings.items.len;
        while (i > 0) {
            i -= 1;
            const entry = try c.allocator.create(Env);
            entry.* = .{ .name = bindings.items[i].name, .scheme = schemes.items[i], .next = env };
            env = entry;
        }
        return env;
    }
    fn cloneType(c: *Checker, source: T, copies: *std.AutoHashMap(T, T)) anyerror!T {
        if (copies.get(source)) |copied| return copied;
        const copied = try c.make(.empty);
        try copies.put(source, copied);
        copied.* = switch (source.*) {
            .variable => |v| blk: {
                const variable = try c.allocator.create(Variable);
                variable.* = .{ .id = v.id, .level = v.level, .link = if (v.link) |t| try c.cloneType(t, copies) else null };
                break :blk .{ .variable = variable };
            },
            .function => |f| .{ .function = .{ .arg = try c.cloneType(f.arg, copies), .eff = try c.cloneType(f.eff, copies), .ret = try c.cloneType(f.ret, copies) } },
            .list => |t| .{ .list = try c.cloneType(t, copies) },
            .record => |t| .{ .record = try c.cloneType(t, copies) },
            .tagged => |t| .{ .tagged = try c.cloneType(t, copies) },
            .promise => |t| .{ .promise = try c.cloneType(t, copies) },
            .row => |r| .{ .row = .{ .label = r.label, .field = try c.cloneType(r.field, copies), .tail = try c.cloneType(r.tail, copies) } },
            .effect => |e| .{ .effect = .{ .label = e.label, .lift = try c.cloneType(e.lift, copies), .reply = try c.cloneType(e.reply, copies), .tail = try c.cloneType(e.tail, copies) } },
            else => source.*,
        };
        return copied;
    }
    fn cachedEnvironment(c: *Checker, frozen: FrozenScope) anyerror!?*const Env {
        c.next_id = frozen.next_id;
        var copies = std.AutoHashMap(T, T).init(c.allocator);
        var entries = std.ArrayList(*const Env).init(c.allocator);
        var cursor = frozen.env;
        while (cursor) |entry| : (cursor = entry.next) try entries.append(entry);
        var env: ?*const Env = null;
        var i = entries.items.len;
        while (i > 0) {
            i -= 1;
            const entry = try c.allocator.create(Env);
            entry.* = .{ .name = entries.items[i].name, .scheme = try c.cloneType(entries.items[i].scheme, &copies), .next = env };
            env = entry;
        }
        return env;
    }
    fn runtimeType(c: *Checker, value: runtime.Value) anyerror!T {
        return switch (value) {
            .integer, .javascript_integer => c.integer,
            .string => c.string,
            .binary => c.binary,
            .list => |head| if (head) |cell| c.list(try c.runtimeType(cell.head)) else c.list(try c.fresh(0)),
            .record => |input_fields| blk: {
                const fields = try @import("oracle_order.zig").fields(c.allocator, input_fields);
                const types = try c.allocator.alloc(T, fields.len);
                // dict.to_list is visited forwards for variable allocation.
                for (fields, 0..) |field, index| types[index] = try c.runtimeType(field.value);
                var rows = c.empty;
                var index = fields.len;
                while (index > 0) {
                    index -= 1;
                    rows = try c.row(fields[index].name, types[index], rows);
                }
                break :blk c.record(rows);
            },
            .tagged => |tag| c.tagged(try c.row(tag.label, try c.runtimeType(tag.value), try c.fresh(0))),
            .closure => blk: {
                const source = try @import("capture.zig").capture(c.allocator, value);
                _ = try c.infer(source, null, c.empty, 0, 0);
                // value_to_type generalizes the annotated root, whose effect
                // rows may have been closed independently of the returned type.
                const annotated = c.infos.items[c.infos.items.len - 1].ty;
                break :blk c.generalize(annotated, -1);
            },
            .partial => |p| if (p.kind == .builtin) blk: {
                var f = try c.instantiate(c.builtin_types.get(p.label) orelse return c.fresh(0), 1);
                for (p.args) |arg| {
                    const argtype = try c.instantiate(try c.runtimeType(arg), 1);
                    const ret = try c.fresh(1);
                    const eff = try c.fresh(1);
                    c.unify(try c.fun(argtype, eff, ret), f, 1) catch {};
                    f = ret;
                }
                break :blk c.generalize(f, 1);
            } else c.fresh(0),
            else => c.fresh(0),
        };
    }
    fn typeDoc(c: *Checker, ty: T) anyerror!*const pretty.Doc {
        const p = pretty.Printer{ .allocator = c.allocator };
        const t = resolve(ty);
        return switch (t.*) {
            .variable => |v| p.text(try std.fmt.allocPrint(c.allocator, "{d}", .{v.id})),
            .quantified => |id| p.text(try std.fmt.allocPrint(c.allocator, "{d}", .{id})),
            .integer => p.text("Integer"),
            .string => p.text("String"),
            .binary => p.text("Binary"),
            .never => p.text("Never"),
            .dynamic => p.text("Dynamic"),
            .list => |x| p.wrap("List(", try c.typeDoc(x), ")"),
            .promise => |x| p.wrap("Promise(", try c.typeDoc(x), ")"),
            .record => |rows| p.separated(try c.rowDocs(rows), "{", "}"),
            .tagged => |rows| p.wrap("[", try c.joinDocs(try c.rowDocs(rows), try p.line(" | ", " |")), "]"),
            .empty => p.text("{}"),
            .row => p.wrap("{", try c.joinDocs(try c.rowDocs(t), try p.text("")), "}"),
            .effect => p.wrap("<", try c.effectDoc(t), ">"),
            .function => blk: {
                var args = std.ArrayList(*const pretty.Doc).init(c.allocator);
                var cursor = t;
                while (resolve(cursor).* == .function) {
                    const f = resolve(cursor).function;
                    const arg = try c.typeDoc(f.arg);
                    const eff = resolve(f.eff);
                    try args.append(if (eff.* == .empty) arg else try p.sequence(&.{ arg, try p.line(" ", ""), try p.wrap("<", try c.effectDoc(eff), ">") }));
                    cursor = f.ret;
                }
                break :blk p.sequence(&.{ try p.separated(args.items, "(", ")"), try p.text(" -> "), try c.typeDoc(cursor) });
            },
        };
    }
    fn rowItems(c: *Checker, input: T, record_type: bool) anyerror![]const ScopeItem {
        const t = resolve(input);
        if ((record_type and t.* != .record) or (!record_type and t.* != .tagged)) return &.{};
        var cursor = resolve(if (record_type) t.record else t.tagged);
        var fields = std.ArrayList(ScopeItem).init(c.allocator);
        while (cursor.* == .row) {
            const entry = cursor.row;
            try fields.append(.{ .name = entry.label, .type_text = try c.render(entry.field) });
            cursor = resolve(entry.tail);
        }
        return fields.items;
    }
    fn rowDocs(c: *Checker, rows: T) anyerror![]const *const pretty.Doc {
        const p = pretty.Printer{ .allocator = c.allocator };
        var docs = std.ArrayList(*const pretty.Doc).init(c.allocator);
        var cursor = resolve(rows);
        while (cursor.* == .row) {
            const r = cursor.row;
            try docs.append(try p.sequence(&.{ try p.text(try std.fmt.allocPrint(c.allocator, "{s}: ", .{r.label})), try c.typeDoc(r.field) }));
            cursor = resolve(r.tail);
        }
        if (cursor.* == .variable) try docs.append(try p.text(try std.fmt.allocPrint(c.allocator, "..{d}", .{cursor.variable.id})));
        return docs.items;
    }
    fn joinDocs(c: *Checker, docs: []const *const pretty.Doc, separator: *const pretty.Doc) !*const pretty.Doc {
        const p = pretty.Printer{ .allocator = c.allocator };
        var joined = std.ArrayList(*const pretty.Doc).init(c.allocator);
        for (docs, 0..) |doc, i| {
            if (i > 0) try joined.append(separator);
            try joined.append(doc);
        }
        return p.sequence(joined.items);
    }
    fn effectDoc(c: *Checker, eff: T) anyerror!*const pretty.Doc {
        const p = pretty.Printer{ .allocator = c.allocator };
        var docs = std.ArrayList(*const pretty.Doc).init(c.allocator);
        var cursor = resolve(eff);
        while (cursor.* == .effect) {
            const e = cursor.effect;
            try docs.append(try p.sequence(&.{ try p.text(try std.fmt.allocPrint(c.allocator, "{s}(↑", .{e.label})), try c.typeDoc(e.lift), try p.text(" ↓"), try c.typeDoc(e.reply), try p.text(")") }));
            cursor = resolve(e.tail);
        }
        if (cursor.* == .variable) try docs.append(try p.text(try std.fmt.allocPrint(c.allocator, "..{d}", .{cursor.variable.id})));
        return c.joinDocs(docs.items, try p.line(", ", ","));
    }
    fn render(c: *Checker, ty: T) ![]const u8 {
        const resolved = resolve(ty);
        if (c.rendered_types.get(resolved)) |text| return text;
        const text = try pretty.renderDocument(c.allocator, try c.typeDoc(resolved), 80);
        try c.rendered_types.put(resolved, text);
        return text;
    }
    fn renderScope(c: *Checker, env: ?*const Env) anyerror![]const ScopeItem {
        const key = if (env) |e| @intFromPtr(e) else 0;
        if (c.rendered_scopes.get(key)) |items| return items;
        var items = std.ArrayList(ScopeItem).init(c.allocator);
        var cursor = env;
        var seen = std.StringHashMap(void).init(c.allocator);
        while (cursor) |binding| : (cursor = binding.next) {
            if (seen.contains(binding.name)) continue;
            try seen.put(binding.name, {});
            try items.append(.{ .name = binding.name, .type_text = try c.render(binding.scheme) });
        }
        try c.rendered_scopes.put(key, items.items);
        return items.items;
    }
    fn renderReason(c: *Checker, reason: Reason) anyerror![]const u8 {
        return switch (reason) {
            .todo => "code incomplete",
            .missing_variable => |s| std.fmt.allocPrint(c.allocator, "missing variable '{s}'", .{s}),
            .missing_builtin => |s| std.fmt.allocPrint(c.allocator, "missing variable '!{s}'", .{s}),
            .missing_row => |s| std.fmt.allocPrint(c.allocator, "missing row '{s}'", .{s}),
            .recursive => "Recursive",
            .mismatch => |m| std.fmt.allocPrint(c.allocator, "type mismatch given: {s} expected: {s}", .{ try c.render(m.given), try c.render(m.expected) }),
            .same_tail => |m| std.fmt.allocPrint(c.allocator, "same tail given: {s} expected: {s}", .{ try c.render(m.given), try c.render(m.expected) }),
            .missing_reference => |ir| blk: {
                const code = runtime.stringField(ir, "0") orelse "";
                if (eq(code, ".")) break :blk std.fmt.allocPrint(c.allocator, "missing reference {s}", .{runtime.stringField(ir, "i") orelse ""});
                if (eq(code, "@")) {
                    const name = runtime.stringField(ir, "p") orelse "";
                    const version = runtime.field(ir, "r");
                    if (version == .integer) {
                        if (runtime.stringField(runtime.field(ir, "l"), "/")) |cid| break :blk std.fmt.allocPrint(c.allocator, "missing reference @{s}:{d}:{s}", .{ name, version.integer, cid });
                        break :blk std.fmt.allocPrint(c.allocator, "missing reference @{s}:{d}", .{ name, version.integer });
                    }
                    break :blk std.fmt.allocPrint(c.allocator, "missing reference @{s}", .{name});
                }
                break :blk std.fmt.allocPrint(c.allocator, "missing reference #{s}", .{runtime.stringField(runtime.field(ir, "l"), "/") orelse ""});
            },
        };
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn resolve(ty: T) T {
    var t = ty;
    while (t.* == .variable and t.variable.link != null) t = t.variable.link.?;
    return t;
}
fn occurs(id: usize, input: T) bool {
    const t = resolve(input);
    return switch (t.*) {
        .variable => |v| v.id == id,
        .function => |f| occurs(id, f.arg) or occurs(id, f.eff) or occurs(id, f.ret),
        .list, .record, .tagged, .promise => |x| occurs(id, x),
        .row => |r| occurs(id, r.field) or occurs(id, r.tail),
        .effect => |e| occurs(id, e.lift) or occurs(id, e.reply) or occurs(id, e.tail),
        else => false,
    };
}
fn effectTail(input: T) ?*Variable {
    const t = resolve(input);
    return switch (t.*) {
        .variable => |v| v,
        .effect => |e| effectTail(e.tail),
        else => null,
    };
}

pub fn analyze(allocator: A, program: J, scope: ?*const runtime.Binding) anyerror!Analysis {
    return analyzeWithOptions(allocator, program, scope, .{});
}
pub fn analyzeWithOptions(allocator: A, program: J, scope: ?*const runtime.Binding, options: Options) anyerror!Analysis {
    var c = try Checker.init(allocator);
    c.options = options;
    const env = if (options.scope_cache) |cache| try c.cachedEnvironment(try cache.get(scope)) else try c.environment(scope);
    var i: usize = 0;
    c.infos.clearRetainingCapacity();
    const effects = try std.json.parseFromSlice(J, allocator, @embedFile("computer_types.json"), .{});
    var eff = c.empty;
    i = effects.value.array.items.len;
    while (i > 0) {
        i -= 1;
        const e = effects.value.array.items[i].array.items;
        var lift = try c.decode(e[1]);
        if (options.native_effects and eq(e[0].string, "Hash")) {
            const unit = try c.record(c.empty);
            lift = try c.record(try c.row("algorithm", try c.tagged(try c.row("SHA256", unit, try c.row("SHA1", unit, c.empty))), try c.row("bytes", c.binary, c.empty)));
        }
        eff = try c.effect(e[0].string, lift, try c.decode(e[2]), eff);
    }
    if (options.native_effects) {
        // GitQuery transports different record schemas for each action. Its
        // JSON boundary validates values at runtime; do not claim a static
        // record schema for that foreign data channel.
        const dynamic = try c.make(.dynamic);
        const result_dynamic = try c.tagged(try c.row("Ok", dynamic, try c.row("Error", c.string, c.empty)));
        const result_binary = try c.tagged(try c.row("Ok", c.binary, try c.row("Error", c.string, c.empty)));
        eff = try c.effect("GitQuery", dynamic, result_dynamic, try c.effect("Inflate", c.binary, result_binary, eff));
    }
    _ = try c.infer(program, env, eff, 0, 0);
    const root_type = c.infos.items[c.infos.items.len - 1].ty;
    var analysis = Analysis{ .info = std.AutoHashMap(usize, Info).init(allocator), .error_count = 0, .loading_count = 0, .root_type = try c.render(root_type) };
    var error_paths = std.ArrayList([]const usize).init(allocator);
    var path_info = std.ArrayList(PathInfo).init(allocator);
    for (c.infos.items) |raw| {
        if (raw.reason) |r| {
            if (!(r == .todo and raw.depth < 2)) try error_paths.append(raw.path);
            if (r == .missing_reference and raw.loading) analysis.loading_count += 1 else if (!(r == .todo and raw.depth < 2)) analysis.error_count += 1;
        }
        if (raw.node == 0 and !(options.collect_paths and raw.annotated)) continue;
        const info = Info{
            .type_text = try c.render(raw.ty),
            .problem = if (raw.reason) |r| try c.renderReason(r) else null,
            .effect_text = if (options.collect_effects) try pretty.renderDocument(allocator, try c.effectDoc(raw.effect), 80) else "",
            .scope = if (options.collect_scope) try c.renderScope(raw.env) else &.{},
            .loading = raw.loading,
            .fields = if (options.collect_scope) try c.rowItems(raw.ty, true) else &.{},
            .variants = if (options.collect_scope) try c.rowItems(raw.ty, false) else &.{},
        };
        if (raw.node != 0) try analysis.info.put(raw.node, info);
        if (options.collect_paths and raw.annotated) try path_info.append(.{ .path = raw.path, .info = info, .ordinal = raw.ordinal });
    }
    analysis.error_paths = error_paths.items;
    std.mem.sort(PathInfo, path_info.items, {}, struct {
        fn before(_: void, left: PathInfo, right: PathInfo) bool {
            return left.ordinal < right.ordinal;
        }
    }.before);
    analysis.path_info = path_info.items;
    return analysis;
}

test "contextual inference resolves identity application and retains errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parser = @import("parser.zig");
    const result = try analyze(a, try parser.parse(a, "let f = (x) -> { x } f(42)"), null);
    try std.testing.expectEqualStrings("Integer", result.root_type);
    try std.testing.expectEqual(@as(usize, 0), result.error_count);
    const bad = try analyze(a, try parser.parse(a, "!int_add(1, \"a\")"), null);
    try std.testing.expectEqual(@as(usize, 1), bad.error_count);
    const polymorphic = try analyze(a, try parser.parse(a, "let identity = (x) -> { x } {a: identity(1), b: identity(\"x\")}"), null);
    try std.testing.expectEqualStrings("{a: Integer, b: String}", polymorphic.root_type);
}

test "annotation lookup uses preorder and retains primitive nodes without IDs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parser = @import("parser.zig");
    var program = try parser.parse(a, "!int_add(1, 2)");
    const Mark = struct {
        fn all(allocator: A, value: *J) anyerror!void {
            if (value.* != .object) return;
            var it = value.object.iterator();
            while (it.next()) |entry| try all(allocator, entry.value_ptr);
            if (runtime.stringField(value.*, "0") != null) try value.object.put("_native_path", .{ .array = std.ArrayList(J).init(allocator) });
        }
    };
    try Mark.all(a, &program);
    var function = &program.object.getPtr("f").?.object.getPtr("f").?.*;
    var path = std.ArrayList(J).init(a);
    try path.append(.{ .integer = 7 });
    try function.object.put("_native_path", .{ .array = path });
    const analysis = try analyzeWithOptions(a, program, null, .{ .collect_paths = true });
    try std.testing.expectEqual(@as(usize, 0), analysis.info.count());
    try std.testing.expectEqualStrings("Integer", analysis.infoAtPath(&.{}).?.type_text);
    try std.testing.expectEqualStrings("(Integer, Integer) -> Integer", analysis.infoAtPath(&.{7}).?.type_text);
    try std.testing.expect(analysis.infoAtPath(&.{ 1, 0 }) == null);
}

test "frozen scope contexts are independent across successive drafts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var cache = ScopeCache.init(a);
    var engine = runtime.Engine.init(a);
    const parser = @import("parser.zig");
    try engine.bind("identity", try engine.eval(try parser.parse(a, "(x) -> { x }")));
    for ([_][]const u8{ "identity(1)", "identity(\"a\")", "identity(2)", "let z = identity([]) identity(3)" }) |source| {
        const program = try parser.parse(a, source);
        const uncached = try analyze(a, program, engine.scope);
        const cached = try analyzeWithOptions(a, program, engine.scope, .{ .scope_cache = &cache });
        try std.testing.expectEqualStrings(uncached.root_type, cached.root_type);
        try std.testing.expectEqual(uncached.error_count, cached.error_count);
    }
}

test "native capabilities are explicit and keep the oracle profile closed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parser = @import("parser.zig");
    const query = try parser.parseExpression(a, "perform GitQuery({repo: \".\", action: \"head\"})");
    try std.testing.expect((try analyze(a, query, null)).error_count > 0);
    const native = try analyzeWithOptions(a, query, null, .{ .native_effects = true });
    try std.testing.expectEqual(@as(usize, 0), native.error_count);
    try std.testing.expect(std.mem.indexOf(u8, native.root_type, "Dynamic") != null);
    const mixed = try parser.parseExpression(a, "let _ = perform GitQuery({repo: \".\", action: \"head\"}) let _ = perform GitQuery({repo: \".\", action: \"history\", limit: 2}) {}");
    try std.testing.expectEqual(@as(usize, 0), (try analyzeWithOptions(a, mixed, null, .{ .native_effects = true })).error_count);
    const hash = try parser.parseExpression(a, "perform Hash({algorithm: SHA1({}), bytes: !string_to_binary(\"x\")})");
    try std.testing.expect((try analyze(a, hash, null)).error_count > 0);
    try std.testing.expectEqual(@as(usize, 0), (try analyzeWithOptions(a, hash, null, .{ .native_effects = true })).error_count);
    const unknown = try parser.parseExpression(a, "perform UnknownCapability({})");
    try std.testing.expect((try analyzeWithOptions(a, unknown, null, .{ .native_effects = true })).error_count > 0);
}
