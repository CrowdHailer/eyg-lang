//! Native structural EYG editor and styled terminal buffer.
//! The adapter deliberately exposes cells, rather than stripping ANSI: callers
//! can compare the actual terminal contract with a pinned reference runtime.
const std = @import("std");
const parser = @import("parser.zig");
const interpreter = @import("interpreter.zig");
const unicode = @import("unicode.zig");
const platform = @import("platform.zig");
const inference = @import("inference.zig");
const sandbox = @import("sandbox.zig");
const async_git = @import("async_git.zig");
const hub = @import("hub.zig");
const async_hub = @import("async_hub.zig");
const patterns = @import("tui_patterns.zig");
const source_loader = @import("source.zig");
const effect_cast = @import("effect_cast.zig");
const Allocator = std.mem.Allocator;
const J = std.json.Value;
const Error = anyerror;

pub const Color = union(enum) { default, indexed: u8, rgb: [3]u8 };
pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    modifiers: u16 = 0,
    underline_color: Color = .default,
};
pub const Cell = struct {
    symbol: []const u8 = " ",
    width: u8 = 1,
    style: Style = .{},
};
const CellContext = struct {
    pub fn hash(_: CellContext, cell: Cell) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(cell.symbol);
        std.hash.autoHash(&hasher, cell.width);
        std.hash.autoHash(&hasher, cell.style);
        return hasher.final();
    }
    pub fn eql(_: CellContext, left: Cell, right: Cell) bool {
        return left.width == right.width and std.mem.eql(u8, left.symbol, right.symbol) and std.meta.eql(left.style, right.style);
    }
};
pub const Buffer = struct {
    allocator: Allocator,
    width: usize,
    height: usize,
    cells: []Cell,

    pub fn init(a: Allocator, width: usize, height: usize) !Buffer {
        const cells = try a.alloc(Cell, try std.math.mul(usize, width, height));
        @memset(cells, Cell{});
        return .{ .allocator = a, .width = width, .height = height, .cells = cells };
    }
    pub fn deinit(self: Buffer) void {
        self.allocator.free(self.cells);
    }
    fn set(self: *Buffer, x: usize, y: usize, symbol: []const u8, width: u8, style: Style) void {
        if (x >= self.width or y >= self.height) return;
        self.cells[y * self.width + x] = .{ .symbol = symbol, .width = width, .style = style };
        if (width == 2 and x + 1 < self.width) self.cells[y * self.width + x + 1] = .{ .symbol = " ", .width = 0, .style = style };
    }
    fn text(self: *Buffer, x: usize, y: usize, value: []const u8, style: Style, maximum: usize) void {
        if (y >= self.height or x >= self.width) return;
        var at = x;
        var pos: usize = 0;
        const limit = @min(self.width, x +| maximum);
        while (pos < value.len and at < limit) {
            const g = grapheme(value, pos);
            if (g.width == 0) {
                pos = g.end;
                continue;
            }
            if (at + g.width > limit) break;
            self.set(at, y, value[pos..g.end], g.width, style);
            at += g.width;
            pos = g.end;
        }
    }
    /// Returned symbols are owned by a; buffers and analysis caches may be reset.
    pub fn json(self: Buffer, a: Allocator) !J {
        var cells = std.ArrayList(J).init(a);
        try cells.ensureTotalCapacity(self.cells.len);
        // Most terminal cells are identical blanks. Share immutable JSON cell
        // objects within this frame instead of allocating a map for each cell.
        var interned = std.HashMap(Cell, J, CellContext, 80).init(a);
        defer interned.deinit();
        for (self.cells) |cell| {
            if (interned.get(cell)) |encoded| {
                try cells.append(encoded);
                continue;
            }
            const encoded = try object(a, &.{
                .{ "symbol", .{ .string = try a.dupe(u8, cell.symbol) } },
                .{ "width", jint(cell.width) },
                .{ "fg", try colorJson(a, cell.style.fg) },
                .{ "bg", try colorJson(a, cell.style.bg) },
                .{ "modifiers", jint(cell.style.modifiers) },
                .{ "sub_modifiers", jint(0) },
                .{ "underline_color", try colorJson(a, cell.style.underline_color) },
                .{ "link", .{ .string = "" } },
            });
            try interned.put(cell, encoded);
            try cells.append(encoded);
        }
        return object(a, &.{ .{ "width", jint(self.width) }, .{ "height", jint(self.height) }, .{ "cells", .{ .array = cells } } });
    }
    pub fn ansi(self: Buffer, a: Allocator) ![]u8 {
        var out = std.ArrayList(u8).init(a);
        const w = out.writer();
        try w.writeAll("\x1b[?2026h\x1b[2J");
        for (0..self.height) |y| {
            try w.print("\x1b[{};1H", .{y + 1});
            var current: ?Style = null;
            for (self.cells[y * self.width .. (y + 1) * self.width]) |cell| {
                if (cell.width == 0) continue;
                if (current == null or !std.meta.eql(current.?, cell.style)) {
                    try w.writeAll("\x1b[0m");
                    try ansiColor(w, cell.style.fg, 38);
                    try ansiColor(w, cell.style.bg, 48);
                    const bits = [_]u16{ 1, 2, 4, 8, 16, 32, 64 };
                    const codes = [_]u8{ 1, 2, 3, 4, 5, 7, 9 };
                    for (bits, codes) |bit, code| if (cell.style.modifiers & bit != 0) {
                        try w.print("\x1b[{}m", .{code});
                    };
                    switch (cell.style.underline_color) {
                        .rgb => |rgb| try w.print("\x1b[58:2::{}:{}:{}m", .{ rgb[0], rgb[1], rgb[2] }),
                        .indexed => |i| try w.print("\x1b[58:5:{}m", .{i}),
                        .default => {},
                    }
                    current = cell.style;
                }
                try writeAnsiSymbol(w, cell.symbol);
            }
        }
        try w.writeAll("\x1b[0m\x1b[?2026l");
        return out.toOwnedSlice();
    }
};
fn ansiColor(w: anytype, color: Color, code: u8) !void {
    switch (color) {
        .default => {},
        .indexed => |n| if (n < 8) {
            try w.print("\x1b[{}m", .{@as(u16, code) - 8 + n});
        } else if (n < 16) {
            try w.print("\x1b[{}m", .{@as(u16, code) + 52 + n - 8});
        } else {
            try w.print("\x1b[{};5;{}m", .{ code, n });
        },
        .rgb => |rgb| try w.print("\x1b[{};2;{};{};{}m", .{ code, rgb[0], rgb[1], rgb[2] }),
    }
}
fn colorJson(a: Allocator, c: Color) !J {
    return switch (c) {
        .default => .null,
        .indexed => |n| jint(n),
        .rgb => |rgb| blk: {
            var arr = std.ArrayList(J).init(a);
            for (rgb) |n| try arr.append(jint(n));
            break :blk .{ .array = arr };
        },
    };
}
fn jint(n: anytype) J {
    return .{ .integer = @intCast(n) };
}
fn object(a: Allocator, pairs: []const struct { []const u8, J }) !J {
    var map = std.json.ObjectMap.init(a);
    for (pairs) |p| try map.put(p[0], p[1]);
    return .{ .object = map };
}
fn field(j: J, key: []const u8) J {
    return if (j == .object) j.object.get(key) orelse .null else .null;
}
fn str(j: J) []const u8 {
    return if (j == .string) j.string else "";
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

const Kind = enum { vacant, integer, string, binary, variable, builtin, perform, handle, tag, reference, list, record, call, function, block, select, case, label, parameter, binding, field, branch };
const Node = struct {
    kind: Kind,
    text: []const u8 = "",
    number: i64 = 0,
    wide_number: ?f64 = null,
    children: std.ArrayList(*Node),
    parent: ?*Node = null,
    open: bool = true,
    spread: bool = false,
    reference_ir: J = .null,
    destructured: bool = false,
    fn create(a: Allocator, kind: Kind, text: []const u8) !*Node {
        const n = try a.create(Node);
        n.* = .{ .kind = kind, .text = try a.dupe(u8, text), .children = std.ArrayList(*Node).init(a) };
        return n;
    }
    fn add(n: *Node, child: *Node) !void {
        child.parent = n;
        try n.children.append(child);
    }
    fn isExpression(n: *Node) bool {
        return switch (n.kind) {
            .label, .parameter, .binding, .field, .branch => false,
            else => true,
        };
    }
    fn contains(n: *Node, child: *Node) bool {
        var p: ?*Node = child;
        while (p) |v| {
            if (v == n) return true;
            p = v.parent;
        }
        return false;
    }
};
const Snapshot = struct { root: *Node, selected: *Node };
const EffectRecord = struct { label: []const u8, lift: []const u8, reply: []const u8 };
const RenderCache = struct { width: usize, arena: std.heap.ArenaAllocator, text: []const u8 };
const History = struct { root: *Node, selected: *Node, result: ?[]const u8 = null, value: ?interpreter.Value = null, failure: bool = false, aborted: bool = false, code: bool = false, effects: bool = false, occured: []const EffectRecord = &.{}, render_cache: ?RenderCache = null };
const Mode = enum { navigating, input, picker, history, running };
const InputKind = enum { integer, string, variable, builtin, function, record, tag, select, perform, handle, assign, assign_before, overwrite, label, reference, release, import, match, reply, extend_field_before, extend_field_after, extend_branch_before, extend_branch_after, extend_parameter_before, extend_parameter_after, extend_pattern_before, extend_pattern_after };
const Choice = struct { name: []const u8, hint: []const u8 };
const Span = struct { text: []const u8, style: Style = .{} };
const Line = std.ArrayList(Span);
const Lines = std.ArrayList(Line);

pub const Tui = struct {
    allocator: Allocator,
    root: *Node,
    selected: *Node,
    mode: Mode = .navigating,
    input_kind: InputKind = .integer,
    input_value: []const u8 = "",
    input_cursor: usize = 0,
    choices: []const Choice = &.{},
    choice_selected: usize = 0,
    message: ?[]const u8 = null,
    quit: bool = false,
    history_selected: usize = 0,
    history: std.ArrayList(History),
    undo: std.ArrayList(Snapshot),
    redo: std.ArrayList(Snapshot),
    engine: interpreter.Engine,
    scratch: ?Allocator = null,
    host: platform.Host,
    pending_effects: std.ArrayList(EffectRecord),
    pending_index: usize = 0,
    pending_scope: ?*const interpreter.Binding = null,
    pending_lift: ?interpreter.Value = null,
    pending_exit: ?[]const u8 = null,
    last_value: ?interpreter.Value = null,
    analysis_errors: usize = 0,
    analysis_loading: usize = 0,
    files: J = .null,
    sandboxed: bool = false,
    scope_cache: inference.ScopeCache,
    sandbox_world: ?sandbox.Handler = null,
    analysis_arena: ?std.heap.ArenaAllocator = null,
    cached_analysis: ?inference.Analysis = null,
    analysis_hash: u64 = 0,
    git_worker: ?*async_git.Worker = null,
    retired_workers: std.ArrayList(*async_git.Worker),
    active_engine: ?*interpreter.Engine = null,
    import_stack: std.ArrayList(*interpreter.Engine),
    vm_paused: bool = false,
    package_fixtures: J = .null,
    hub_worker: ?*async_hub.Worker = null,
    hub_waiting: ?J = null,
    hub_attempted: std.StringHashMap(void),
    extension_header: bool = false,
    assign_before_target: ?*Node = null,
    assign_before_anchor: ?*Node = null,

    pub fn init(a: Allocator) Tui {
        const n = Node.create(a, .vacant, "") catch @panic("out of memory");
        return .{ .allocator = a, .root = n, .selected = n, .history = std.ArrayList(History).init(a), .undo = std.ArrayList(Snapshot).init(a), .redo = std.ArrayList(Snapshot).init(a), .engine = interpreter.Engine.init(a), .host = platform.Host.init(a), .pending_effects = std.ArrayList(EffectRecord).init(a), .scope_cache = inference.ScopeCache.init(a), .retired_workers = std.ArrayList(*async_git.Worker).init(a), .import_stack = std.ArrayList(*interpreter.Engine).init(a), .hub_attempted = std.StringHashMap(void).init(a) };
    }
    fn packages(self: *Tui) !*hub.Cache {
        if (self.host.hub_cache == null) {
            if (self.sandboxed) {
                self.host.hub_cache = try hub.Cache.init(self.allocator, "https://eyg.test");
                if (self.package_fixtures == .object) try self.host.hub_cache.?.ingestPackages(self.package_fixtures) else self.host.hub_cache.?.pulled = true;
            } else _ = try self.host.packages();
        }
        return &self.host.hub_cache.?;
    }
    pub fn startHub(self: *Tui) !void {
        if (self.sandboxed) return;
        const cache = try self.packages();
        if (self.hub_worker == null and !cache.pulled) self.hub_worker = try async_hub.Worker.start(cache, null);
    }
    fn referenceDescription(self: *Tui, n: *Node) ![]const u8 {
        const ir = n.reference_ir;
        if (eq(str(field(ir, "0")), "@") and field(ir, "r") == .integer and field(field(ir, "l"), "/") == .string) return std.fmt.allocPrint(self.temp(), "@{s}:{d}:{s}", .{ str(field(ir, "p")), field(ir, "r").integer, str(field(field(ir, "l"), "/")) });
        return n.text;
    }
    fn referenceLoading(context: ?*anyopaque, reference: J) bool {
        const self: *Tui = @ptrCast(@alignCast(context.?));
        if (self.sandboxed or eq(str(field(reference, "0")), ".")) return false;
        const cache = self.packages() catch return false;
        if (!cache.pulled) return true;
        const cid = (self.cachedCID(reference) catch return false) orelse return false;
        if (cache.modules.contains(cid)) return false;
        if (self.hub_worker != null) return true;
        const key = self.referenceKey(reference) catch return false;
        return !self.hub_attempted.contains(key);
    }
    fn effectChoices(self: *Tui) ![]const Choice {
        if (self.sandboxed) return &effect_choices;
        const choices = try self.allocator.alloc(Choice, effect_choices.len + 2);
        @memcpy(choices[0..effect_choices.len], &effect_choices);
        for (choices[0..effect_choices.len]) |*choice| if (eq(choice.name, "Hash")) {
            choice.hint = "{algorithm: [SHA1: {} | SHA256: {}], bytes: Binary} : Binary";
        };
        choices[effect_choices.len] = .{ .name = "GitQuery", .hint = "Dynamic : [Ok: Dynamic | Error: String]" };
        choices[effect_choices.len + 1] = .{ .name = "Inflate", .hint = "Binary : [Ok: Binary | Error: String]" };
        return choices;
    }
    fn releaseChoices(self: *Tui) !void {
        const entries = try (try self.packages()).packageList(self.allocator);
        const choices = try self.allocator.alloc(Choice, entries.len);
        for (entries, choices) |entry, *choice| choice.* = .{ .name = entry.name, .hint = try std.fmt.allocPrint(self.allocator, "{d}", .{entry.version}) };
        self.choices = choices;
    }
    fn cachedCID(self: *Tui, reference: J) !?[]const u8 {
        const cache = try self.packages();
        const pulled = cache.pulled;
        const refresh = cache.refresh_on_miss;
        cache.pulled = true;
        cache.refresh_on_miss = false;
        defer {
            cache.pulled = pulled;
            cache.refresh_on_miss = refresh;
        }
        return cache.referenceCID(reference) catch null;
    }
    fn cachedModule(self: *Tui, reference: J) !?J {
        const cid = try self.cachedCID(reference) orelse return null;
        const cache = try self.packages();
        return if (cache.modules.get(cid)) |module| module.source else null;
    }
    fn referenceKey(self: *Tui, reference: J) ![]const u8 {
        return std.json.stringifyAlloc(self.allocator, try hub.canonicalTree(self.allocator, reference), .{});
    }
    fn queueReference(self: *Tui, reference: J) !void {
        if (self.sandboxed or self.hub_worker != null) return;
        const key = try self.referenceKey(reference);
        if (self.hub_attempted.contains(key)) return;
        try self.hub_attempted.put(key, {});
        self.hub_worker = try async_hub.Worker.start(try self.packages(), reference);
    }
    fn prepareHub(self: *Tui) Error!void {
        if (self.sandboxed or self.hub_worker != null) return;
        if (self.hub_waiting) |reference| {
            try self.queueReference(reference);
            return;
        }
        try self.prepareNode(self.root);
    }
    fn prepareNode(self: *Tui, n: *Node) Error!void {
        if (self.hub_worker != null) return;
        if (n.kind == .reference) {
            const reference = try self.toIR(n);
            if (!eq(str(field(reference, "0")), ".") and try self.cachedModule(reference) == null) try self.queueReference(reference);
        }
        for (n.children.items) |child| try self.prepareNode(child);
    }
    fn pollHub(self: *Tui) Error!bool {
        const worker = self.hub_worker orelse return false;
        if (!worker.ready()) return false;
        self.hub_worker = null;
        defer worker.destroy();
        try worker.merge(try self.packages());
        self.cached_analysis = null;
        if (self.mode == .picker and self.input_kind == .release) try self.releaseChoices();
        if (self.hub_waiting) |reference| {
            if (try self.cachedModule(reference) == null and worker.reference == null) {
                try self.queueReference(reference);
                return true;
            }
            self.hub_waiting = null;
            const active = self.active_engine orelse &self.engine;
            const value = active.continueRun() catch |err| {
                try self.runError(err);
                return true;
            };
            try self.resumeParents(value);
        } else try self.prepareHub();
        return true;
    }
    fn remoteReference(self: *Tui, engine: *interpreter.Engine, reference: J) Error!interpreter.Value {
        const cache = try self.packages();
        const program = try self.cachedModule(reference) orelse {
            if (!self.sandboxed) {
                const key = try self.referenceKey(reference);
                if (self.hub_worker != null or !self.hub_attempted.contains(key)) {
                    self.hub_waiting = reference;
                    try self.queueReference(reference);
                    return error.TuiHub;
                }
            }
            engine.failure = .{ .undefined_reference = reference };
            return error.Runtime;
        };
        if (self.sandboxed) return cache.resolve(engine, reference);
        const cid = try self.cachedCID(reference) orelse unreachable;
        if (cache.modules.get(cid)) |module| if (module.value) |value| return value;
        const child = try self.allocator.create(interpreter.Engine);
        child.* = interpreter.Engine.init(self.allocator);
        child.time_budget_ns = 1_000_000;
        child.inspection_meta = try source_loader.content(self.allocator, cid);
        child.reference_handler = hubReference;
        child.reference_context = self;
        try self.import_stack.append(engine);
        self.active_engine = child;
        const value = child.eval(program) catch |err| {
            if (err == error.Yield or err == error.TuiHub) return err;
            _ = self.import_stack.pop();
            self.active_engine = engine;
            engine.failure = child.failure;
            return err;
        };
        _ = self.import_stack.pop();
        self.active_engine = engine;
        try cache.modules.put(cid, .{ .source = program, .value = value });
        return value;
    }
    fn hubReference(context: ?*anyopaque, engine: *interpreter.Engine, reference: J) Error!interpreter.Value {
        const self: *Tui = @ptrCast(@alignCast(context.?));
        const code = str(field(reference, "0"));
        if (eq(code, "#") or (eq(code, "@") and field(reference, "l") != .null)) return self.remoteReference(engine, reference);
        engine.failure = .{ .undefined_reference = reference };
        return error.Runtime;
    }
    pub fn hasPendingWork(self: *const Tui) bool {
        return self.vm_paused or self.git_worker != null or self.retired_workers.items.len > 0 or self.hub_worker != null or self.hub_waiting != null;
    }
    pub fn shutdown(self: *Tui) void {
        if (self.hub_worker) |worker| worker.destroy();
        self.hub_worker = null;
        self.hub_waiting = null;
        if (self.analysis_arena) |*arena| arena.deinit();
        self.analysis_arena = null;
        self.cached_analysis = null;
        for (self.history.items) |*entry| if (entry.render_cache) |*cache| {
            cache.arena.deinit();
            entry.render_cache = null;
        };
        if (self.git_worker) |job| job.destroy();
        self.git_worker = null;
        for (self.retired_workers.items) |job| job.destroy();
        self.retired_workers.clearRetainingCapacity();
    }
    /// Transfer a finished worker result into session storage before releasing
    /// the worker arena, then resume the interpreter on the UI thread.
    pub fn pollWork(self: *Tui) Error!bool {
        if (try self.pollHub()) return true;
        var i: usize = 0;
        while (i < self.retired_workers.items.len) {
            const job = self.retired_workers.items[i];
            if (job.ready()) {
                job.destroy();
                _ = self.retired_workers.swapRemove(i);
            } else i += 1;
        }
        if (self.vm_paused) {
            const active = self.active_engine orelse &self.engine;
            const value = active.continueRun() catch |err| {
                if (err == error.Yield) return false;
                self.vm_paused = false;
                try self.runError(err);
                return true;
            };
            self.vm_paused = false;
            try self.resumeParents(value);
            return true;
        }
        const job = self.git_worker orelse return false;
        if (!job.ready()) return false;
        self.git_worker = null;
        defer job.destroy();
        const value = switch (job.response) {
            .success => |response| blk: {
                const bytes = try std.json.stringifyAlloc(self.allocator, response, .{});
                const owned = (try std.json.parseFromSlice(J, self.allocator, bytes, .{ .allocate = .alloc_always })).value;
                break :blk try self.engine.tag("Ok", try self.engine.fromPlainJson(owned));
            },
            .failure => |err| try self.engine.tag("Error", .{ .string = @errorName(err) }),
            .pending => unreachable,
        };
        try self.pending_effects.append(.{ .label = "GitQuery", .lift = try self.engine.inspect(self.pending_lift.?), .reply = try self.engine.inspect(value) });
        self.mode = .navigating;
        try self.resumeActive(value);
        return true;
    }
    pub fn event(self: *Tui, ev: J) Error!void {
        defer if (!self.sandboxed and !self.quit) self.prepareHub() catch {};
        self.message = null;
        const key = str(field(ev, "key"));
        if (eq(key, "ctrl+q")) {
            self.quit = true;
            return;
        }
        if (field(ev, "paste") == .string) {
            const text = field(ev, "paste").string;
            if (self.mode == .input or self.mode == .picker) {
                try self.pasteInput(text);
                if (self.mode == .picker and self.input_kind == .import) try self.refreshImportChoices();
                return;
            }
            if (self.mode == .history or self.mode == .running) return;
            if (!self.selected.isExpression()) {
                self.message = "Select an expression to paste into";
                return;
            }
            const ir = self.parseSource(text) catch {
                self.message = try parser.diagnostic(self.allocator, text);
                return;
            };
            const n = try self.fromIR(ir);
            try self.save();
            self.replace(self.selected, n);
            self.selected = n;
            return;
        }
        if (key.len == 0) return;
        switch (self.mode) {
            .history => {
                if (eq(key, "up")) self.history_selected = @min(self.history_selected + 1, self.history.items.len - 1) else if (eq(key, "down")) {
                    if (self.history_selected == 0) self.mode = .navigating else self.history_selected -= 1;
                } else if (eq(key, "esc")) {
                    self.mode = .navigating;
                    for (self.history.items) |*h| {
                        h.code = false;
                        h.effects = false;
                    }
                } else if (eq(key, "k")) self.history.items[self.history_selected].code = !self.history.items[self.history_selected].code else if (eq(key, "K")) self.history.items[self.history_selected].effects = !self.history.items[self.history_selected].effects else if (eq(key, "enter")) {
                    const h = self.history.items[self.history_selected];
                    const copy = try self.cloneSnapshot(h.root, h.selected);
                    self.root = copy.root;
                    self.selected = copy.selected;
                    self.mode = .navigating;
                }
                return;
            },
            .input, .picker => {
                try self.inputKey(key);
                if (self.mode == .picker and self.input_kind == .import) try self.refreshImportChoices();
                return;
            },
            .running => {
                if (eq(key, "esc")) {
                    if (self.git_worker) |job| {
                        job.cancelled = true;
                        try self.retired_workers.append(job);
                        self.git_worker = null;
                    }
                    self.engine.scope = self.pending_scope;
                    try self.finish("Cancelled", false, true);
                }
                return;
            },
            .navigating => {},
        }
        if (eq(key, "esc")) return;
        if (eq(key, "up") and self.root.kind == .vacant and self.history.items.len > 0) {
            self.mode = .history;
            self.history_selected = 0;
            return;
        }
        if (eq(key, "right") or eq(key, "left") or eq(key, "up") or eq(key, "down") or eq(key, "a") or eq(key, " ")) {
            try self.navigate(key);
            return;
        }
        if (eq(key, "enter")) {
            try self.run();
            return;
        }
        if (eq(key, "y")) {
            self.message = "Copy is not supported";
            return;
        }
        if (eq(key, "Y")) {
            self.message = "Use your terminal's native paste shortcut to paste";
            return;
        }
        if (eq(key, "z") or eq(key, "Z")) {
            const from = if (eq(key, "z")) &self.undo else &self.redo;
            const to = if (eq(key, "z")) &self.redo else &self.undo;
            if (from.items.len == 0) {
                try self.fail(if (eq(key, "z")) "undo" else "redo");
                return;
            }
            try to.append(try self.cloneSnapshot(self.root, self.selected));
            const snapshot = from.pop().?;
            self.root = snapshot.root;
            self.selected = snapshot.selected;
            return;
        }
        if (eq(key, "i")) {
            if (self.selected.kind == .binding or self.selected.destructured) {
                try self.fail("insert");
                return;
            }
            if (self.selected.kind == .string) try self.openInput(.string, self.selected.text, true) else if (!self.selected.isExpression() or self.selected.kind == .variable or self.selected.kind == .tag or self.selected.kind == .builtin or self.selected.kind == .perform or self.selected.kind == .handle or self.selected.kind == .select) try self.openInput(.label, editableText(self.selected), true) else try self.fail("insert");
            return;
        }
        if (eq(key, "k")) {
            if (self.selected.kind == .block) self.selected.open = !self.selected.open else {
                var at = self.selected;
                var toggled = false;
                while (at.parent) |parent| {
                    if (parent.kind == .binding and parent.children.items[0].contains(self.selected) and parent.children.items[1].kind == .block) {
                        parent.children.items[1].open = !parent.children.items[1].open;
                        toggled = true;
                        break;
                    }
                    at = parent;
                }
                if (self.selected.kind == .binding and self.selected.children.items[1].kind == .block) {
                    self.selected.children.items[1].open = !self.selected.children.items[1].open;
                    toggled = true;
                }
                if (!toggled) try self.fail("toggle");
            }
            return;
        }
        if (eq(key, "d")) {
            try self.delete();
            return;
        }
        if (key.len != 1 or std.mem.indexOfScalar(u8, "wEeRrtiopasdfghjkLl@#qZzxcCbnmv<>", key[0]) == null) {
            self.message = try std.fmt.allocPrint(self.allocator, "No action bound for key '{s}'", .{key});
            return;
        }
        if (eq(key, "<") or eq(key, ">")) {
            try self.extend(eq(key, "<"));
            return;
        }
        if (eq(key, "x")) {
            try self.spread();
            return;
        }
        if (eq(key, "E")) {
            self.prepareAssignment();
            try self.openInput(.assign_before, "", true);
            return;
        }
        if (!self.selected.isExpression()) {
            if (eq(key, "q")) {
                self.message = "Select an expression to import into";
                return;
            }
            try self.fail(actionName(key));
            return;
        }
        if (eq(key, "n")) {
            try self.openInput(.integer, if (self.selected.kind == .integer) try self.integerText(self.selected) else "0", false);
            return;
        }
        if (eq(key, "s")) {
            try self.openInput(.string, if (self.selected.kind == .string) self.selected.text else "", false);
            return;
        }
        if (eq(key, "f")) {
            try self.openInput(.function, "", true);
            return;
        }
        if (eq(key, "v")) {
            try self.openInput(.variable, "", true);
            if (try self.forwardInfo()) |info| self.choices = try self.toChoices(info.scope);
            return;
        }
        if (eq(key, "j")) {
            try self.openInput(.builtin, "", true);
            self.choices = &builtin_choices;
            return;
        }
        if (eq(key, "r") or eq(key, "o") or eq(key, "t") or eq(key, "g") or eq(key, "p") or eq(key, "h") or eq(key, "e") or eq(key, "E") or eq(key, "m")) {
            const kind: InputKind = if (eq(key, "r")) .record else if (eq(key, "o")) .overwrite else if (eq(key, "t")) .tag else if (eq(key, "g")) .select else if (eq(key, "p")) .perform else if (eq(key, "h")) .handle else if (eq(key, "e")) .assign else if (eq(key, "E")) .assign_before else .match;
            if (try self.pickerInfo()) |info| {
                if (kind == .record and info.fields.len > 0) {
                    try self.recordFields(info.fields);
                    return;
                }
                if (kind == .match and info.variants.len > 0) {
                    try self.matchVariants(info.variants);
                    return;
                }
                try self.openInput(kind, "", true);
                if (kind == .select or kind == .overwrite) self.choices = try self.toChoices(info.fields) else if (kind == .tag or kind == .match) self.choices = try self.toChoices(info.variants);
            } else try self.openInput(kind, "", true);
            if (kind == .perform or kind == .handle) self.choices = try self.effectChoices();
            return;
        }
        if (eq(key, "#")) {
            try self.openInput(.reference, "", false);
            return;
        }
        if (eq(key, "@")) {
            try self.openInput(.release, "", true);
            try self.releaseChoices();
            return;
        }
        if (eq(key, "q")) {
            try self.openInput(.import, "", true);
            try self.refreshImportChoices();
            return;
        }
        if (eq(key, "d")) {
            try self.delete();
            return;
        }
        if (eq(key, "L") or eq(key, "R") or eq(key, "b")) {
            try self.save();
            const n = try Node.create(self.allocator, if (eq(key, "L")) .list else if (eq(key, "R")) .record else .binary, "");
            self.replace(self.selected, n);
            self.selected = n;
            return;
        }
        if (eq(key, "l")) {
            try self.wrap(.list);
            return;
        }
        if (eq(key, "c") or eq(key, "C") or eq(key, "w")) {
            try self.call(key);
            return;
        }
        self.message = try std.fmt.allocPrint(self.allocator, "No action bound for key '{s}'", .{key});
    }
    fn fail(self: *Tui, name: []const u8) !void {
        self.message = try std.fmt.allocPrint(self.allocator, "Action {s} not possible at this position", .{name});
    }
    fn cloneSnapshot(self: *Tui, root: *Node, selected: *Node) Error!Snapshot {
        var focus: ?*Node = null;
        const copy = try self.cloneNode(root, selected, &focus);
        return .{ .root = copy, .selected = focus orelse copy };
    }
    fn cloneNode(self: *Tui, n: *Node, selected: *Node, focus: *?*Node) Error!*Node {
        const copy = try Node.create(self.allocator, n.kind, n.text);
        copy.number = n.number;
        copy.wide_number = n.wide_number;
        copy.open = n.open;
        copy.spread = n.spread;
        copy.reference_ir = n.reference_ir;
        copy.destructured = n.destructured;
        if (n == selected) focus.* = copy;
        for (n.children.items) |c| try copy.add(try self.cloneNode(c, selected, focus));
        return copy;
    }
    fn save(self: *Tui) !void {
        try self.undo.append(try self.cloneSnapshot(self.root, self.selected));
        self.redo.clearRetainingCapacity();
    }
    fn replace(self: *Tui, old: *Node, new: *Node) void {
        if (old.parent) |p| {
            for (p.children.items) |*c| if (c.* == old) {
                c.* = new;
                new.parent = p;
                return;
            };
        } else {
            self.root = new;
            new.parent = null;
        }
    }
    fn wrap(self: *Tui, kind: Kind) !void {
        try self.save();
        const old = self.selected;
        const n = try Node.create(self.allocator, kind, "");
        self.replace(old, n);
        try n.add(old);
    }
    fn openInput(self: *Tui, kind: InputKind, value: []const u8, picker: bool) !void {
        self.mode = if (picker) .picker else .input;
        self.input_kind = kind;
        self.input_value = value;
        self.input_cursor = cellWidth(value);
        self.choice_selected = 0;
        self.choices = &.{};
    }
    fn pasteInput(self: *Tui, text: []const u8) !void {
        var clean = std.ArrayList(u8).init(self.allocator);
        for (text) |c| if (c != '\r') try clean.append(if (c == '\n') ' ' else c);
        var at: usize = 0;
        while (at < clean.items.len and cellWidth(self.input_value) < 256) {
            const end = unicode.graphemeEnd(clean.items, at);
            try self.insertInput(clean.items[at..end]);
            at = end;
        }
    }
    fn insertInput(self: *Tui, text: []const u8) !void {
        if (cellWidth(self.input_value) >= 256) return;
        const at = byteAtWidth(self.input_value, self.input_cursor);
        self.input_value = try std.mem.concat(self.allocator, u8, &.{ self.input_value[0..at], text, self.input_value[at..] });
        self.input_cursor += cellWidth(text);
        self.choice_selected = 0;
    }
    fn inputKey(self: *Tui, key: []const u8) Error!void {
        const previous_value = self.input_value;
        if (eq(key, "esc")) {
            if (self.input_kind == .reply) {
                try self.reply(true);
                return;
            }
            self.mode = .navigating;
            return;
        }
        if (eq(key, "enter")) {
            try self.submit();
            return;
        }
        if (self.mode == .picker and eq(key, "tab")) {
            const c = try self.completion();
            self.input_value = c;
            self.input_cursor = cellWidth(c);
            if (!eq(previous_value, c)) self.choice_selected = 0;
            return;
        }
        if (self.mode == .picker and (eq(key, "up") or eq(key, "down"))) {
            const items_ = try self.matches();
            if (eq(key, "up")) self.choice_selected -|= 1 else if (items_.len > 0) self.choice_selected = @min(self.choice_selected + 1, items_.len - 1);
            return;
        }
        const edit_key = if (std.mem.startsWith(u8, key, "shift+") and std.mem.indexOf(u8, key, "ctrl+") == null and std.mem.indexOf(u8, key, "alt+") == null) key[6..] else key;
        if (eq(key, "ctrl+a") or eq(edit_key, "home")) self.input_cursor = 0 else if (eq(key, "ctrl+e") or eq(edit_key, "end")) self.input_cursor = cellWidth(self.input_value) else if (eq(key, "ctrl+u")) {
            self.input_value = "";
            self.input_cursor = 0;
        } else if (eq(key, "ctrl+k")) self.input_value = self.input_value[0..byteAtWidth(self.input_value, self.input_cursor)] else if (eq(edit_key, "left")) {
            if (self.input_cursor > 0) self.input_cursor = cellWidth(self.input_value[0..byteAtWidth(self.input_value, self.input_cursor - 1)]);
        } else if (eq(edit_key, "right")) {
            self.moveInputRight();
        } else if (eq(edit_key, "backspace")) {
            try self.backspaceInput();
        } else if (eq(edit_key, "delete")) {
            const before = self.input_cursor;
            self.moveInputRight();
            if (before != self.input_cursor) try self.backspaceInput();
        } else if (edit_key.len > 0 and std.mem.indexOf(u8, edit_key, "ctrl+") == null and std.mem.indexOf(u8, edit_key, "alt+") == null and grapheme(edit_key, 0).end == edit_key.len) try self.insertInput(edit_key);
        if (!eq(previous_value, self.input_value)) self.choice_selected = 0;
    }
    fn moveInputRight(self: *Tui) void {
        if (self.input_cursor >= cellWidth(self.input_value)) return;
        const at = byteAtWidth(self.input_value, self.input_cursor);
        self.input_cursor += grapheme(self.input_value, at).width;
    }
    fn backspaceInput(self: *Tui) !void {
        if (self.input_cursor == 0) return;
        const before = byteAtWidth(self.input_value, self.input_cursor - 1);
        const after = byteAtWidth(self.input_value, self.input_cursor);
        const prefix = self.input_value[0..before];
        self.input_value = try std.mem.concat(self.allocator, u8, &.{ prefix, self.input_value[after..] });
        self.input_cursor = cellWidth(prefix);
    }
    fn matches(self: *Tui) ![]const Choice {
        var out = std.ArrayList(Choice).init(self.temp());
        const query = try unicode.changeCase(self.temp(), self.input_value, false);
        for (self.choices) |c| if (std.mem.startsWith(u8, try unicode.changeCase(self.temp(), c.name, false), query)) try out.append(c);
        return out.toOwnedSlice();
    }
    fn completion(self: *Tui) ![]const u8 {
        const matches_ = try self.matches();
        if (matches_.len == 0) return self.input_value;
        const chosen = matches_[@min(self.choice_selected, matches_.len - 1)].name;
        var shared = chosen;
        for (matches_) |c| shared = try commonPrefix(self.temp(), shared, c.name);
        const length = graphemeCount(self.input_value);
        if (graphemeCount(shared) > length) return shared;
        const branch = chosen[0..byteAtGrapheme(chosen, length + 1)];
        const query = try unicode.changeCase(self.temp(), branch, false);
        shared = chosen;
        for (matches_) |c| if (std.mem.startsWith(u8, try unicode.changeCase(self.temp(), c.name, false), query)) {
            shared = try commonPrefix(self.temp(), shared, c.name);
        };
        return shared;
    }
    fn pickerInfo(self: *Tui) !?inference.Info {
        const analysis = try inference.analyzeWithOptions(self.allocator, try self.toIR(self.root), self.engine.scope, .{ .reference_resolver = resolveReference, .reference_context = self, .scope_cache = &self.scope_cache, .reference_loading = referenceLoading, .native_effects = !self.sandboxed, .collect_paths = true });
        return analysis.infoAtPath(try projectionPath(self.allocator, self.selected));
    }
    fn forwardInfo(self: *Tui) !?inference.Info {
        const desired = try projectionPath(self.allocator, self.selected);
        std.mem.reverse(usize, desired);
        const analysis = try inference.analyzeWithOptions(self.allocator, try self.toIR(self.root), self.engine.scope, .{ .reference_resolver = resolveReference, .reference_context = self, .scope_cache = &self.scope_cache, .reference_loading = referenceLoading, .native_effects = !self.sandboxed, .collect_paths = true });
        return analysis.infoAtPath(desired);
    }
    fn toChoices(self: *Tui, items: []const inference.ScopeItem) ![]Choice {
        const choices = try self.allocator.alloc(Choice, items.len);
        for (items, choices) |item, *choice| choice.* = .{ .name = item.name, .hint = item.type_text };
        return choices;
    }
    fn recordFields(self: *Tui, fields: []const inference.ScopeItem) Error!void {
        try self.save();
        const old = self.selected;
        const record = try Node.create(self.allocator, .record, "");
        self.replace(old, record);
        for (fields, 0..) |field_, i| {
            const f = try Node.create(self.allocator, .field, "");
            try f.add(try Node.create(self.allocator, .label, field_.name));
            try f.add(if (i == 0) old else try Node.create(self.allocator, .vacant, ""));
            try record.add(f);
        }
    }
    fn matchVariants(self: *Tui, variants: []const inference.ScopeItem) Error!void {
        try self.save();
        const old = self.selected;
        const n = try Node.create(self.allocator, .case, "");
        self.replace(old, n);
        try n.add(old);
        for (variants, 0..) |variant, i| {
            const br = try Node.create(self.allocator, .branch, "");
            try br.add(try Node.create(self.allocator, .label, variant.name));
            const f = try Node.create(self.allocator, .function, "");
            try f.add(try Node.create(self.allocator, .parameter, "_"));
            const hole = try Node.create(self.allocator, .vacant, "");
            try f.add(hole);
            try br.add(f);
            try n.add(br);
            if (i == 0) self.selected = hole;
        }
    }
    fn integerText(self: *Tui, n: *Node) ![]const u8 {
        return if (n.wide_number) |wide| interpreter.numberText(self.temp(), wide) else interpreter.integerText(self.temp(), n.number);
    }
    fn validReference(self: *Tui, text: []const u8) !bool {
        const source = if (std.mem.startsWith(u8, text, "#")) text else try std.mem.concat(self.temp(), u8, &.{ "#", text });
        const ir = parser.parseExpression(self.temp(), source) catch return false;
        return eq(str(field(ir, "0")), "#");
    }
    fn submit(self: *Tui) Error!void {
        if (self.input_kind == .reply) {
            try self.reply(false);
            return;
        }
        if (isExtension(self.input_kind)) {
            try self.submitExtension();
            return;
        }
        const old = if (self.input_kind == .assign_before and self.assign_before_target != null) self.assign_before_target.? else self.selected;
        const text = if (self.input_kind == .import) std.mem.trim(u8, self.input_value, " \t\r\n") else self.input_value;
        if (self.input_kind == .import and (text.len == 0 or text[text.len - 1] == '/')) {
            self.message = "Choose a file to import";
            return;
        }
        if (self.input_kind == .integer) {
            const number = parseEditorNumber(text) catch return;
            try self.save();
            const n = try Node.create(self.allocator, .integer, "");
            switch (interpreter.numberValue(number)) {
                .integer => |i| n.number = i,
                .javascript_integer => |f| n.wide_number = f,
                else => unreachable,
            }
            self.replace(old, n);
            self.selected = n;
        } else if (self.input_kind == .release) {
            const cache = try self.packages();
            const entry = cache.latest.get(text) orelse {
                self.message = "Choose a published package";
                return;
            };
            const ir = try object(self.allocator, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = entry.name } }, .{ "r", jint(entry.version) }, .{ "l", try object(self.allocator, &.{.{ "/", .{ .string = entry.cid } }}) } });
            try self.save();
            const n = try self.fromIR(ir);
            self.replace(old, n);
            self.selected = n;
            self.mode = .navigating;
            return;
        } else if (self.input_kind == .reference) {
            const cid = if (std.mem.startsWith(u8, text, "#")) text[1..] else text;
            if (!try self.validReference(text)) return;
            try self.save();
            const n = try Node.create(self.allocator, .reference, try std.mem.concat(self.allocator, u8, &.{ "#", cid }));
            self.replace(old, n);
            self.selected = n;
        } else {
            try self.save();
            switch (self.input_kind) {
                .string, .variable, .builtin, .label, .import => {
                    if (self.input_kind == .label) {
                        switch (old.kind) {
                            .select => old.children.items[1].text = text,
                            .binding, .field, .branch => old.children.items[0].text = text,
                            else => old.text = text,
                        }
                    } else {
                        const n = try Node.create(self.allocator, switch (self.input_kind) {
                            .string => .string,
                            .builtin => .builtin,
                            .import => .reference,
                            else => .variable,
                        }, if (self.input_kind == .import) try std.fmt.allocPrint(self.allocator, "import {s}", .{try quoted(self.allocator, text)}) else text);
                        self.replace(old, n);
                        self.selected = n;
                    }
                },
                .function => {
                    const p = try Node.create(self.allocator, .parameter, text);
                    if (old.kind == .function) {
                        try old.children.insert(0, p);
                        p.parent = old;
                    } else if (old.parent != null and old.parent.?.kind == .function and old.parent.?.children.items[old.parent.?.children.items.len - 1] == old) {
                        const f = old.parent.?;
                        try f.children.insert(f.children.items.len - 1, p);
                        p.parent = f;
                    } else {
                        const n = try Node.create(self.allocator, .function, "");
                        self.replace(old, n);
                        try n.add(p);
                        try n.add(old);
                    }
                },
                .record, .overwrite => record_: {
                    if (self.input_kind == .overwrite and old.kind == .record and !old.spread and old.children.items.len > 0) {
                        const hole = try Node.create(self.allocator, .vacant, "");
                        try old.add(hole);
                        old.spread = true;
                        self.selected = hole;
                        break :record_;
                    }
                    const n = try Node.create(self.allocator, .record, "");
                    const f = try Node.create(self.allocator, .field, "");
                    try f.add(try Node.create(self.allocator, .label, text));
                    self.replace(old, n);
                    if (self.input_kind == .overwrite) {
                        const hole = try Node.create(self.allocator, .vacant, "");
                        try f.add(hole);
                        try n.add(f);
                        try n.add(if (old.kind == .vacant or (old.kind == .record and old.children.items.len == 0)) try Node.create(self.allocator, .vacant, "") else old);
                        n.spread = true;
                        self.selected = hole;
                    } else {
                        try f.add(old);
                        try n.add(f);
                    }
                },
                .tag => {
                    const n = try Node.create(self.allocator, .tag, text);
                    if (old.kind == .vacant) {
                        self.replace(old, n);
                        self.selected = n;
                    } else {
                        const c = try Node.create(self.allocator, .call, "");
                        self.replace(old, c);
                        try c.add(n);
                        try c.add(old);
                        self.selected = n;
                    }
                },
                .select => {
                    const n = try Node.create(self.allocator, .select, "");
                    self.replace(old, n);
                    try n.add(old);
                    try n.add(try Node.create(self.allocator, .label, text));
                    self.selected = n;
                },
                .perform => {
                    const n = try Node.create(self.allocator, .call, "");
                    self.replace(old, n);
                    try n.add(try Node.create(self.allocator, .perform, text));
                    try n.add(old);
                },
                .handle => {
                    const n = try Node.create(self.allocator, .call, "");
                    self.replace(old, n);
                    try n.add(try Node.create(self.allocator, .handle, text));
                    const handler = try Node.create(self.allocator, .function, "");
                    try handler.add(try Node.create(self.allocator, .parameter, "value"));
                    try handler.add(try Node.create(self.allocator, .parameter, "resume"));
                    try handler.add(old);
                    try n.add(handler);
                    const run_ = try Node.create(self.allocator, .function, "");
                    try run_.add(try Node.create(self.allocator, .parameter, "_"));
                    try run_.add(try Node.create(self.allocator, .vacant, ""));
                    try n.add(run_);
                },
                .assign, .assign_before => assign_: {
                    const b = try Node.create(self.allocator, .binding, "");
                    try b.add(try Node.create(self.allocator, .label, text));
                    if (self.input_kind == .assign_before and self.assign_before_anchor != null) {
                        const anchor = self.assign_before_anchor.?;
                        const block_ = anchor.parent.?;
                        try b.add(try Node.create(self.allocator, .vacant, ""));
                        try block_.children.insert(nodeIndex(block_, anchor), b);
                        b.parent = block_;
                        self.selected = b;
                        break :assign_;
                    }
                    if (old.parent != null and old.parent.?.kind == .block and old.parent.?.children.items[old.parent.?.children.items.len - 1] == old) {
                        const block_ = old.parent.?;
                        const at = block_.children.items.len - 1;
                        if (self.input_kind == .assign_before or old.kind == .vacant) {
                            const hole = try Node.create(self.allocator, .vacant, "");
                            try b.add(hole);
                            try block_.children.insert(at, b);
                            b.parent = block_;
                            self.selected = hole;
                        } else {
                            try b.add(old);
                            block_.children.items[at] = b;
                            b.parent = block_;
                            const tail = try Node.create(self.allocator, .vacant, "");
                            try block_.add(tail);
                            self.selected = tail;
                        }
                    } else {
                        const block_ = try Node.create(self.allocator, .block, "");
                        self.replace(old, block_);
                        const hole = try Node.create(self.allocator, .vacant, "");
                        if (self.input_kind == .assign_before) {
                            try b.add(hole);
                            try block_.add(b);
                            try block_.add(old);
                            self.selected = hole;
                        } else {
                            try b.add(old);
                            try block_.add(b);
                            try block_.add(hole);
                            self.selected = if (old.kind == .vacant) old else hole;
                        }
                    }
                },
                .match => {
                    const n = try Node.create(self.allocator, .case, "");
                    self.replace(old, n);
                    try n.add(old);
                    const br = try Node.create(self.allocator, .branch, "");
                    try br.add(try Node.create(self.allocator, .label, text));
                    const f = try Node.create(self.allocator, .function, "");
                    try f.add(try Node.create(self.allocator, .parameter, "_"));
                    const hole = try Node.create(self.allocator, .vacant, "");
                    try f.add(hole);
                    try br.add(f);
                    try n.add(br);
                    self.selected = hole;
                },
                else => {},
            }
        }
        self.mode = .navigating;
    }
    fn call(self: *Tui, key: []const u8) Error!void {
        const arity = if (eq(key, "c")) (if (try self.forwardInfo()) |info| typeArity(info.type_text) else 1) else 1;
        try self.save();
        const old = self.selected;
        const n = try Node.create(self.allocator, .call, "");
        const hole = try Node.create(self.allocator, .vacant, "");
        if (eq(key, "C") and old.parent != null and old.parent.?.kind == .call and old.parent.?.children.items[0] == old) {
            const p = old.parent.?;
            try p.children.insert(1, hole);
            hole.parent = p;
            self.selected = hole;
            return;
        }
        if (eq(key, "C") and old.kind == .call) {
            try old.add(hole);
            self.selected = hole;
            return;
        }
        self.replace(old, n);
        if (eq(key, "w")) {
            try n.add(hole);
            try n.add(old);
            self.selected = hole;
        } else {
            try n.add(old);
            try n.add(hole);
            self.selected = hole;
            if (eq(key, "c")) for (1..arity) |_| try n.add(try Node.create(self.allocator, .vacant, ""));
        }
    }
    fn delete(self: *Tui) Error!void {
        const old = self.selected;
        if (old.kind == .vacant and old.parent == null) {
            try self.fail("delete");
            return;
        }
        try self.save();
        if (!old.isExpression()) {
            if (old.parent) |parent| {
                if (parent.kind == .field and parent.parent != null and parent.parent.?.destructured) {
                    const pattern = parent.parent.?;
                    const index = nodeIndex(pattern, parent);
                    const had_next = index + 1 < pattern.children.items.len;
                    const side = nodeIndex(parent, old);
                    _ = pattern.children.orderedRemove(index);
                    self.selected = if (pattern.children.items.len == 0) pattern else pattern.children.items[if (had_next) index else index - 1].children.items[side];
                    return;
                }
                if (old.destructured and old.children.items.len == 0) {
                    old.destructured = false;
                    old.text = "_";
                    return;
                }
                if (old.kind == .parameter and parent.kind == .function) {
                    const count = parent.children.items.len - 1;
                    if (count > 1) {
                        const at = nodeIndex(parent, old);
                        _ = parent.children.orderedRemove(at);
                        self.selected = parent.children.items[@min(at, count - 2)];
                    } else self.selected = parent;
                    return;
                }
                if (old.kind == .label and parent.kind == .field and parent.parent.?.kind == .record) {
                    const record = parent.parent.?;
                    const fields = record.children.items.len - @as(usize, if (record.spread) 1 else 0);
                    if (fields == 1 and record.spread) {
                        self.selected = record;
                        return;
                    }
                    const at = nodeIndex(record, parent);
                    _ = record.children.orderedRemove(at);
                    self.selected = if (fields == 1) record else record.children.items[@min(at, fields - 2)].children.items[0];
                    return;
                }
                if (old.kind == .label and parent.kind == .branch) {
                    const case_ = parent.parent.?;
                    const count = case_.children.items.len - 1 - @as(usize, if (case_.spread) 1 else 0);
                    if (count > 1) {
                        const at = nodeIndex(case_, parent);
                        _ = case_.children.orderedRemove(at);
                        self.selected = case_.children.items[@min(at, count - 1)].children.items[0];
                    } else self.selected = case_;
                    return;
                }
                if (old.kind == .binding and parent.kind == .block) {
                    const count = parent.children.items.len - 1;
                    const at = nodeIndex(parent, old);
                    _ = parent.children.orderedRemove(at);
                    if (count == 1) {
                        const tail = parent.children.items[0];
                        self.replace(parent, tail);
                        self.selected = tail;
                    } else self.selected = parent.children.items[@min(at, count - 2)];
                    return;
                }
                self.selected = if (parent.kind == .field or parent.kind == .branch) parent.parent.? else parent;
            }
            return;
        }
        if (old.kind != .vacant) {
            const hole = try Node.create(self.allocator, .vacant, "");
            self.replace(old, hole);
            self.selected = hole;
            return;
        }
        const parent = old.parent.?;
        const at = nodeIndex(parent, old);
        if (parent.kind == .list) {
            if (parent.spread and at + 1 == parent.children.items.len) parent.spread = false else if (parent.spread and parent.children.items.len == 2) {
                const tail = parent.children.items[1];
                self.replace(parent, tail);
                self.selected = tail;
                return;
            }
            _ = parent.children.orderedRemove(at);
            self.selected = if (parent.children.items.len == 0) parent else parent.children.items[@min(at, parent.children.items.len - 1)];
            return;
        }
        if (parent.kind == .call) {
            if (at == 0 or parent.children.items.len == 2) {
                self.selected = parent;
                return;
            }
            _ = parent.children.orderedRemove(at);
            self.selected = parent.children.items[@min(at, parent.children.items.len - 1)];
            return;
        }
        if (parent.kind == .field and parent.parent.?.kind == .record) {
            const record = parent.parent.?;
            const fields = record.children.items.len - @as(usize, if (record.spread) 1 else 0);
            const index = nodeIndex(record, parent);
            if (fields == 1) {
                const empty = try Node.create(self.allocator, .record, "");
                self.replace(record, empty);
                self.selected = empty;
                return;
            }
            const had_next = index + 1 < fields;
            _ = record.children.orderedRemove(index);
            self.selected = if (had_next) record.children.items[index].children.items[0] else record.children.items[index - 1].children.items[1];
            return;
        }
        if (parent.kind == .case and parent.spread and at + 1 == parent.children.items.len) {
            _ = parent.children.pop();
            parent.spread = false;
            self.selected = if (parent.children.items.len > 1) parent.children.items[parent.children.items.len - 1].children.items[0] else parent.children.items[0];
            return;
        }
        self.selected = parent;
    }
    fn prepareAssignment(self: *Tui) void {
        self.assign_before_target = null;
        self.assign_before_anchor = null;
        var at = self.selected;
        while (at.parent) |parent| {
            if (at.kind == .binding and parent.kind == .block) {
                self.assign_before_anchor = at;
                return;
            }
            if (at.isExpression() and parent.kind == .block and nodeIndex(parent, at) + 1 == parent.children.items.len) {
                self.assign_before_target = at;
                return;
            }
            at = parent;
        }
        self.assign_before_target = at;
    }
    fn branchAnchor(n: *Node) ?*Node {
        if (n.parent) |parent| {
            if (parent.kind == .branch) return parent;
            if (parent.kind == .function and parent.parent != null and parent.parent.?.kind == .branch and nodeIndex(parent, n) + 1 == parent.children.items.len) return parent.parent;
        }
        return null;
    }
    fn extend(self: *Tui, before: bool) Error!void {
        const old = self.selected;
        const p = old.parent;
        if (p != null and ((p.?.kind == .list and !(p.?.spread and nodeIndex(p.?, old) + 1 == p.?.children.items.len and !before)) or (p.?.kind == .call and nodeIndex(p.?, old) > 0))) {
            try self.save();
            const n = try Node.create(self.allocator, .vacant, "");
            const at = nodeIndex(p.?, old) + @as(usize, if (before) 0 else 1);
            try p.?.children.insert(at, n);
            n.parent = p;
            self.selected = n;
            return;
        }
        if (p != null and p.?.kind == .field and p.?.parent != null) {
            const owner = p.?.parent.?;
            if (owner.kind == .record and nodeIndex(p.?, old) == 0) {
                try self.openInput(if (before) .extend_field_before else .extend_field_after, "", true);
                return;
            }
            if (owner.destructured) {
                try self.openInput(if (before) .extend_pattern_before else .extend_pattern_after, "", true);
                return;
            }
        }
        if (old.kind == .parameter and p != null and p.?.kind == .function and !old.destructured) {
            try self.openInput(if (before) .extend_parameter_before else .extend_parameter_after, "", true);
            return;
        }
        if (branchAnchor(old) != null) {
            self.extension_header = old.kind == .label and p != null and p.?.kind == .branch;
            try self.openInput(if (before) .extend_branch_before else .extend_branch_after, "", true);
            return;
        }
        try self.fail(if (before) "insert before" else "insert after");
    }
    fn submitExtension(self: *Tui) Error!void {
        try self.save();
        const old = self.selected;
        const before = extensionBefore(self.input_kind);
        const offset: @TypeOf(@as(usize, 0)) = if (before) 0 else 1;
        switch (self.input_kind) {
            .extend_field_before, .extend_field_after => {
                const field_ = old.parent.?;
                const record = field_.parent.?;
                const fresh = try Node.create(self.allocator, .field, "");
                try fresh.add(try Node.create(self.allocator, .label, self.input_value));
                const hole = try Node.create(self.allocator, .vacant, "");
                try fresh.add(hole);
                try record.children.insert(nodeIndex(record, field_) + offset, fresh);
                fresh.parent = record;
                self.selected = hole;
            },
            .extend_pattern_before, .extend_pattern_after => {
                const field_ = old.parent.?;
                const pattern = field_.parent.?;
                const fresh = try Node.create(self.allocator, .field, "");
                try fresh.add(try Node.create(self.allocator, .label, self.input_value));
                const variable = try Node.create(self.allocator, .parameter, self.input_value);
                try fresh.add(variable);
                try pattern.children.insert(nodeIndex(pattern, field_) + offset, fresh);
                fresh.parent = pattern;
                self.selected = variable;
            },
            .extend_parameter_before, .extend_parameter_after => {
                const function_ = old.parent.?;
                const fresh = try Node.create(self.allocator, .parameter, self.input_value);
                try function_.children.insert(nodeIndex(function_, old) + offset, fresh);
                fresh.parent = function_;
                self.selected = fresh;
            },
            .extend_branch_before, .extend_branch_after => {
                const anchor = branchAnchor(old).?;
                const case_ = anchor.parent.?;
                const fresh = try Node.create(self.allocator, .branch, "");
                const label = try Node.create(self.allocator, .label, self.input_value);
                try fresh.add(label);
                const function_ = try Node.create(self.allocator, .function, "");
                if (old.parent != null and old.parent.?.kind == .function) {
                    const prior = old.parent.?;
                    var ignored: ?*Node = null;
                    for (prior.children.items[0 .. prior.children.items.len - 1]) |parameter| try function_.add(try self.cloneNode(parameter, old, &ignored));
                } else try function_.add(try Node.create(self.allocator, .parameter, "_"));
                const hole = try Node.create(self.allocator, .vacant, "");
                try function_.add(hole);
                try fresh.add(function_);
                try case_.children.insert(nodeIndex(case_, anchor) + offset, fresh);
                fresh.parent = case_;
                self.selected = if (self.extension_header) label else hole;
            },
            else => unreachable,
        }
        self.mode = .navigating;
    }
    fn spread(self: *Tui) Error!void {
        const old = self.selected;
        if (old.parent) |parent| {
            if (parent.kind == .list and !parent.spread) {
                try self.save();
                const hole = try Node.create(self.allocator, .vacant, "");
                try parent.add(hole);
                parent.spread = true;
                self.selected = hole;
                return;
            }
        }
        var anchor = branchAnchor(old);
        if (old.kind == .function and old.parent != null and old.parent.?.kind == .branch) anchor = null;
        if (anchor == null and !old.isExpression()) {
            var at = old;
            while (at.parent) |parent| {
                if (parent.kind == .function and parent.parent != null and parent.parent.?.kind == .branch) {
                    anchor = parent.parent;
                    break;
                }
                at = parent;
            }
        }
        if (anchor) |branch| {
            const case_ = branch.parent.?;
            if (!case_.spread) {
                try self.save();
                const function_ = try Node.create(self.allocator, .function, "");
                try function_.add(try Node.create(self.allocator, .parameter, "_"));
                const hole = try Node.create(self.allocator, .vacant, "");
                try function_.add(hole);
                try case_.add(function_);
                case_.spread = true;
                self.selected = hole;
                return;
            }
        }
        try self.fail("spread");
    }
    fn leaf(n: *Node, last: bool) *Node {
        if (n.children.items.len == 0) return n;
        if (n.kind == .block) {
            n.open = true;
            if (!last and n.children.items[0].kind == .binding) return n.children.items[0].children.items[0];
        }
        return leaf(n.children.items[if (last) n.children.items.len - 1 else 0], last);
    }
    fn navigate(self: *Tui, key: []const u8) !void {
        if (eq(key, "a")) {
            if (self.selected.parent) |p| {
                self.selected = if (p.kind == .field or p.kind == .branch) p.parent.? else p;
            } else try self.fail("increase selection");
            return;
        }
        if (eq(key, "up") or eq(key, "down")) {
            var n = self.selected;
            while (n.parent) |p| {
                if (p.kind == .block or p.kind == .case) {
                    const at = nodeIndex(p, n);
                    if (eq(key, "up") and at > (if (p.kind == .case) @as(usize, 1) else 0)) {
                        const target = p.children.items[at - 1];
                        self.selected = if (target.kind == .branch) target.children.items[0] else target;
                        return;
                    }
                    if (eq(key, "down") and at + 1 < p.children.items.len and !(p.kind == .case and at == 0)) {
                        const target = p.children.items[at + 1];
                        self.selected = if (target.kind == .branch) target.children.items[0] else target;
                        return;
                    }
                }
                n = p;
            }
            try self.fail(if (eq(key, "up")) "move up" else "move down");
            return;
        }
        if (eq(key, " ")) {
            var nodes = std.ArrayList(*Node).init(self.allocator);
            try collectLeaves(self.root, &nodes);
            if (nodes.items.len == 0) {
                try self.fail("Jump to vacant");
                return;
            }
            var start: usize = 0;
            for (nodes.items, 0..) |n, i| if (n == self.selected) {
                start = i;
                break;
            };
            for (1..nodes.items.len + 1) |offset| {
                const n = nodes.items[(start + offset) % nodes.items.len];
                if (n.kind == .vacant and n != self.selected) {
                    self.selected = n;
                    var parent = n.parent;
                    while (parent) |ancestor| {
                        if (ancestor.kind == .block) ancestor.open = true;
                        parent = ancestor.parent;
                    }
                    return;
                }
            }
            try self.fail("Jump to vacant");
            return;
        }
        const last = eq(key, "left");
        if (self.selected.kind == .binding) {
            self.selected = self.selected.children.items[0];
            return;
        }
        if (last and self.selected.destructured and self.selected.children.items.len > 0) {
            self.selected = self.selected.children.items[self.selected.children.items.len - 1].children.items[0];
            return;
        }
        if (self.selected.children.items.len > 0) {
            self.selected = leaf(self.selected, last);
            return;
        }
        var n = self.selected;
        while (n.parent) |p| {
            const at = nodeIndex(p, n);
            if (!last and at + 1 < p.children.items.len) {
                // Moving past the final assignment selects the whole block
                // tail; a subsequent move descends into that expression.
                self.selected = if (p.kind == .block and at + 2 == p.children.items.len) p.children.items[at + 1] else leaf(p.children.items[at + 1], false);
                return;
            }
            if (last and at > 0) {
                self.selected = leaf(p.children.items[at - 1], true);
                return;
            }
            n = p;
        }
        self.selected = leaf(self.root, last);
    }
    fn collectLeaves(n: *Node, list: *std.ArrayList(*Node)) Error!void {
        if (n.children.items.len == 0) {
            try list.append(n);
            return;
        }
        for (n.children.items) |c| try collectLeaves(c, list);
    }
    fn patternNode(self: *Tui, kind: Kind, pattern: patterns.Pattern) Error!*Node {
        const n = try Node.create(self.allocator, kind, pattern.label);
        n.destructured = pattern.destructured;
        for (pattern.fields) |field_| {
            const f = try Node.create(self.allocator, .field, "");
            try f.add(try Node.create(self.allocator, .label, field_.name));
            try f.add(try Node.create(self.allocator, .parameter, field_.variable));
            try n.add(f);
        }
        return n;
    }
    fn nodePattern(self: *Tui, n: *Node) !patterns.Pattern {
        const fields_ = try self.temp().alloc(patterns.Field, n.children.items.len);
        for (n.children.items, fields_) |field_, *out| out.* = .{ .name = field_.children.items[0].text, .variable = field_.children.items[1].text };
        return .{ .label = n.text, .fields = fields_, .destructured = n.destructured };
    }
    fn fromIR(self: *Tui, ir: J) Error!*Node {
        const code = str(field(ir, "0"));
        const a = self.allocator;
        if (eq(code, "i")) {
            const n = try Node.create(a, .integer, "");
            const v = field(ir, "v");
            n.number = if (v == .integer) v.integer else 0;
            return n;
        }
        if (eq(code, "s")) return Node.create(a, .string, str(field(ir, "v")));
        if (eq(code, "z")) return Node.create(a, .vacant, "");
        if (eq(code, "x")) return Node.create(a, .binary, try interpreter.decodeBytes(a, field(ir, "v")));
        if (eq(code, "v") or eq(code, "b") or eq(code, "t") or eq(code, "p") or eq(code, "h")) return Node.create(a, if (eq(code, "v")) .variable else if (eq(code, "b")) .builtin else if (eq(code, "t")) .tag else if (eq(code, "p")) .perform else .handle, str(field(ir, "l")));
        if (eq(code, "u")) return Node.create(a, .record, "");
        if (eq(code, "ta")) return Node.create(a, .list, "");
        if (eq(code, "g")) {
            const fn_ = try Node.create(a, .function, "");
            try fn_.add(try Node.create(a, .parameter, "$"));
            const select = try Node.create(a, .select, "");
            try select.add(try Node.create(a, .variable, "$"));
            try select.add(try Node.create(a, .label, str(field(ir, "l"))));
            try fn_.add(select);
            return fn_;
        }
        if (eq(code, "m")) return Node.create(a, .variable, "CASE!!");
        if (eq(code, "n")) return Node.create(a, .variable, "NOCASE!!");
        if (eq(code, "f")) {
            const n = try Node.create(a, .function, "");
            var body = ir;
            while (eq(str(field(body, "0")), "f")) {
                const gathered = try patterns.gather(a, str(field(body, "l")), field(body, "b"));
                try n.add(try self.patternNode(.parameter, gathered.pattern));
                body = gathered.rest;
            }
            try n.add(try self.fromIR(body));
            return n;
        }
        if (eq(code, "l")) {
            const n = try Node.create(a, .block, "");
            var tail = ir;
            while (eq(str(field(tail, "0")), "l")) {
                const b = try Node.create(a, .binding, "");
                const gathered = try patterns.gather(a, str(field(tail, "l")), field(tail, "t"));
                try b.add(try self.patternNode(.label, gathered.pattern));
                try b.add(try self.fromIR(field(tail, "v")));
                try n.add(b);
                tail = gathered.rest;
            }
            try n.add(try self.fromIR(tail));
            return n;
        }
        if (eq(code, "a")) {
            const f = field(ir, "f");
            const arg = field(ir, "a");
            const fcode = str(field(f, "0"));
            if (eq(fcode, "g")) {
                const n = try Node.create(a, .select, "");
                try n.add(try self.fromIR(arg));
                try n.add(try Node.create(a, .label, str(field(f, "l"))));
                return n;
            }
            if (eq(fcode, "a") and eq(str(field(field(f, "f"), "0")), "a") and eq(str(field(field(field(f, "f"), "f"), "0")), "m")) {
                const n = try Node.create(a, .case, "");
                try n.add(try self.fromIR(arg));
                try self.fromCases(n, f);
                return n;
            }
            if (eq(fcode, "a")) {
                const op = field(f, "f");
                const opcode = str(field(op, "0"));
                if (eq(opcode, "m")) {
                    const fn_ = try Node.create(a, .function, "");
                    try fn_.add(try Node.create(a, .parameter, "$"));
                    const cases = try Node.create(a, .case, "");
                    try cases.add(try Node.create(a, .variable, "$"));
                    try self.fromCases(cases, ir);
                    try fn_.add(cases);
                    return fn_;
                }
                if (eq(opcode, "c")) {
                    const n = try Node.create(a, .list, "");
                    var rest = ir;
                    while (eq(str(field(rest, "0")), "a") and eq(str(field(field(rest, "f"), "0")), "a") and eq(str(field(field(field(rest, "f"), "f"), "0")), "c")) {
                        try n.add(try self.fromIR(field(field(rest, "f"), "a")));
                        rest = field(rest, "a");
                    }
                    if (!eq(str(field(rest, "0")), "ta")) {
                        try n.add(try self.fromIR(rest));
                        n.spread = true;
                    }
                    return n;
                }
                if (eq(opcode, "e") or eq(opcode, "o")) {
                    const n = try Node.create(a, .record, "");
                    var rest = ir;
                    while (eq(str(field(rest, "0")), "a") and eq(str(field(field(rest, "f"), "0")), "a")) {
                        const cur = field(field(rest, "f"), "f");
                        if (!eq(str(field(cur, "0")), opcode)) break;
                        const fnode = try Node.create(a, .field, "");
                        try fnode.add(try Node.create(a, .label, str(field(cur, "l"))));
                        try fnode.add(try self.fromIR(field(field(rest, "f"), "a")));
                        try n.add(fnode);
                        rest = field(rest, "a");
                    }
                    if (!eq(str(field(rest, "0")), "u")) {
                        try n.add(if (eq(opcode, "e")) try Node.create(a, .variable, "Record extend") else try self.fromIR(rest));
                        n.spread = true;
                    }
                    return n;
                }
            }
            const fn_ = try self.fromIR(f);
            const argument = try self.fromIR(arg);
            if (fn_.kind == .call) {
                try fn_.add(argument);
                return fn_;
            }
            const n = try Node.create(a, .call, "");
            try n.add(fn_);
            try n.add(argument);
            return n;
        }
        if (eq(code, ".")) {
            const n = try Node.create(a, .reference, try std.fmt.allocPrint(a, "import {s}", .{try quoted(a, str(field(ir, "i")))}));
            n.reference_ir = ir;
            return n;
        }
        if (eq(code, "@")) {
            const version = field(ir, "r");
            const n = try Node.create(a, .reference, if (version == .integer) try std.fmt.allocPrint(a, "@{s}:{d}", .{ str(field(ir, "p")), version.integer }) else try std.mem.concat(a, u8, &.{ "@", str(field(ir, "p")) }));
            n.reference_ir = ir;
            return n;
        }
        if (eq(code, "#")) {
            const loc = field(ir, "l");
            if (loc == .object and field(loc, "/") == .string) {
                const n = try Node.create(a, .reference, try std.mem.concat(a, u8, &.{ "#", field(loc, "/").string }));
                n.reference_ir = ir;
                return n;
            }
            const name = field(ir, "p");
            if (name == .string) return Node.create(a, .reference, try std.mem.concat(a, u8, &.{ "@", name.string }));
            if (loc == .string) return Node.create(a, .reference, if (std.mem.startsWith(u8, loc.string, "./") or std.mem.startsWith(u8, loc.string, "../")) try std.fmt.allocPrint(a, "import {s}", .{try quoted(a, loc.string)}) else try std.mem.concat(a, u8, &.{ "#", loc.string }));
            return Node.create(a, .reference, "#reference");
        }
        return Node.create(a, .variable, try std.mem.concat(a, u8, &.{ "!", code }));
    }
    fn fromCases(self: *Tui, n: *Node, ir: J) Error!void {
        if (eq(str(field(ir, "0")), "n")) return;
        if (eq(str(field(ir, "0")), "a") and eq(str(field(field(ir, "f"), "0")), "a") and eq(str(field(field(field(ir, "f"), "f"), "0")), "m")) {
            const br = try Node.create(self.allocator, .branch, "");
            try br.add(try Node.create(self.allocator, .label, str(field(field(field(ir, "f"), "f"), "l"))));
            try br.add(try self.fromIR(field(field(ir, "f"), "a")));
            try n.add(br);
            try self.fromCases(n, field(ir, "a"));
        } else {
            try n.add(try self.fromIR(ir));
            n.spread = true;
        }
    }
    fn toIR(self: *Tui, n: *Node) Error!J {
        var ir = try self.toIRInner(n);
        if (ir == .object) try ir.object.put("_native_node", jint(@intFromPtr(n)));
        try annotateMetadata(&ir, try nodePath(self.temp(), n), self.temp());
        return ir;
    }
    fn toIRInner(self: *Tui, n: *Node) Error!J {
        const a = self.temp();
        switch (n.kind) {
            .integer => return object(a, &.{ .{ "0", .{ .string = "i" } }, .{ "v", if (n.wide_number) |wide| .{ .float = wide } else jint(n.number) } }),
            .string => return object(a, &.{ .{ "0", .{ .string = "s" } }, .{ "v", .{ .string = n.text } } }),
            .vacant => return irOp(a, "z", ""),
            .variable, .builtin, .tag, .perform, .handle => return irOp(a, switch (n.kind) {
                .variable => "v",
                .builtin => "b",
                .tag => "t",
                .perform => "p",
                else => "h",
            }, n.text),
            .call => {
                var ir = try self.toIR(n.children.items[0]);
                for (n.children.items[1..]) |c| ir = try irApply(a, ir, try self.toIR(c));
                return ir;
            },
            .function => {
                var ir = try self.toIR(n.children.items[n.children.items.len - 1]);
                if (n.children.items.len == 2 and !n.children.items[0].destructured and eq(n.children.items[0].text, "$") and eq(str(field(ir, "0")), "a") and eq(str(field(field(ir, "a"), "0")), "v") and eq(str(field(field(ir, "a"), "l")), "$")) return field(ir, "f");
                var i = n.children.items.len - 1;
                while (i > 0) {
                    i -= 1;
                    const param = n.children.items[i];
                    const lowered = try patterns.lower(a, try self.nodePattern(param), ir, try nodePath(a, param));
                    ir = try object(a, &.{ .{ "0", .{ .string = "f" } }, .{ "l", .{ .string = lowered.label } }, .{ "b", lowered.body } });
                }
                return ir;
            },
            .block => {
                var ir = try self.toIR(n.children.items[n.children.items.len - 1]);
                var i = n.children.items.len - 1;
                while (i > 0) {
                    i -= 1;
                    const b = n.children.items[i];
                    const pattern = b.children.items[0];
                    const lowered = try patterns.lower(a, try self.nodePattern(pattern), ir, try nodePath(a, b));
                    ir = try object(a, &.{ .{ "0", .{ .string = "l" } }, .{ "l", .{ .string = lowered.label } }, .{ "v", try self.toIR(b.children.items[1]) }, .{ "t", lowered.body } });
                    try annotateMetadata(&ir, try nodePath(a, b), a);
                }
                return ir;
            },
            .list => {
                var i = n.children.items.len;
                var ir = try irOp(a, "ta", "");
                try annotateMetadata(&ir, try prependPath(a, n.children.items.len, try nodePath(a, n)), a);
                if (n.spread and i > 0) {
                    i -= 1;
                    ir = try self.toIR(n.children.items[i]);
                }
                while (i > 0) {
                    i -= 1;
                    ir = try irApply(a, try irApply(a, try irOp(a, "c", ""), try self.toIR(n.children.items[i])), ir);
                }
                return ir;
            },
            .record => {
                var i = n.children.items.len;
                var ir = try irOp(a, "u", "");
                if (n.spread and i > 0) {
                    i -= 1;
                    ir = try self.toIR(n.children.items[i]);
                }
                while (i > 0) {
                    i -= 1;
                    const f = n.children.items[i];
                    var extension = try irOp(a, if (n.spread) "o" else "e", f.children.items[0].text);
                    try annotateMetadata(&extension, try nodePath(a, f.children.items[0]), a);
                    ir = try irApply(a, try irApply(a, extension, try self.toIR(f.children.items[1])), ir);
                }
                return ir;
            },
            .case => {
                var i = n.children.items.len;
                var cases = try irOp(a, "n", "");
                try annotateMetadata(&cases, try prependPath(a, n.children.items.len, try nodePath(a, n)), a);
                if (n.spread and i > 1) {
                    i -= 1;
                    cases = try self.toIR(n.children.items[i]);
                }
                while (i > 1) {
                    i -= 1;
                    const br = n.children.items[i];
                    cases = try irApply(a, try irApply(a, try irOp(a, "m", br.children.items[0].text), try self.toIR(br.children.items[1])), cases);
                }
                return irApply(a, cases, try self.toIR(n.children.items[0]));
            },
            .select => {
                var select = try irOp(a, "g", n.children.items[1].text);
                try annotateMetadata(&select, try nodePath(a, n.children.items[1]), a);
                return irApply(a, select, try self.toIR(n.children.items[0]));
            },
            .reference => {
                if (n.reference_ir != .null) {
                    return hub.canonicalTree(a, n.reference_ir);
                }
                return parser.parse(a, n.text);
            },
            .binary => return object(a, &.{ .{ "0", .{ .string = "x" } }, .{ "v", try interpreter.encodeBytes(a, n.text) } }),
            else => return irOp(a, "z", ""),
        }
    }
    fn run(self: *Tui) Error!void {
        if (self.root.kind == .vacant) {
            self.message = "write a program";
            return;
        }
        self.host.attach(&self.engine);
        self.engine.inspection_meta = .{ .literal = "Location(origin: Repl, source: Json)" };
        self.engine.effect_handler = handleEffect;
        self.engine.effect_context = self;
        self.engine.reference_handler = handleReference;
        self.engine.reference_context = self;
        self.pending_effects.clearRetainingCapacity();
        self.active_engine = &self.engine;
        self.import_stack.clearRetainingCapacity();
        self.engine.time_budget_ns = if (self.sandboxed) 0 else 1_000_000;
        self.vm_paused = false;
        self.pending_index = 0;
        self.pending_scope = self.engine.scope;
        self.pending_exit = null;
        self.last_value = null;
        try self.continueRun(null);
    }
    fn continueRun(self: *Tui, resumed: ?interpreter.Value) Error!void {
        var reply_ = resumed;
        const count = if (self.root.kind == .block) self.root.children.items.len else 1;
        while (self.pending_index < count) {
            const n = if (self.root.kind == .block) self.root.children.items[self.pending_index] else self.root;
            if (n.kind == .vacant and self.root.kind == .block) break;
            const value = if (reply_) |v| v else self.engine.evalTrusted(try self.toIR(if (n.kind == .binding) n.children.items[1] else n)) catch |err| {
                try self.runError(err);
                return;
            };
            reply_ = null;
            if (n.kind == .binding) {
                patterns.bind(&self.engine, try self.nodePattern(n.children.items[0]), value) catch |err| {
                    try self.runError(err);
                    return;
                };
            } else self.last_value = value;
            self.pending_index += 1;
        }
        try self.finish(null, false, false);
    }
    fn runError(self: *Tui, err: anyerror) Error!void {
        if (err == error.Yield) {
            self.vm_paused = true;
            self.mode = .running;
            return;
        }
        self.vm_paused = false;
        if (err == error.TuiHub) {
            self.mode = .running;
            return;
        }
        if (err == error.TuiAsync) {
            self.mode = .running;
            return;
        }
        if (err == error.TuiInput) {
            try self.openInput(.reply, "", false);
            return;
        }
        if (self.active_engine) |active| if (active != &self.engine) {
            self.engine.failure = active.failure;
        };
        self.import_stack.clearRetainingCapacity();
        self.active_engine = &self.engine;
        self.engine.scope = self.pending_scope;
        if (err == error.TuiExit) {
            try self.finish(self.pending_exit, false, true);
            return;
        }
        if (err != error.Runtime) return err;
        try self.finish(try self.engine.describe(), true, false);
    }
    fn reply(self: *Tui, cancel: bool) Error!void {
        const value = try self.engine.tag(if (cancel) "Error" else "Ok", if (cancel) .{ .string = "Cancelled" } else .{ .binary = self.input_value });
        try self.pending_effects.append(.{ .label = "StandardIn", .lift = "{}", .reply = try self.engine.inspect(value) });
        self.mode = .navigating;
        try self.resumeActive(value);
    }
    /// A paused imported module retains its own evaluator and the parents
    /// waiting for its value. A reply resumes the innermost evaluator first.
    fn resumeActive(self: *Tui, reply_: interpreter.Value) Error!void {
        const active = self.active_engine orelse &self.engine;
        const value = active.@"resume"(reply_) catch |err| {
            try self.runError(err);
            return;
        };
        try self.resumeParents(value);
    }
    fn resumeParents(self: *Tui, initial: interpreter.Value) Error!void {
        var value = initial;
        while (self.import_stack.pop()) |parent| {
            self.active_engine = parent;
            value = parent.@"resume"(value) catch |err| {
                try self.runError(err);
                return;
            };
        }
        self.active_engine = &self.engine;
        try self.continueRun(value);
    }
    fn importFailure(engine: *interpreter.Engine, message: []const u8) error{Runtime} {
        engine.failure = .{ .unhandled_effect = .{ .label = "Abort", .value = .{ .string = message } } };
        return error.Runtime;
    }
    fn handleReference(context: ?*anyopaque, engine: *interpreter.Engine, ir: J) Error!interpreter.Value {
        const self: *Tui = @ptrCast(@alignCast(context.?));
        if (!eq(str(field(ir, "0")), ".")) return self.remoteReference(engine, ir);
        const path = str(field(ir, "i"));
        const a = self.allocator;
        const origin = engine.origin orelse if (self.sandboxed) "/" else self.host.directory;
        const resolved = try std.fs.path.resolve(a, &.{ if (self.sandboxed) "/" else ".", origin, path });
        const contents = if (self.sandboxed) (try self.world()).readFile(resolved) catch return importFailure(engine, try std.fmt.allocPrint(a, "failed to read module from location: {s}", .{path})) else std.fs.cwd().readFileAlloc(a, resolved, 64 * 1024 * 1024) catch return importFailure(engine, try std.fmt.allocPrint(a, "failed to read module from location: {s}", .{path}));
        const parsed = source_loader.disk(a, contents, resolved) catch return importFailure(engine, try parser.diagnostic(a, contents));
        const child = try a.create(interpreter.Engine);
        child.* = interpreter.Engine.init(a);
        child.origin = std.fs.path.dirname(resolved) orelse origin;
        child.inspection_meta = parsed.meta;
        child.time_budget_ns = if (self.sandboxed) 0 else 1_000_000;
        child.effect_handler = null;
        child.reference_handler = handleReference;
        child.reference_context = self;
        try self.import_stack.append(engine);
        self.active_engine = child;
        const value = child.eval(parsed.program) catch |err| {
            if (err == error.TuiInput or err == error.TuiAsync or err == error.Yield or err == error.TuiHub) return err;
            _ = self.import_stack.pop();
            self.active_engine = engine;
            engine.failure = child.failure;
            return err;
        };
        _ = self.import_stack.pop();
        self.active_engine = engine;
        return value;
    }
    fn handleEffect(context: ?*anyopaque, engine: *interpreter.Engine, label: []const u8, lift: interpreter.Value) Error!interpreter.Value {
        const self: *Tui = @ptrCast(@alignCast(context.?));
        if (self.sandboxed) try effect_cast.validate(engine, label, lift) else try effect_cast.validateNative(engine, label, lift);
        if (!self.sandboxed and eq(label, "GitQuery")) {
            const request = engine.toPlainJson(lift) catch |err| {
                const reply_ = try engine.tag("Error", .{ .string = @errorName(err) });
                try self.recordEffect(engine, label, lift, reply_);
                return reply_;
            };
            self.git_worker = async_git.Worker.start(request) catch |err| {
                const reply_ = try engine.tag("Error", .{ .string = @errorName(err) });
                try self.recordEffect(engine, label, lift, reply_);
                return reply_;
            };
            self.pending_lift = lift;
            return error.TuiAsync;
        }
        if (eq(label, "StandardIn")) {
            self.pending_lift = lift;
            return error.TuiInput;
        }
        if (eq(label, "Exit")) {
            self.pending_exit = try std.fmt.allocPrint(self.allocator, "Exited with status {s}", .{try interpreter.numberText(self.allocator, interpreter.numberFloat(lift).?)});
            return error.TuiExit;
        }
        const value = if (eq(label, "StandardOut") or eq(label, "StandardError")) interpreter.unit() else (if (self.sandboxed) (try self.world()).effect(engine, label, lift) else platform.effect(&self.host, engine, label, lift)) catch |err| {
            if (err == error.UnhandledEffect) {
                engine.failure = .{ .unhandled_effect = .{ .label = label, .value = lift } };
                return error.Runtime;
            }
            return err;
        };
        try self.recordEffect(engine, label, lift, value);
        return value;
    }
    fn recordEffect(self: *Tui, engine: *interpreter.Engine, label: []const u8, lift: interpreter.Value, reply_: interpreter.Value) !void {
        try self.pending_effects.append(.{ .label = label, .lift = try engine.inspect(lift), .reply = try engine.inspect(reply_) });
    }
    fn finish(self: *Tui, result: ?[]const u8, failed: bool, aborted: bool) !void {
        try self.history.insert(0, .{ .root = self.root, .selected = self.selected, .result = result, .value = if (failed or aborted) null else self.last_value, .failure = failed, .aborted = aborted, .occured = try self.allocator.dupe(EffectRecord, self.pending_effects.items) });
        self.import_stack.clearRetainingCapacity();
        self.active_engine = &self.engine;
        self.vm_paused = false;
        self.hub_waiting = null;
        self.root = try Node.create(self.allocator, .vacant, "");
        self.selected = self.root;
        self.mode = .navigating;
        self.undo.clearRetainingCapacity();
        self.redo.clearRetainingCapacity();
    }
    fn temp(self: *Tui) Allocator {
        return self.scratch orelse self.allocator;
    }
    fn analyse(self: *Tui) !void {
        var hash = std.hash.Wyhash.init(0);
        hashNode(&hash, self.root);
        const scope_id: usize = if (self.engine.scope) |scope_| @intFromPtr(scope_) else 0;
        hash.update(std.mem.asBytes(&scope_id));
        const key = hash.final();
        if (self.cached_analysis == null or key != self.analysis_hash) {
            self.cached_analysis = null;
            if (self.analysis_arena == null) self.analysis_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            _ = self.analysis_arena.?.reset(.retain_capacity);
            self.cached_analysis = try inference.analyzeWithOptions(self.analysis_arena.?.allocator(), try self.toIR(self.root), self.engine.scope, .{ .reference_resolver = resolveReference, .reference_context = self, .scope_cache = &self.scope_cache, .collect_scope = false, .collect_effects = false, .reference_loading = referenceLoading, .native_effects = !self.sandboxed, .collect_paths = true });
            self.analysis_hash = key;
        }
        const analysis = &self.cached_analysis.?;
        self.analysis_errors = analysis.error_count;
        self.analysis_loading = analysis.loading_count;
    }
    fn parseSource(self: *Tui, text: []const u8) !J {
        return parseModule(self.allocator, text);
    }
    fn resolveReference(context: ?*anyopaque, a: Allocator, ir: J) Error!?J {
        const self: *Tui = @ptrCast(@alignCast(context.?));
        if (!eq(str(field(ir, "0")), ".")) return self.cachedModule(ir);
        const path = str(field(ir, "i"));
        if (self.sandboxed) {
            const text = (try self.world()).readFile(path) catch return null;
            return (source_loader.disk(a, text, path) catch return null).program;
        }
        const resolved = try std.fs.path.resolve(a, &.{ self.host.directory, path });
        const text = std.fs.cwd().readFileAlloc(a, resolved, 64 * 1024 * 1024) catch return null;
        return (source_loader.disk(a, text, resolved) catch return null).program;
    }
    fn world(self: *Tui) !*sandbox.Handler {
        if (self.sandbox_world == null) self.sandbox_world = try sandbox.Handler.init(self.allocator, self.files);
        return &self.sandbox_world.?;
    }
    fn refreshImportChoices(self: *Tui) !void {
        const slash = std.mem.lastIndexOfScalar(u8, self.input_value, '/');
        const directory = if (slash) |i| self.input_value[0 .. i + 1] else "";
        const hidden = self.input_value.len > directory.len and self.input_value[directory.len] == '.';
        var choices = std.ArrayList(Choice).init(self.allocator);
        if (self.sandboxed) {
            const w = try self.world();
            const absolute = try std.fs.path.resolve(self.allocator, &.{ "/", if (directory.len == 0) "." else directory });
            const prefix = if (eq(absolute, "/")) absolute else try std.mem.concat(self.allocator, u8, &.{ absolute, "/" });
            var it = w.entries.iterator();
            while (it.next()) |entry| {
                const path = entry.key_ptr.*;
                if (!std.mem.startsWith(u8, path, prefix) or path.len <= prefix.len) continue;
                const suffix = path[prefix.len..];
                if (std.mem.indexOfScalar(u8, suffix, '/') != null or (!hidden and suffix[0] == '.')) continue;
                try choices.append(.{ .name = try std.mem.concat(self.allocator, u8, &.{ directory, suffix, if (entry.value_ptr.* == null) "/" else "" }), .hint = if (entry.value_ptr.* == null) "directory" else "file" });
            }
        } else {
            const path = try std.fs.path.resolve(self.allocator, &.{ self.host.directory, if (directory.len == 0) "." else directory });
            if (std.fs.cwd().openDir(path, .{ .iterate = true })) |opened| {
                var dir = opened;
                defer dir.close();
                var it = dir.iterate();
                while (it.next() catch null) |entry| {
                    if (!hidden and entry.name.len > 0 and entry.name[0] == '.') continue;
                    const is_directory = if (dir.statFile(entry.name)) |stat| stat.kind == .directory else |_| false;
                    const name = try std.mem.concat(self.allocator, u8, &.{ directory, entry.name, if (is_directory) "/" else "" });
                    try choices.append(.{ .name = name, .hint = if (is_directory) "directory" else "file" });
                }
            } else |_| {}
        }
        std.mem.sort(Choice, choices.items, {}, struct {
            fn less(_: void, x: Choice, y: Choice) bool {
                const left = if (eq(x.hint, "directory")) x.name[0 .. x.name.len - 1] else x.name;
                const right = if (eq(y.hint, "directory")) y.name[0 .. y.name.len - 1] else y.name;
                return unicode.utf16LessThan(left, right);
            }
        }.less);
        self.choices = try choices.toOwnedSlice();
    }
    fn lineNew(self: *Tui) Line {
        return Line.init(self.temp());
    }
    fn linesNew(self: *Tui) Lines {
        return Lines.init(self.temp());
    }
    fn plainLine(self: *Tui, text: []const u8, style: Style) !Line {
        var l = self.lineNew();
        try l.append(.{ .text = text, .style = style });
        return l;
    }
    fn styleFor(self: *Tui, n: *Node, base: Style, focus: ?*Node, active: bool, err_: bool) Style {
        _ = self;
        var s = base;
        if (err_) {
            s.modifiers |= 8;
            s.underline_color = .{ .rgb = .{ 255, 0, 0 } };
        }
        if (focus != null and focus.?.contains(n)) {
            if (active) {
                s.fg = .default;
                s.bg = .default;
                s.modifiers |= 32;
            } else s.modifiers |= 10;
        }
        return s;
    }
    fn token(self: *Tui, l: *Line, n: *Node, text: []const u8, base: Style, focus: ?*Node, active: bool, err_: bool) !void {
        try l.append(.{ .text = text, .style = self.styleFor(n, base, focus, active, err_) });
    }
    /// The reference editor checks surrounding projection frames with a
    /// reversed path, while standalone expressions use their stored reverse
    /// path. Preserve that observable distinction, including error underlines.
    fn nodeError(self: *Tui, n: *Node, focus: ?*Node) bool {
        if (focus == null or !n.isExpression() or n.kind == .vacant or self.cached_analysis == null) return false;
        const path = renderPath(self.temp(), n, focus) catch return false;
        if (n != focus.? and n.contains(focus.?)) std.mem.reverse(usize, path);
        for (self.cached_analysis.?.error_paths) |candidate| if (std.mem.eql(usize, path, candidate)) return true;
        return false;
    }
    fn renderPattern(self: *Tui, line: *Line, n: *Node, focus: ?*Node, active: bool, err_: bool) !void {
        if (!n.destructured) {
            try self.token(line, n, n.text, .{ .fg = .{ .indexed = 3 } }, focus, active, err_);
            return;
        }
        try self.token(line, n, "{", .{}, focus, active, err_);
        for (n.children.items, 0..) |field_, i| {
            if (i > 0) try self.token(line, n, ", ", .{}, focus, active, err_);
            try self.token(line, field_.children.items[0], field_.children.items[0].text, .{}, focus, active, err_);
            try self.token(line, n, ": ", .{}, focus, active, err_);
            try self.token(line, field_.children.items[1], field_.children.items[1].text, .{ .fg = .{ .indexed = 3 } }, focus, active, err_);
        }
        try self.token(line, n, "}", .{}, focus, active, err_);
    }
    fn renderNode(self: *Tui, n: *Node, focus: ?*Node, active: bool, top: bool, inherited_error: bool) Error!Lines {
        const a = self.temp();
        const err_ = inherited_error or self.nodeError(n, focus);
        var lines = self.linesNew();
        var line = self.lineNew();
        switch (n.kind) {
            .vacant => try self.token(&line, n, "Vacant", .{ .fg = .{ .indexed = 3 }, .modifiers = 1 }, focus, active, inherited_error),
            .integer => try self.token(&line, n, try self.integerText(n), .{ .fg = .{ .indexed = 5 } }, focus, active, err_),
            .string => try self.token(&line, n, try quoted(a, n.text), .{ .fg = .{ .indexed = 2 } }, focus, active, err_),
            .binary => {
                var text = std.ArrayList(u8).init(a);
                try text.appendSlice("<<");
                for (n.text, 0..) |byte, i| {
                    if (i > 0) try text.appendSlice(", ");
                    try text.writer().print("{d}", .{byte});
                }
                try text.appendSlice(">>");
                try self.token(&line, n, try text.toOwnedSlice(), .{ .fg = .{ .indexed = 2 } }, focus, active, err_);
            },
            .variable => try self.token(&line, n, n.text, .{ .fg = .{ .indexed = 3 } }, focus, active, err_),
            .label => try self.token(&line, n, n.text, .{}, focus, active, err_),
            .parameter => try self.token(&line, n, n.text, .{ .fg = .{ .indexed = 3 } }, focus, active, err_),
            .builtin => try self.token(&line, n, try std.mem.concat(a, u8, &.{ "!", n.text }), .{ .fg = .{ .indexed = 2 } }, focus, active, err_),
            .reference => {
                if (std.mem.startsWith(u8, n.text, "import ")) {
                    try self.token(&line, n, "import ", .{ .fg = .{ .indexed = 6 } }, focus, active, err_);
                    try self.token(&line, n, n.text[7..], .{ .fg = .{ .indexed = 2 } }, focus, active, err_);
                } else try self.token(&line, n, n.text, .{ .fg = .{ .indexed = 5 } }, focus, active, err_);
            },
            .tag, .perform, .handle => {
                if (n.kind == .perform or n.kind == .handle) try self.token(&line, n, if (n.kind == .perform) "perform " else "handle ", .{ .fg = .{ .indexed = 6 } }, focus, active, err_);
                try self.token(&line, n, n.text, .{ .fg = .{ .indexed = 12 }, .modifiers = 1 }, focus, active, err_);
            },
            .call => {
                var result = try self.renderNode(n.children.items[0], focus, active, false, err_);
                var args = std.ArrayList(Lines).init(a);
                var preceding_inline = true;
                for (n.children.items[1..], 0..) |arg, i| {
                    const rendered = try self.renderNode(arg, focus, active, false, err_);
                    if (i + 2 < n.children.items.len and rendered.items.len > 1) preceding_inline = false;
                    try args.append(rendered);
                }
                var arguments = self.linesNew();
                line = self.lineNew();
                try self.token(&line, n, "(", .{}, focus, active, err_);
                try arguments.append(line);
                if (preceding_inline) {
                    for (args.items, 0..) |arglines, i| {
                        if (i > 0) try self.token(&arguments.items[arguments.items.len - 1], n, ", ", .{}, focus, active, err_);
                        try joinLines(&arguments, arglines);
                    }
                    try self.token(&arguments.items[arguments.items.len - 1], n, ")", .{}, focus, active, err_);
                } else {
                    // morph keeps the final multiline argument inline when all
                    // earlier arguments are inline. Otherwise every argument
                    // becomes an indented frame, including its trailing comma.
                    for (args.items) |*arglines| {
                        try self.token(&arglines.items[arglines.items.len - 1], n, ",", .{}, focus, active, err_);
                        try self.indent(arglines, n, focus, active);
                        try arguments.appendSlice(arglines.items);
                    }
                    line = self.lineNew();
                    try self.token(&line, n, ")", .{}, focus, active, err_);
                    try arguments.append(line);
                }
                if (result.items.len > 1 and arguments.items.len > 1) {
                    // Joining two multiline frames makes their shared boundary
                    // an inner line of the resulting frame.
                    try result.items[result.items.len - 1].appendSlice(arguments.items[0].items);
                    try result.items[result.items.len - 1].insert(0, .{ .text = "  ", .style = self.styleFor(n, .{}, focus, active, false) });
                    try result.appendSlice(arguments.items[1..]);
                } else try joinLines(&result, arguments);
                return result;
            },
            .select => {
                var result = try self.renderNode(n.children.items[0], focus, active, false, err_);
                try self.token(&result.items[result.items.len - 1], n.children.items[1], ".", .{}, focus, active, err_);
                try self.token(&result.items[result.items.len - 1], n.children.items[1], n.children.items[1].text, .{}, focus, active, err_);
                return result;
            },
            .function => {
                try self.token(&line, n, "(", .{}, focus, active, err_);
                for (n.children.items[0 .. n.children.items.len - 1], 0..) |p, i| {
                    if (i > 0) try self.token(&line, n, ", ", .{}, focus, active, err_);
                    try self.renderPattern(&line, p, focus, active, err_);
                }
                try self.token(&line, n, ") -> ", .{}, focus, active, err_);
                try lines.append(line);
                const body = try self.renderNode(n.children.items[n.children.items.len - 1], focus, active, false, err_);
                try joinLines(&lines, body);
                return lines;
            },
            .block => {
                if (!top and !n.open) {
                    try self.token(&line, n, "{ ... }", .{}, focus, active, err_);
                } else {
                    if (!top) {
                        try self.token(&line, n, "{", .{}, focus, active, err_);
                        try lines.append(line);
                    }
                    for (n.children.items, 0..) |child, i| {
                        if (top and i + 1 == n.children.items.len and child.kind == .vacant) {
                            if (focus == null or focus == n) continue;
                            if (focus != child) {
                                try lines.append(try self.plainLine("...", .{ .modifiers = 2 }));
                                continue;
                            }
                        }
                        var childlines = try self.renderNode(child, focus, active, false, err_);
                        if (!top) try self.indent(&childlines, n, focus, active);
                        try lines.appendSlice(childlines.items);
                    }
                    if (!top) {
                        line = self.lineNew();
                        try self.token(&line, n, "}", .{}, focus, active, err_);
                        try lines.append(line);
                    }
                    return lines;
                }
            },
            .binding, .field, .branch => {
                const label = n.children.items[0];
                if (n.kind == .binding) try self.token(&line, n, "let ", .{ .fg = .{ .indexed = 6 } }, focus, active, err_);
                if (n.kind == .binding) try self.renderPattern(&line, label, focus, active, err_) else try self.token(&line, label, label.text, if (n.kind == .branch) .{ .fg = .{ .indexed = 12 }, .modifiers = 1 } else .{}, focus, active, err_);
                try self.token(&line, n, if (n.kind == .binding) " = " else if (n.kind == .branch) " " else ": ", if (n.kind == .branch and focus != label) .{ .fg = .{ .indexed = 12 }, .modifiers = 1 } else .{}, focus, active, err_);
                try lines.append(line);
                const val = try self.renderNode(n.children.items[1], focus, active, false, err_);
                try joinLines(&lines, val);
                return lines;
            },
            .list, .record => {
                const pre = if (n.kind == .list) "[" else "{";
                const post = if (n.kind == .list) "]" else "}";
                var parts = std.ArrayList(Lines).init(a);
                var inline_ = true;
                for (n.children.items, 0..) |child, i| {
                    var childlines = try self.renderNode(child, focus, active, false, err_);
                    if (n.spread and i + 1 == n.children.items.len) try childlines.items[0].insert(0, .{ .text = "..", .style = self.styleFor(n, .{}, focus, active, err_) });
                    if (childlines.items.len > 1) inline_ = false;
                    try parts.append(childlines);
                }
                try self.token(&line, n, pre, .{}, focus, active, err_);
                try lines.append(line);
                if (inline_) {
                    for (parts.items, 0..) |part, i| {
                        if (i > 0) try self.token(&lines.items[0], n, ", ", .{}, focus, active, err_);
                        try lines.items[0].appendSlice(part.items[0].items);
                    }
                    try self.token(&lines.items[0], n, post, .{}, focus, active, err_);
                } else {
                    for (parts.items, 0..) |*part, i| {
                        if (i + 1 < parts.items.len) try self.token(&part.items[part.items.len - 1], n, ", ", .{}, focus, active, err_);
                        try self.indent(part, n, focus, active);
                        try lines.appendSlice(part.items);
                    }
                    line = self.lineNew();
                    try self.token(&line, n, post, .{}, focus, active, err_);
                    try lines.append(line);
                }
                return lines;
            },
            .case => {
                try self.token(&line, n, "match ", .{ .fg = .{ .indexed = 6 } }, focus, active, err_);
                try lines.append(line);
                const subject = try self.renderNode(n.children.items[0], focus, active, false, err_);
                if (subject.items.len == 1) try joinLines(&lines, subject) else try self.token(&lines.items[0], n, "some big case", .{}, focus, active, err_);
                try self.token(&lines.items[lines.items.len - 1], n, " {", .{}, focus, active, err_);
                for (n.children.items[1..]) |br| {
                    var part = try self.renderNode(br, focus, active, false, err_);
                    try self.indent(&part, n, focus, active);
                    try lines.appendSlice(part.items);
                }
                line = self.lineNew();
                try self.token(&line, n, "}", .{}, focus, active, err_);
                try lines.append(line);
                return lines;
            },
        }
        try lines.append(line);
        return lines;
    }
    fn indent(self: *Tui, lines: *Lines, n: *Node, focus: ?*Node, active: bool) !void {
        const style = self.styleFor(n, .{}, focus, active, false);
        for (lines.items) |*line| try line.insert(0, .{ .text = "  ", .style = style });
    }
    fn status(self: *Tui) !Line {
        const a = self.temp();
        var l = self.lineNew();
        if (self.mode == .running) {
            try l.append(.{ .text = if (self.vm_paused) "◌ evaluating · Esc cancel" else "◌ GitQuery · Esc cancel", .style = .{ .fg = .{ .indexed = 3 } } });
            return l;
        }
        if (self.mode == .history) {
            try l.append(.{ .text = try std.fmt.allocPrint(a, "history {}/{} · ↑↓ select · Enter recall · k code · K effects · Esc edit", .{ self.history_selected + 1, self.history.items.len }), .style = .{ .fg = .{ .indexed = 6 } } });
            return l;
        }
        if (self.message) |message| {
            try l.append(.{ .text = try std.mem.concat(a, u8, &.{ "! ", message }), .style = .{ .fg = .{ .indexed = 1 } } });
            return l;
        }
        if (self.root.kind == .vacant) {
            if (self.mode == .navigating) try l.append(.{ .text = if (self.history.items.len == 0) "Ctrl+Q quit" else "↑ history · Ctrl+Q quit", .style = .{ .modifiers = 2 } });
            return l;
        }
        const errors = self.analysis_errors;
        const loading = self.analysis_loading;
        try l.append(.{ .text = if (loading > 0) (if (loading < 10) try std.fmt.allocPrint(a, "◌{} ", .{loading}) else "◌9+") else if (errors == 0) "✔  " else if (errors < 10) try std.fmt.allocPrint(a, "!{} ", .{errors}) else "!9+", .style = .{ .fg = .{ .indexed = if (loading > 0) 3 else if (errors == 0) 2 else 1 } } });
        try l.append(.{ .text = "· " });
        if (self.selected.isExpression()) {
            if (self.cached_analysis.?.infoAtPath(try projectionPath(a, self.selected))) |info| {
                if (info.loading and self.selected.kind == .reference) {
                    try l.append(.{ .text = try std.mem.concat(a, u8, &.{ "loading ", try self.referenceDescription(self.selected) }), .style = .{ .fg = .{ .indexed = 3 } } });
                } else if (info.problem) |problem| {
                    try l.append(.{ .text = problem, .style = .{ .fg = .{ .indexed = 1 } } });
                } else try l.append(.{ .text = info.type_text });
            }
        }
        return l;
    }
    pub fn buffer(self: *Tui, width: usize, height: usize) Error!Buffer {
        try self.analyse();
        var buf = try Buffer.init(self.temp(), width, height);
        if (width == 0 or height == 0) return buf;
        const code_height = height - 1;
        var lines = self.linesNew();
        var selected_end: usize = 0;
        var reverse = self.history.items.len;
        while (reverse > 0) {
            reverse -= 1;
            const h = &self.history.items[reverse];
            if (self.mode == .history and self.history_selected == reverse) try lines.append(try self.plainLine("◆ selected history", .{}));
            const code = try self.renderNode(h.root, null, false, true, false);
            if (!(self.mode == .history and h.code) and code.items.len > 1) {
                try lines.append(code.items[0]);
                try lines.append(try self.plainLine(try std.fmt.allocPrint(self.temp(), "  ▸ {} more line{s}", .{ code.items.len - 1, if (code.items.len == 2) @as([]const u8, "") else "s" }), .{ .modifiers = 2 }));
            } else try lines.appendSlice(code.items);
            if (h.occured.len > 0) {
                if (!(self.mode == .history and h.effects)) try lines.append(try self.plainLine(try std.fmt.allocPrint(self.temp(), "▸ {} effect{s}", .{ h.occured.len, if (h.occured.len == 1) @as([]const u8, "") else "s" }), .{ .modifiers = 2 })) else for (h.occured) |effect| try lines.append(try self.plainLine(try std.fmt.allocPrint(self.temp(), "✔ {s}({s}) -> {s}", .{ effect.label, effect.lift, effect.reply }), .{ .fg = .{ .indexed = 7 } }));
            }
            if (if (h.value != null) try renderHistory(h, @max(1, width -| 2)) else h.result) |text| {
                var split = std.mem.splitScalar(u8, text, '\n');
                var i: usize = 0;
                while (split.next()) |part| : (i += 1) try lines.append(try self.plainLine(try std.mem.concat(self.temp(), u8, &.{ if (h.failure) "✘ " else if (h.aborted) "■ " else if (i == 0) "= " else "  ", part }), if (h.failure) .{ .fg = .{ .indexed = 1 } } else if (h.aborted) .{ .fg = .{ .indexed = 3 } } else .{}));
            }
            if (self.mode == .history and self.history_selected == reverse) selected_end = lines.items.len;
        }
        if (self.root.kind == .vacant) {
            if (self.history.items.len == 0) {
                try lines.append(try self.plainLine("EYG shell", .{ .modifiers = 1 }));
                try lines.append(try self.plainLine("Paste a program or build one with keys, then press Enter to run it.", .{ .modifiers = 2 }));
                try lines.append(try self.plainLine("Try pasting  !int_add(20, 22)  or press n for an integer.", .{ .modifiers = 2 }));
                try lines.append(try self.plainLine("q imports a file · @ adds a package · # a content reference", .{ .modifiers = 2 }));
                try lines.append(self.lineNew());
            }
            try lines.append(try self.plainLine("Write EYG…", .{ .modifiers = if (self.mode == .navigating) 32 else 10 }));
        } else {
            const input = try self.renderNode(self.root, self.selected, self.mode == .navigating, true, false);
            try lines.appendSlice(input.items);
        }
        const visible = @min(lines.items.len, code_height);
        const end = if (self.mode == .history) @max(selected_end, visible) else lines.items.len;
        const start = end - visible;
        const ystart = code_height - visible;
        for (lines.items[start..end], 0..) |line, i| renderLine(&buf, 0, ystart + i, line, width);
        renderLine(&buf, 0, code_height, try self.status(), width);
        if (self.mode == .input or self.mode == .picker) try self.popup(&buf, code_height);
        return buf;
    }
    fn popup(self: *Tui, buf: *Buffer, code_height: usize) !void {
        const width = @min(@as(usize, 50), buf.width);
        const height = @min(if (self.mode == .picker) @as(usize, 12) else 3, code_height);
        const x = (buf.width - width) / 2;
        const y = (code_height - height) / 2;
        if (width == 0 or height == 0) return;
        for (y..y + height) |row| for (x..x + width) |col| {
            buf.set(col, row, " ", 1, .{});
        };
        if (width < 2 or height < 2) return;
        for (x..x + width) |col| {
            buf.set(col, y, "─", 1, .{});
            if (height > 1) buf.set(col, y + height - 1, "─", 1, .{});
        }
        for (y..y + height) |row| {
            buf.set(x, row, "│", 1, .{});
            if (width > 1) buf.set(x + width - 1, row, "│", 1, .{});
        }
        buf.set(x, y, "╭", 1, .{});
        if (width > 1) buf.set(x + width - 1, y, "╮", 1, .{});
        if (height > 1) {
            buf.set(x, y + height - 1, "╰", 1, .{});
            if (width > 1) buf.set(x + width - 1, y + height - 1, "╯", 1, .{});
        }
        if (width < 3) return;
        const inner = width - 2;
        const invalid_cid = self.input_kind == .reference and !try self.validReference(self.input_value);
        const invalid = self.input_kind == .integer and (parseEditorNumber(self.input_value) catch null) == null;
        const title = if (self.mode == .picker) "↑↓ pick · Tab fill · Enter apply · Esc cancel" else if (invalid) "Enter a valid integer" else if (invalid_cid) "Enter a valid cid" else "Enter: apply | Esc: cancel";
        // Plain block titles truncate with an ellipsis; styled input titles clip.
        if (self.mode == .picker and cellWidth(title) > inner and inner > 0) {
            const cut = byteAtWidth(title, inner - 1);
            buf.text(x + 1, y, title[0..cut], .{}, inner);
            buf.text(x + inner, y, "…", .{}, 1);
        } else buf.text(x + 1, y, title, if (invalid or (invalid_cid)) .{ .fg = .{ .indexed = 1 } } else .{}, inner);
        if (height < 3) return;
        const completion_ = if (self.mode == .picker) try self.completion() else self.input_value;
        const suffix = try dropStartJs(self.temp(), completion_, graphemeCount(self.input_value));
        const placeholder = if (self.mode == .picker) (if (suffix.len == 0) "Type to filter" else "") else switch (self.input_kind) {
            .string => "Enter text",
            .integer => "Enter an integer",
            .reference => "Enter a content reference",
            .reply => "Standard input",
            else => "",
        };
        const display = if (self.input_value.len > 0) self.input_value else placeholder;
        const cursor_width = self.input_cursor;
        const view_start = if (cursor_width >= inner) cursor_width - inner + 1 else 0;
        const hidden = byteAtWidth(display, view_start);
        const shown = display[hidden..];
        const style: Style = .{ .modifiers = if (self.input_value.len > 0) 1 else 0 };
        // input.render pads its whole row using the input style, including blanks.
        for (x + 1..x + 1 + inner) |col| buf.set(col, y + 1, " ", 1, style);
        buf.text(x + 1, y + 1, shown, style, inner);
        if (self.mode == .picker) {
            const offset = cellWidth(self.input_value) - cellWidth(self.input_value[0..@min(hidden, self.input_value.len)]);
            if (suffix.len > 0 and offset < inner) buf.text(x + 1 + offset, y + 1, suffix, .{ .modifiers = 2 }, inner - offset);
            const matches_ = try self.matches();
            if (matches_.len == 0) {
                if (height > 3) buf.text(x + 1, y + 2, "No matches", .{}, inner);
                return;
            }
            const list_height = height - 3;
            const start = self.choice_selected + 1 -| list_height;
            const end = @min(matches_.len, start + list_height);
            for (matches_[start..end], start..) |choice, i| {
                const selected = i == self.choice_selected;
                const base: Style = .{ .fg = .{ .rgb = .{ 111, 220, 255 } }, .bg = if (selected) .{ .rgb = .{ 40, 48, 80 } } else .default };
                const name = try std.mem.concat(self.temp(), u8, &.{ if (selected) "› " else "  ", choice.name });
                const hint = try std.mem.concat(self.temp(), u8, &.{ " : ", try std.mem.replaceOwned(u8, self.temp(), choice.hint, "\n", " ") });
                buf.text(x + 1, y + 2 + i - start, name, base, inner);
                const cells = cellWidth(name);
                if (cells < inner) {
                    var hs = base;
                    hs.fg = .{ .rgb = .{ 210, 169, 255 } };
                    buf.text(x + 1 + cells, y + 2 + i - start, hint, hs, inner - cells);
                }
            }
        }
    }
    /// Keep returned snapshots in session storage for multi-frame protocols.
    pub fn frame(self: *Tui, width: usize, height: usize) Error!J {
        return self.frameAlloc(self.allocator, width, height);
    }
    /// Render with temporary storage and return a snapshot owned by the caller.
    /// Resetting output_allocator never affects editor state or earlier frames
    /// allocated elsewhere; the render buffer and temporary layout do not escape.
    pub fn frameAlloc(self: *Tui, output_allocator: Allocator, width: usize, height: usize) Error!J {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const previous_scratch = self.scratch;
        self.scratch = arena.allocator();
        defer self.scratch = previous_scratch;
        const b = try self.buffer(width, height);
        return b.json(output_allocator);
    }
    pub fn renderAnsi(self: *Tui, width: usize, height: usize) Error![]u8 {
        return self.renderAnsiAlloc(self.allocator, width, height);
    }
    pub fn renderAnsiAlloc(self: *Tui, output_allocator: Allocator, width: usize, height: usize) Error![]u8 {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        self.scratch = arena.allocator();
        defer self.scratch = null;
        const b = try self.buffer(width, height);
        return b.ansi(output_allocator);
    }
};
fn nodeIndex(p: *Node, n: *Node) usize {
    for (p.children.items, 0..) |child, i| if (child == n) return i;
    return 0;
}
fn irOp(a: Allocator, code: []const u8, label: []const u8) !J {
    return object(a, &.{ .{ "0", .{ .string = code } }, .{ "l", .{ .string = label } } });
}
fn irApply(a: Allocator, f: J, arg: J) !J {
    return object(a, &.{ .{ "0", .{ .string = "a" } }, .{ "f", f }, .{ "a", arg } });
}
fn quoted(a: Allocator, text: []const u8) ![]const u8 {
    return std.json.stringifyAlloc(a, text, .{ .emit_null_optional_fields = true });
}
fn joinLines(a: *Lines, b: Lines) !void {
    if (b.items.len == 0) return;
    if (a.items.len == 0) {
        try a.appendSlice(b.items);
        return;
    }
    try a.items[a.items.len - 1].appendSlice(b.items[0].items);
    try a.appendSlice(b.items[1..]);
}
fn renderLine(buf: *Buffer, x: usize, y: usize, line: Line, width: usize) void {
    var pos = x;
    for (line.items) |span| {
        if (pos >= x + width) break;
        buf.text(pos, y, span.text, span.style, x + width - pos);
        pos += cellWidth(span.text);
    }
}
fn commonPrefix(allocator: Allocator, left: []const u8, right: []const u8) ![]const u8 {
    var l: usize = 0;
    var r: usize = 0;
    while (l < left.len and r < right.len) {
        const le = unicode.graphemeEnd(left, l);
        const re = unicode.graphemeEnd(right, r);
        if (!eq(try unicode.changeCase(allocator, left[l..le], false), try unicode.changeCase(allocator, right[r..re], false))) break;
        l = le;
        r = re;
    }
    return left[0..l];
}
fn graphemeCount(text: []const u8) usize {
    var at: usize = 0;
    var count: usize = 0;
    while (at < text.len) : (count += 1) at = unicode.graphemeEnd(text, at);
    return count;
}
fn byteAtGrapheme(text: []const u8, count: usize) usize {
    var at: usize = 0;
    var n: usize = 0;
    while (at < text.len and n < count) : (n += 1) at = unicode.graphemeEnd(text, at);
    return at;
}
// The pinned JavaScript stdlib uses the UTF-8 size of a grapheme prefix
// as a UTF-16 slice index here. Preserve its observable completion behavior.
fn dropStartJs(allocator: Allocator, text: []const u8, count: usize) ![]const u8 {
    const units = byteAtGrapheme(text, count);
    var at: usize = 0;
    var consumed: usize = 0;
    while (at < text.len and consumed < units) {
        const point = codepoint(text, at);
        const width: usize = if (point.cp > 0xffff) 2 else 1;
        if (consumed + width > units) {
            // JavaScript slice can split a surrogate pair. WTF-8 retains that
            // code unit internally; the protocol writer escapes it as JSON,
            // and terminal output replaces it exactly as JavaScript does.
            const low: u21 = 0xdc00 + ((point.cp - 0x10000) & 0x3ff);
            const tail = try allocator.alloc(u8, 3 + text.len - point.end);
            tail[0] = 0xe0 | @as(u8, @intCast(low >> 12));
            tail[1] = 0x80 | @as(u8, @intCast((low >> 6) & 0x3f));
            tail[2] = 0x80 | @as(u8, @intCast(low & 0x3f));
            @memcpy(tail[3..], text[point.end..]);
            return tail;
        }
        consumed += width;
        at = point.end;
    }
    return text[at..];
}
fn writeAnsiSymbol(writer: anytype, text: []const u8) !void {
    var start: usize = 0;
    var at: usize = 0;
    while (at + 2 < text.len) : (at += 1) {
        if (text[at] == 0xed and text[at + 1] >= 0xa0 and text[at + 1] <= 0xbf and text[at + 2] >= 0x80 and text[at + 2] <= 0xbf) {
            try writer.writeAll(text[start..at]);
            try writer.writeAll("\xef\xbf\xbd");
            at += 2;
            start = at + 1;
        }
    }
    try writer.writeAll(text[start..]);
}
fn typeArity(ty: []const u8) usize {
    if (ty.len == 0 or ty[0] != '(') return 1;
    var nesting: usize = 0;
    var count: usize = 1;
    for (ty[1..]) |char| {
        if (char == ')' and nesting == 0) break;
        if (char == ',' and nesting == 0) count += 1;
        if (char == '(' or char == '[' or char == '{') nesting += 1;
        if (char == ')' or char == ']' or char == '}') nesting -|= 1;
    }
    return count;
}
fn actionName(key: []const u8) []const u8 {
    const names = .{ .{ "n", "insert integer" }, .{ "s", "insert string" }, .{ "f", "create function" }, .{ "v", "insert variable" }, .{ "j", "insert builtin" }, .{ "r", "create record" }, .{ "R", "create empty record" }, .{ "l", "create list" }, .{ "L", "create list" }, .{ "t", "tag" }, .{ "g", "select field" }, .{ "e", "assign" }, .{ "E", "assign before" }, .{ "p", "perform" }, .{ "h", "insert handle" }, .{ "d", "delete" }, .{ "c", "call function" }, .{ "C", "call" }, .{ "w", "call" }, .{ "m", "insert match" }, .{ "b", "create list" }, .{ "o", "overwrite" }, .{ "<", "insert before" }, .{ ">", "insert after" }, .{ "x", "spread" }, .{ "#", "insert reference" }, .{ "@", "choose release" } };
    inline for (names) |pair| if (eq(key, pair[0])) return pair[1];
    return key;
}

const Grapheme = struct { end: usize, width: u8 };
fn codepoint(s: []const u8, pos: usize) struct { cp: u21, end: usize } {
    const len = std.unicode.utf8ByteSequenceLength(s[pos]) catch 1;
    const end = @min(s.len, pos + len);
    const cp = std.unicode.utf8Decode(s[pos..end]) catch 0xfffd;
    return .{ .cp = cp, .end = end };
}
fn cpWidth(cp: u21) u8 {
    if (cp >= 0x0300 and cp <= 0x036F) return 0;
    if (cp >= 0x1160 and cp <= 0x11FF) return 0;
    if (cp >= 0xFE00 and cp <= 0xFE0F) return 0;
    if (cp >= 0xE0100 and cp <= 0xE01EF) return 0;
    if (cp >= 0x1100 and cp <= 0x115F) return 2;
    if (cp >= 0x2E80 and cp <= 0x303E) return 2;
    if (cp >= 0x3041 and cp <= 0x33FF) return 2;
    if (cp >= 0x3400 and cp <= 0x4DBF) return 2;
    if (cp >= 0x4E00 and cp <= 0x9FFF) return 2;
    if (cp >= 0xA000 and cp <= 0xA4CF) return 2;
    if (cp >= 0xAC00 and cp <= 0xD7A3) return 2;
    if (cp >= 0xF900 and cp <= 0xFAFF) return 2;
    if (cp >= 0xFE30 and cp <= 0xFE4F) return 2;
    if (cp >= 0xFF00 and cp <= 0xFF60) return 2;
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return 2;
    if (cp >= 0x1F1E6 and cp <= 0x1F1FF) return 2;
    if (cp >= 0x1F300 and cp <= 0x1F5FF) return 2;
    if (cp >= 0x1F600 and cp <= 0x1F64F) return 2;
    if (cp >= 0x1F680 and cp <= 0x1F6FF) return 2;
    if (cp >= 0x1F700 and cp <= 0x1F77F) return 2;
    if (cp >= 0x1F780 and cp <= 0x1F7FF) return 2;
    if (cp >= 0x1F800 and cp <= 0x1F8FF) return 2;
    if (cp >= 0x1F900 and cp <= 0x1F9FF) return 2;
    if (cp >= 0x1FA00 and cp <= 0x1FAFF) return 2;
    if (cp >= 0x20000 and cp <= 0x2FFFD) return 2;
    if (cp >= 0x30000 and cp <= 0x3FFFD) return 2;
    if (cp >= 0x2329 and cp <= 0x232A) return 2;
    if (cp >= 0x231A and cp <= 0x231B) return 2;
    if (cp >= 0x23E9 and cp <= 0x23EC) return 2;
    if (cp >= 0x25FD and cp <= 0x25FE) return 2;
    if (cp >= 0x2614 and cp <= 0x2615) return 2;
    if (cp >= 0x2648 and cp <= 0x2653) return 2;
    if (cp >= 0x26AA and cp <= 0x26AB) return 2;
    if (cp >= 0x26BD and cp <= 0x26BE) return 2;
    if (cp >= 0x26C4 and cp <= 0x26C5) return 2;
    if (cp >= 0x26F2 and cp <= 0x26F3) return 2;
    if (cp >= 0x270A and cp <= 0x270B) return 2;
    if (cp >= 0x2753 and cp <= 0x2755) return 2;
    if (cp >= 0x2795 and cp <= 0x2797) return 2;
    if (cp >= 0x2B1B and cp <= 0x2B1C) return 2;
    if (cp >= 0x1F191 and cp <= 0x1F19A) return 2;
    if (cp >= 0x1F200 and cp <= 0x1F202) return 2;
    if (cp >= 0x1F210 and cp <= 0x1F23B) return 2;
    if (cp >= 0x1F240 and cp <= 0x1F248) return 2;
    if (cp >= 0x1F250 and cp <= 0x1F251) return 2;
    if (cp >= 0x1F260 and cp <= 0x1F265) return 2;
    if (cp < 0x20 or cp == 0x7f or cp == 0x200b or cp == 0x200c or cp == 0x200d or cp == 0xfeff) return 0;
    if (cp == 0x1F004 or cp == 0x1F0CF or cp == 0x1F18E) return 2;
    return 1;
}
fn grapheme(s: []const u8, pos: usize) Grapheme {
    return .{ .end = unicode.graphemeEnd(s, pos), .width = cpWidth(codepoint(s, pos).cp) };
}
fn cellWidth(s: []const u8) usize {
    var pos: usize = 0;
    var width: usize = 0;
    while (pos < s.len) {
        const g = grapheme(s, pos);
        width += g.width;
        pos = g.end;
    }
    return width;
}
fn byteAtWidth(s: []const u8, width: usize) usize {
    if (width == 0) return 0;
    var pos: usize = 0;
    var cells: usize = 0;
    while (pos < s.len) {
        const g = grapheme(s, pos);
        if (cells + g.width > width) break;
        cells += g.width;
        pos = g.end;
    }
    return pos;
}

const builtin_choices = [_]Choice{
    .{ .name = "equal", .hint = "(0, 0) -> [True: {} | False: {}]" },
    .{ .name = "fix", .hint = "(((0 <..1>) -> 2, 0 <..1>) -> 2, 0 <..1>) -> 2" },
    .{ .name = "never", .hint = "(Never) -> 0" },
    .{ .name = "int_compare", .hint = "(Integer, Integer) -> [Lt: {} | Eq: {} | Gt: {}]" },
    .{ .name = "int_add", .hint = "(Integer, Integer) -> Integer" },
    .{ .name = "int_subtract", .hint = "(Integer, Integer) -> Integer" },
    .{ .name = "int_multiply", .hint = "(Integer, Integer) -> Integer" },
    .{ .name = "int_divide", .hint = "(Integer, Integer) -> [Ok: Integer | Error: {}]" },
    .{ .name = "int_absolute", .hint = "(Integer) -> Integer" },
    .{ .name = "int_parse", .hint = "(String) -> [Ok: Integer | Error: {}]" },
    .{ .name = "int_to_string", .hint = "(Integer) -> String" },
    .{ .name = "string_append", .hint = "(String, String) -> String" },
    .{ .name = "string_split", .hint = "(String, String) -> {head: String, tail: List(String)}" },
    .{ .name = "string_split_once", .hint = "(String, String) -> [Ok: {pre: String, post: String} | Error: {}]" },
    .{ .name = "string_replace", .hint = "(String, String, String) -> String" },
    .{ .name = "string_uppercase", .hint = "(String) -> String" },
    .{ .name = "string_lowercase", .hint = "(String) -> String" },
    .{ .name = "string_starts_with", .hint = "(String, String) -> [True: {} | False: {}]" },
    .{ .name = "string_ends_with", .hint = "(String, String) -> [True: {} | False: {}]" },
    .{ .name = "string_length", .hint = "(String) -> Integer" },
    .{ .name = "string_to_binary", .hint = "(String) -> Binary" },
    .{ .name = "string_from_binary", .hint = "(Binary) -> [Ok: String | Error: {}]" },
    .{ .name = "binary_from_integers", .hint = "(List(Integer)) -> Binary" },
    .{ .name = "binary_size", .hint = "(Binary) -> Integer" },
    .{ .name = "binary_concat", .hint = "(Binary, Binary) -> Binary" },
    .{ .name = "binary_compare", .hint = "(Binary, Binary) -> [Lt: {} | Eq: {} | Gt: {}]" },
    .{ .name = "binary_fold", .hint = "(Binary, 0, (Integer <..1>, 0 <..1>) -> 0 <..1>) -> 0" },
    .{ .name = "list_pop", .hint = "(List(0)) -> [Ok: {head: 0, tail: List(0)} | Error: {}]" },
    .{ .name = "list_fold", .hint = "(List(0), 1, (0 <..2>, 1 <..2>) -> 1 <..2>) -> 1" },
};

const effect_choices = [_]Choice{
    .{ .name = "AppendFile", .hint = "{path: String, contents: Binary} : [Ok: {} | Error: String]" },
    .{ .name = "CreateKey", .hint = "[Eddsa: {}] : [Ok: [Eddsa: {kty: String, crv: String, x: Binary, d: Binary}] | Error: String]" },
    .{ .name = "CWD", .hint = "{} : [Ok: String | Error: {}]" },
    .{ .name = "DecodeJSON", .hint = "Binary : [\n  Ok: List(\n    {\n      term: [\n        True: {} |\n        False: {} |\n        Null: {} |\n        Integer: Integer |\n        Number: {\n          sign: [Positive: {} | Negative: {}],\n          integer: Integer,\n          decimal: {numerator: Integer, size: Integer},\n          exponent: Integer,\n        } |\n        String: String |\n        Array: {} |\n        Object: {} |\n        Field: String\n      ],\n      depth: Integer,\n    }\n  ) |\n  Error: String\n]" },
    .{ .name = "DeleteFile", .hint = "String : [Ok: {} | Error: String]" },
    .{ .name = "Env", .hint = "String : [Some: String | None: {}]" },
    .{ .name = "Exit", .hint = "Integer : Never" },
    .{ .name = "EYGParse", .hint = "String : [\n  Ok: List(\n    [\n      Variable: String |\n      Lambda: String |\n      Apply: {} |\n      Let: String |\n      Binary: Binary |\n      Integer: Integer |\n      String: String |\n      Tail: {} |\n      Cons: {} |\n      Vacant: {} |\n      Empty: {} |\n      Extend: String |\n      Select: String |\n      Overwrite: String |\n      Tag: String |\n      Case: String |\n      NoCases: {} |\n      Perform: String |\n      Handle: String |\n      Builtin: String |\n      Reference: [\n        Content: String |\n        Package: String |\n        Version: {package: String, version: Integer} |\n        Pinned: {package: String, version: Integer, cid: String} |\n        Relative: String\n      ]\n    ]\n  ) |\n  Error: String\n]" },
    .{ .name = "Fetch", .hint = "{\n  method: [\n    CONNECT: {} |\n    DELETE: {} |\n    GET: {} |\n    HEAD: {} |\n    OPTIONS: {} |\n    PATCH: {} |\n    POST: {} |\n    PUT: {} |\n    TRACE: {}\n  ],\n  scheme: [HTTP: {} | HTTPS: {}],\n  host: String,\n  port: [Some: Integer | None: {}],\n  path: String,\n  query: [Some: String | None: {}],\n  headers: List({key: String, value: String}),\n  body: Binary,\n} : [\n  Ok: {\n    status: Integer,\n    headers: List({key: String, value: String}),\n    body: Binary,\n  } |\n  Error: String\n]" },
    .{ .name = "Flip", .hint = "{} : [True: {} | False: {}]" },
    .{ .name = "Hash", .hint = "{algorithm: [SHA256: {}], bytes: Binary} : Binary" },
    .{ .name = "MakeDirectory", .hint = "String : [Ok: {} | Error: String]" },
    .{ .name = "Now", .hint = "{} : Integer" },
    .{ .name = "Random", .hint = "Integer : Integer" },
    .{ .name = "ReadDirectory", .hint = "String : [\n  Ok: List({name: String, type: [Directory: {} | File: {size: Integer}]}) |\n  Error: String\n]" },
    .{ .name = "ReadFile", .hint = "{path: String, offset: Integer, limit: Integer} : [Ok: Binary | Error: String]" },
    .{ .name = "Sign", .hint = "{key: [Eddsa: {kty: String, crv: String, x: Binary, d: Binary}], data: Binary} : [Ok: Binary | Error: String]" },
    .{ .name = "Sleep", .hint = "Integer : {}" },
    .{ .name = "StandardError", .hint = "String : {}" },
    .{ .name = "StandardIn", .hint = "{} : [Ok: Binary | Error: String]" },
    .{ .name = "StandardOut", .hint = "String : {}" },
    .{ .name = "WriteFile", .hint = "{path: String, contents: Binary} : [Ok: {} | Error: String]" },
};

fn parseModule(a: Allocator, text: []const u8) !J {
    const code = if (std.mem.startsWith(u8, text, "#!")) (if (std.mem.indexOfScalar(u8, text, '\n')) |newline| text[newline + 1 ..] else "") else text;
    const trimmed = std.mem.trim(u8, code, " \t\r\n");
    if (trimmed.len > 0 and trimmed[0] == '{') {
        if (std.json.parseFromSlice(J, a, trimmed, .{ .allocate = .alloc_always })) |parsed| {
            if (field(parsed.value, "0") == .string and interpreter.validIr(parsed.value)) return parsed.value;
        } else |_| {}
    }
    return parser.parseExpression(a, code);
}

fn prependPath(a: Allocator, index: usize, rest: []const usize) ![]usize {
    const path = try a.alloc(usize, rest.len + 1);
    path[0] = index;
    @memcpy(path[1..], rest);
    return path;
}
fn nodePath(a: Allocator, n: *Node) ![]usize {
    return pathWithMode(a, n, null, false);
}
fn projectionPath(a: Allocator, n: *Node) ![]usize {
    return renderPath(a, n, n);
}
fn renderPath(a: Allocator, n: *Node, focus: ?*Node) ![]usize {
    return pathWithMode(a, n, focus, true);
}
fn pathWithMode(a: Allocator, n: *Node, focus: ?*Node, rendering: bool) ![]usize {
    var path = std.ArrayList(usize).init(a);
    var at = n;
    while (at.parent) |parent| {
        const index = nodeIndex(parent, at);
        switch (parent.kind) {
            .field => {
                const owner = parent.parent.?;
                try path.append(nodeIndex(owner, parent) * 2 + index);
                at = owner;
            },
            .binding => {
                const block_ = parent.parent.?;
                try path.append(index);
                try path.append(nodeIndex(block_, parent));
                at = block_;
            },
            .branch => {
                const case_ = parent.parent.?;
                if (index > 0) try path.append(0);
                try path.append(nodeIndex(case_, parent));
                at = case_;
            },
            .select => {
                if (!rendering) {
                    try path.append(if (index == 0) @as(usize, 1) else 0);
                } else if (focus != null and focus.? == parent.children.items[1] and index == 0) {
                    // The selected field projection renders its source at the
                    // enclosing path, as the reference renderer does.
                } else try path.append(index);
                at = parent;
            },
            .record => {
                if (parent.spread and index + 1 == parent.children.items.len) {
                    const fields = parent.children.items.len - 1;
                    const zoomed = focus != null and at.contains(focus.?);
                    try path.append(if (zoomed) fields + 1 else fields * 2);
                } else try path.append(index);
                at = parent;
            },
            else => {
                try path.append(index);
                at = parent;
            },
        }
    }
    return path.toOwnedSlice();
}
fn annotateMetadata(ir: *J, path: []const usize, a: Allocator) anyerror!void {
    if (ir.* != .object or field(ir.*, "0") != .string or field(ir.*, "_native_path") == .array) return;
    var values = std.ArrayList(J).init(a);
    for (path) |index| try values.append(jint(index));
    try ir.object.put("_native_path", .{ .array = values });
    try ir.object.put("_native_depth", jint(path.len));
    var iterator = ir.object.iterator();
    while (iterator.next()) |entry| if (entry.value_ptr.* == .object) {
        try annotateMetadata(entry.value_ptr, path, a);
    };
}
fn hashNode(hash: *std.hash.Wyhash, n: *Node) void {
    const identity = @intFromPtr(n);
    const tag = @intFromEnum(n.kind);
    hash.update(std.mem.asBytes(&identity));
    hash.update(std.mem.asBytes(&tag));
    hash.update(n.text);
    hash.update(std.mem.asBytes(&n.number));
    if (n.wide_number) |wide| hash.update(std.mem.asBytes(&wide));
    hash.update(std.mem.asBytes(&n.spread));
    hash.update(std.mem.asBytes(&n.destructured));
    for (n.children.items) |child| hashNode(hash, child);
}

/// Result documents are immutable until the viewport width changes. Keeping
/// their temporary document graph in an owned arena avoids session-arena growth
/// on every key while a large query result remains in scrollback.
fn renderHistory(entry: *History, width: usize) ![]const u8 {
    if (entry.render_cache == null) entry.render_cache = .{ .width = 0, .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator), .text = "" };
    const cache = &entry.render_cache.?;
    if (cache.width != width) {
        _ = cache.arena.reset(.retain_capacity);
        var printer = interpreter.Engine.init(cache.arena.allocator());
        cache.text = try printer.render(entry.value.?, width);
        cache.width = width;
    }
    return cache.text;
}

fn editableText(n: *Node) []const u8 {
    return switch (n.kind) {
        .select => n.children.items[1].text,
        .binding, .field, .branch => n.children.items[0].text,
        else => n.text,
    };
}

fn isExtension(kind: InputKind) bool {
    return switch (kind) {
        .extend_field_before, .extend_field_after, .extend_pattern_before, .extend_pattern_after, .extend_parameter_before, .extend_parameter_after, .extend_branch_before, .extend_branch_after => true,
        else => false,
    };
}
fn extensionBefore(kind: InputKind) bool {
    return switch (kind) {
        .extend_field_before, .extend_pattern_before, .extend_parameter_before, .extend_branch_before => true,
        else => false,
    };
}

fn parseEditorNumber(text: []const u8) !f64 {
    if (text.len == 0) return error.InvalidInteger;
    var i: usize = if (text[0] == '+' or text[0] == '-') 1 else 0;
    if (i == text.len) return error.InvalidInteger;
    while (i < text.len) : (i += 1) if (!std.ascii.isDigit(text[i])) return error.InvalidInteger;
    return std.fmt.parseFloat(f64, text);
}
