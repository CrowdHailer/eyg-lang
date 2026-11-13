//! Hub I/O and decoding run in an independent arena. The UI merges a completed
//! immutable snapshot; no mutable cache or interpreter allocation crosses threads.
const std = @import("std");
const hub = @import("hub.zig");
const runtime = @import("interpreter.zig");
const J = std.json.Value;
const A = std.mem.Allocator;

pub const Worker = struct {
    arena: std.heap.ArenaAllocator,
    origin: []const u8,
    reference: ?J,
    seed: J,
    snapshot: J = .null,
    failure: ?anyerror = null,
    completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    references: std.atomic.Value(u32) = std.atomic.Value(u32).init(2),
    thread: ?std.Thread = null,

    /// null reference replicates the package ledger; a reference fetches its
    /// verified module and every pinned/content dependency.
    pub fn start(cache: *const hub.Cache, reference: ?J) !*Worker {
        const self = try std.heap.page_allocator.create(Worker);
        self.* = .{ .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator), .origin = "", .reference = null, .seed = .null };
        errdefer {
            self.arena.deinit();
            std.heap.page_allocator.destroy(self);
        }
        const a = self.arena.allocator();
        self.origin = try a.dupe(u8, cache.origin);
        // Cache strings/programs live in the UI arena. Deep-copy through the
        // transport before the worker starts, not while it is running.
        self.seed = try clone(a, try exportCache(a, cache));
        if (reference) |ref| self.reference = try clone(a, ref);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }
    fn run(self: *Worker) void {
        self.execute() catch |err| {
            self.failure = err;
        };
        self.completed.store(true, .release);
        self.release();
    }
    fn execute(self: *Worker) !void {
        var cache = try hub.Cache.init(self.arena.allocator(), self.origin);
        try mergeCache(&cache, self.seed);
        defer {
            self.snapshot = exportCache(self.arena.allocator(), &cache) catch |err| snapshot: {
                self.failure = err;
                break :snapshot .null;
            };
        }
        if (self.reference) |ref| {
            var seen = std.StringHashMap(void).init(self.arena.allocator());
            try fetchReference(&cache, ref, &seen);
        } else try cache.refresh();
    }
    pub fn ready(self: *Worker) bool {
        return self.completed.load(.acquire);
    }
    pub fn merge(self: *Worker, cache: *hub.Cache) !void {
        if (self.snapshot != .null) try mergeCache(cache, self.snapshot);
        if (self.failure) |err| cache.last_error = @errorName(err);
    }
    pub fn destroy(self: *Worker) void {
        // Read-only network I/O must not hold terminal cleanup. This worker
        // owns all request/result storage and never accesses the departed UI.
        if (self.thread) |thread| thread.detach();
        self.release();
    }
    fn release(self: *Worker) void {
        if (self.references.fetchSub(1, .acq_rel) == 1) {
            self.arena.deinit();
            std.heap.page_allocator.destroy(self);
        }
    }
};

fn clone(a: A, value: J) !J {
    const bytes = try std.json.stringifyAlloc(a, value, .{});
    return (try std.json.parseFromSlice(J, a, bytes, .{ .allocate = .alloc_always })).value;
}

pub fn exportCache(a: A, cache: *const hub.Cache) !J {
    var latest = std.ArrayList(J).init(a);
    var releases = std.ArrayList(J).init(a);
    var modules = std.ArrayList(J).init(a);
    var packages = cache.latest.valueIterator();
    while (packages.next()) |p| try latest.append(try runtime.object(a, &.{
        .{ "name", .{ .string = p.name } }, .{ "version", .{ .integer = p.version } },
        .{ "cid", .{ .string = p.cid } },   .{ "cursor", .{ .integer = p.cursor } },
    }));
    var release_it = cache.releases.iterator();
    while (release_it.next()) |entry| try releases.append(try runtime.object(a, &.{ .{ "key", .{ .string = entry.key_ptr.* } }, .{ "cid", .{ .string = entry.value_ptr.* } } }));
    var module_it = cache.modules.iterator();
    while (module_it.next()) |entry| try modules.append(try runtime.object(a, &.{ .{ "cid", .{ .string = entry.key_ptr.* } }, .{ "bytes", .{ .string = try hub.canonicalBytes(a, entry.value_ptr.source) } } }));
    return runtime.object(a, &.{ .{ "latest", .{ .array = latest } }, .{ "releases", .{ .array = releases } }, .{ "modules", .{ .array = modules } }, .{ "cursor", .{ .integer = cache.cursor } }, .{ "pulled", .{ .bool = cache.pulled } }, .{ "refresh_on_miss", .{ .bool = cache.refresh_on_miss } } });
}

pub fn mergeCache(cache: *hub.Cache, snapshot: J) !void {
    const a = cache.allocator;
    const latest = runtime.field(snapshot, "latest");
    if (latest == .array) for (latest.array.items) |entry| {
        try cache.addPackage(runtime.stringField(entry, "name") orelse return error.InvalidCacheSnapshot, runtime.field(entry, "version").integer, runtime.stringField(entry, "cid") orelse return error.InvalidCacheSnapshot, runtime.field(entry, "cursor").integer);
    };
    const releases = runtime.field(snapshot, "releases");
    if (releases == .array) for (releases.array.items) |entry| {
        const key = runtime.stringField(entry, "key") orelse return error.InvalidCacheSnapshot;
        const cid = runtime.stringField(entry, "cid") orelse return error.InvalidCacheSnapshot;
        try cache.releases.put(try a.dupe(u8, key), try a.dupe(u8, cid));
    };
    const modules = runtime.field(snapshot, "modules");
    if (modules == .array) for (modules.array.items) |entry| {
        const cid = runtime.stringField(entry, "cid") orelse return error.InvalidCacheSnapshot;
        if (!cache.modules.contains(cid)) _ = try cache.ingestModule(cid, runtime.stringField(entry, "bytes") orelse return error.InvalidCacheSnapshot);
    };
    const cursor = runtime.field(snapshot, "cursor");
    const refresh = runtime.field(snapshot, "refresh_on_miss");
    if (refresh == .bool) cache.refresh_on_miss = refresh.bool;
    if (cursor == .integer and cursor.integer >= cache.cursor) {
        cache.cursor = cursor.integer;
        const pulled = runtime.field(snapshot, "pulled");
        if (pulled == .bool) cache.pulled = pulled.bool;
    }
}

fn fetchReference(cache: *hub.Cache, reference: J, seen: *std.StringHashMap(void)) anyerror!void {
    const cid = try cache.referenceCID(reference);
    if (seen.contains(cid)) return;
    if (seen.count() >= 10000) return error.ModuleDependencyLimit;
    try seen.put(cid, {});
    const source = try cache.resolveIR(reference);
    try fetchDependencies(cache, source, seen);
}
fn fetchDependencies(cache: *hub.Cache, value: J, seen: *std.StringHashMap(void)) anyerror!void {
    switch (value) {
        .object => |object| {
            const code = runtime.stringField(value, "0") orelse "";
            if (std.mem.eql(u8, code, "#") or (std.mem.eql(u8, code, "@") and runtime.field(value, "l") != .null)) {
                try fetchReference(cache, value, seen);
                return;
            }
            for (object.values()) |child| try fetchDependencies(cache, child, seen);
        },
        .array => |array| for (array.items) |child| try fetchDependencies(cache, child, seen),
        else => {},
    }
}

test "hub snapshots own transferred programs and verify their content" {
    var source_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var target_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer target_arena.deinit();
    const a = source_arena.allocator();
    var source = try hub.Cache.init(a, "http://localhost:1");
    const program = try runtime.object(a, &.{ .{ "0", .{ .string = "i" } }, .{ "v", .{ .integer = 42 } } });
    const cid = try hub.canonicalCID(a, program);
    _ = try source.ingestModule(cid, try hub.canonicalBytes(a, program));
    try source.addPackage("demo", 1, cid, 1);
    source.pulled = true;
    var target = try hub.Cache.init(target_arena.allocator(), "http://localhost:1");
    try mergeCache(&target, try exportCache(a, &source));
    source_arena.deinit();
    var engine = runtime.Engine.init(target_arena.allocator());
    const value = try target.resolve(&engine, try runtime.object(target_arena.allocator(), &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = "demo" } } }));
    try std.testing.expectEqual(@as(i64, 42), value.integer);
}
