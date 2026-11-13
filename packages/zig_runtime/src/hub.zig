//! Read-only EYG hub cache. The owner serializes access; transport can run in a
//! worker, but mutable cache/allocator state must not be shared with the UI.
//! Module bytes are decoded and canonically re-encoded before CID verification.
const std = @import("std");
pub const runtime = @import("interpreter.zig");
const codec = @import("ir_codec.zig");
const http = @import("http.zig");
const A = std.mem.Allocator;
const J = std.json.Value;
const V = runtime.Value;
pub const Response = http.Response;
pub const Transport = *const fn (?*anyopaque, A, []const u8) anyerror!Response;
pub const Package = struct { name: []const u8, version: i64, cid: []const u8, cursor: i64 = 0 };
pub const Module = struct { source: J, value: ?V = null };

pub const Cache = struct {
    allocator: A,
    origin: []const u8,
    modules: std.StringHashMap(Module),
    latest: std.StringHashMap(Package),
    releases: std.StringHashMap([]const u8),
    loading: std.StringHashMap(void),
    invalid: std.StringHashMap(runtime.Reason),
    cursor: i64 = 0,
    pulled: bool = false,
    refresh_on_miss: bool = true,
    transport: Transport = liveGet,
    transport_context: ?*anyopaque = null,
    last_error: ?[]const u8 = null,

    pub fn init(a: A, origin: []const u8) !Cache {
        return .{ .allocator = a, .origin = try normalizeOrigin(a, origin), .modules = std.StringHashMap(Module).init(a), .latest = std.StringHashMap(Package).init(a), .releases = std.StringHashMap([]const u8).init(a), .loading = std.StringHashMap(void).init(a), .invalid = std.StringHashMap(runtime.Reason).init(a) };
    }

    /// Default CLI configuration extracts an origin from EYG_ORIGIN and falls
    /// back to https://eyg.run when it is absent or invalid.
    pub fn configured(a: A) !Cache {
        const configured_origin = std.process.getEnvVarOwned(a, "EYG_ORIGIN") catch return init(a, "https://eyg.run");
        return init(a, configured_origin);
    }

    fn releaseKey(self: *Cache, name: []const u8, version: i64) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}\x00{d}", .{ name, version });
    }

    pub fn addPackage(self: *Cache, name: []const u8, version: i64, cid: []const u8, cursor: i64) !void {
        const canonical = try codec.canonicalCid(self.allocator, cid);
        const owned_name = try self.allocator.dupe(u8, name);
        try self.releases.put(try self.releaseKey(owned_name, version), canonical);
        if (self.latest.get(name)) |previous| if (previous.cursor >= cursor) return;
        try self.latest.put(owned_name, .{ .name = owned_name, .version = version, .cid = canonical, .cursor = cursor });
    }

    /// Deterministic fixtures use the same verified module ingestion as GET.
    /// A supplied CID must agree with the program, never a trusted fixture hint.
    pub fn ingestPackages(self: *Cache, packages: J) !void {
        if (packages != .object) return error.InvalidPackagesFixture;
        var entries = packages.object.iterator();
        var cursor = self.cursor;
        while (entries.next()) |entry| {
            const fixture = entry.value_ptr.*;
            const program = runtime.field(fixture, "program");
            const computed = try canonicalCID(self.allocator, program);
            const cid = runtime.stringField(fixture, "cid") orelse computed;
            const version = if (runtime.field(fixture, "version") == .null) 1 else try integer(fixture, "version");
            _ = try self.ingestModule(cid, try canonicalBytes(self.allocator, program));
            cursor += 1;
            try self.addPackage(entry.key_ptr.*, version, cid, cursor);
        }
        self.cursor = cursor;
        self.pulled = true;
        self.refresh_on_miss = false;
    }

    pub fn packageList(self: *const Cache, a: A) ![]Package {
        const result = try a.alloc(Package, self.latest.count());
        var values = self.latest.valueIterator();
        var index: usize = 0;
        while (values.next()) |value| : (index += 1) result[index] = value.*;
        std.mem.sort(Package, result, {}, struct {
            fn less(_: void, left: Package, right: Package) bool {
                return @import("unicode.zig").utf16LessThan(left.name, right.name);
            }
        }.less);
        return result;
    }

    /// Invalid publisher payloads still advance the cursor, as the oracle does.
    /// Ledger entries are trusted hub records; module contents are hash-checked.
    pub fn ingestLedger(self: *Cache, bytes: []const u8) !void {
        const response = (try std.json.parseFromSlice(J, self.allocator, bytes, .{ .allocate = .alloc_always })).value;
        const entries = runtime.field(response, "entries");
        if (entries != .array) return error.InvalidLedger;
        // The oracle decodes the whole archived-entry page before updating its
        // cache. A malformed later entry must not partly apply earlier ones.
        for (entries.array.items) |entry| {
            _ = try integer(entry, "cursor");
            _ = try integer(entry, "sequence");
            _ = try cidField(self.allocator, entry, "cid");
            _ = try cidField(self.allocator, entry, "entity");
            _ = try text(entry, "type");
            if (entry.object.get("previous")) |_| _ = try cidField(self.allocator, entry, "previous");
            _ = try text(entry, "payload");
        }
        for (entries.array.items) |entry| {
            const cursor = try integer(entry, "cursor");
            const payload = try text(entry, "payload");
            self.cursor = cursor;
            const decoded = std.json.parseFromSlice(J, self.allocator, payload, .{ .allocate = .alloc_always }) catch continue;
            const release = publisherRelease(self.allocator, decoded.value, cursor) catch continue;
            try self.addPackage(release.name, release.version, release.cid, cursor);
        }
        self.pulled = entries.array.items.len == 0;
        self.last_error = null;
    }

    pub fn pull(self: *Cache) !void {
        var pages: usize = 0;
        while (!self.pulled) {
            if (pages >= 10000) return error.LedgerPageLimit;
            pages += 1;
            const old_cursor = self.cursor;
            const path = if (old_cursor == 0) "/packages/pull" else try std.fmt.allocPrint(self.allocator, "/packages/pull?since={d}", .{old_cursor});
            const response = self.get(path) catch |err| {
                self.last_error = @errorName(err);
                return err;
            };
            if (response.status != 200) {
                self.last_error = "bad package lookup";
                return error.BadPackageLookup;
            }
            try self.ingestLedger(response.body);
            if (!self.pulled and self.cursor <= old_cursor) return error.LedgerCursorDidNotAdvance;
        }
    }

    /// Start a fresh incremental pull even after the current ledger is drained.
    /// Known packages stay cached; missing live names/versions request this once.
    pub fn refresh(self: *Cache) !void {
        self.pulled = false;
        try self.pull();
    }

    fn get(self: *Cache, path: []const u8) !Response {
        const url = try std.mem.concat(self.allocator, u8, &.{ self.origin, path });
        return self.transport(self.transport_context, self.allocator, url);
    }

    pub fn ingestModule(self: *Cache, cid: []const u8, bytes: []const u8) !J {
        const expected = try codec.canonicalCid(self.allocator, cid);
        const parsed = (try std.json.parseFromSlice(J, self.allocator, bytes, .{ .allocate = .alloc_always })).value;
        const source = try canonicalTree(self.allocator, parsed);
        const computed = try canonicalCID(self.allocator, source);
        if (!std.mem.eql(u8, expected, computed)) {
            self.last_error = "hub returned module with the wrong cid.";
            return error.ModuleHashMismatch;
        }
        if (!self.modules.contains(expected)) try self.modules.put(expected, .{ .source = source });
        return source;
    }

    fn moduleIR(self: *Cache, cid: []const u8) !J {
        if (self.modules.get(cid)) |module| return module.source;
        const response = try self.get(try std.mem.concat(self.allocator, u8, &.{ "/modules/", cid }));
        if (response.status == 204) {
            self.last_error = "no module";
            return error.NoModule;
        }
        if (response.status != 200) {
            self.last_error = "bad module lookup";
            return error.BadModuleLookup;
        }
        return self.ingestModule(cid, response.body);
    }

    pub fn referenceCID(self: *Cache, reference: J) ![]const u8 {
        const code = try text(reference, "0");
        if (std.mem.eql(u8, code, "#")) return cidField(self.allocator, reference, "l");
        if (!std.mem.eql(u8, code, "@")) return error.UndefinedReference;
        const name = try text(reference, "p");
        const raw_version = runtime.field(reference, "r");
        if (raw_version == .null) {
            if (self.latest.get(name)) |entry| return entry.cid;
            if (!self.pulled) try self.pull() else if (self.refresh_on_miss) try self.refresh();
            return if (self.latest.get(name)) |entry| entry.cid else error.UnknownPackage;
        }
        const version_number = codec.jsonInteger(raw_version) orelse return error.InvalidVersion;
        if (version_number < 1 or version_number >= 9223372036854775808.0) return error.UnknownRelease;
        const key = try self.releaseKey(name, @intFromFloat(version_number));
        if (!self.releases.contains(key)) {
            if (!self.pulled) try self.pull() else if (self.refresh_on_miss) try self.refresh();
        }
        const found = self.releases.get(key) orelse return error.UnknownRelease;
        if (reference.object.contains("l")) {
            const pinned = try cidField(self.allocator, reference, "l");
            if (!std.mem.eql(u8, found, pinned)) return error.PinnedReleaseMismatch;
        }
        return found;
    }

    pub fn resolveIR(self: *Cache, reference: J) !J {
        return self.moduleIR(try self.referenceCID(reference));
    }

    /// Modules execute with no host effects. Only content/pinned dependencies
    /// can be fetched while evaluating a module; unpinned imports are invalid.
    pub fn resolve(self: *Cache, caller: *runtime.Engine, reference: J) anyerror!V {
        const cid = self.referenceCID(reference) catch |err| {
            if (err == error.OutOfMemory) return err;
            caller.failure = .{ .undefined_reference = reference };
            return error.Runtime;
        };
        if (self.invalid.contains(cid)) {
            caller.failure = .{ .undefined_reference = reference };
            return error.Runtime;
        }
        if (self.modules.get(cid)) |module| if (module.value) |value| return value;
        if (self.loading.contains(cid) or self.loading.count() >= 128) {
            caller.failure = .{ .undefined_reference = reference };
            return error.Runtime;
        }
        const source = self.moduleIR(cid) catch |err| {
            if (err == error.OutOfMemory) return err;
            caller.failure = .{ .undefined_reference = reference };
            return error.Runtime;
        };
        try self.loading.put(cid, {});
        defer _ = self.loading.remove(cid);
        var engine = runtime.Engine.init(self.allocator);
        engine.inspection_meta = try @import("source.zig").content(self.allocator, cid);
        engine.reference_handler = moduleReference;
        engine.reference_context = self;
        const value = engine.eval(source) catch |err| {
            if (engine.failure) |reason| try self.invalid.put(cid, reason);
            // An invalid cached module is unavailable to its caller. Preserve
            // its inner reason for diagnostics, while matching static_loop's
            // UndefinedReference at the reference that could not be resolved.
            caller.failure = .{ .undefined_reference = reference };
            return err;
        };
        try self.modules.put(cid, .{ .source = source, .value = value });
        return value;
    }
};

test "package picker order follows JavaScript UTF-16 strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var cache = try Cache.init(a, "https://eyg.run");
    const unit_module = try runtime.object(a, &.{.{ "program", try runtime.object(a, &.{.{ "0", .{ .string = "u" } }}) }});
    const packages = try runtime.object(a, &.{
        .{ "\u{e000}", unit_module }, .{ "😀", unit_module }, .{ "\u{10000}", unit_module }, .{ "λ", unit_module },
    });
    try cache.ingestPackages(packages);
    const sorted = try cache.packageList(a);
    for (sorted, [_][]const u8{ "λ", "\u{10000}", "😀", "\u{e000}" }) |entry, expected| try std.testing.expectEqualStrings(expected, entry.name);
}

fn moduleReference(context: ?*anyopaque, engine: *runtime.Engine, reference: J) anyerror!V {
    const self: *Cache = @ptrCast(@alignCast(context.?));
    const code = runtime.stringField(reference, "0") orelse "";
    if (std.mem.eql(u8, code, "#") or (std.mem.eql(u8, code, "@") and runtime.field(reference, "l") != .null)) return self.resolve(engine, reference);
    engine.failure = .{ .undefined_reference = reference };
    return error.Runtime;
}
fn liveGet(_: ?*anyopaque, a: A, url: []const u8) !Response {
    return http.get(a, url);
}
fn normalizeOrigin(a: A, origin: []const u8) ![]const u8 {
    var uri = std.Uri.parse(origin) catch return a.dupe(u8, "https://eyg.run");
    if (uri.host == null or (!std.mem.eql(u8, uri.scheme, "http") and !std.mem.eql(u8, uri.scheme, "https"))) return a.dupe(u8, "https://eyg.run");
    uri.user = null;
    uri.password = null;
    uri.path = .{ .raw = "" };
    uri.query = null;
    uri.fragment = null;
    const formatted = try std.fmt.allocPrint(a, "{}", .{uri});
    return std.mem.trimRight(u8, formatted, "/");
}
fn text(object: J, key: []const u8) ![]const u8 {
    return runtime.stringField(object, key) orelse error.InvalidHubData;
}
fn integer(object: J, key: []const u8) !i64 {
    const value = runtime.field(object, key);
    return if (value == .integer) value.integer else error.InvalidHubData;
}
fn cidField(a: A, object: J, key: []const u8) ![]const u8 {
    return codec.canonicalCid(a, try text(runtime.field(object, key), "/"));
}
fn publisherRelease(a: A, payload: J, cursor: i64) !Package {
    _ = try integer(payload, "sequence");
    _ = try cidField(a, payload, "signatory");
    _ = try text(payload, "key");
    const previous = runtime.field(payload, "previous");
    if (payload != .object or !payload.object.contains("previous")) return error.InvalidHubData;
    if (previous != .null) _ = try cidField(a, payload, "previous");
    if (!std.mem.eql(u8, try text(payload, "type"), "release")) return error.InvalidHubData;
    const content = runtime.field(payload, "content");
    return .{ .name = try text(content, "package"), .version = try integer(content, "version"), .cid = try cidField(a, content, "module"), .cursor = cursor };
}

pub fn canonicalTree(a: A, ir: J) anyerror!J {
    if (!runtime.validIr(ir)) return error.InvalidIR;
    return normalizeTree(a, ir);
}
fn normalizeTree(a: A, ir: J) anyerror!J {
    const code = runtime.stringField(ir, "0").?;
    var output = try runtime.object(a, &.{.{ "0", .{ .string = code } }});
    if (std.mem.eql(u8, code, "a")) {
        try output.object.put("f", try normalizeTree(a, runtime.field(ir, "f")));
        try output.object.put("a", try normalizeTree(a, runtime.field(ir, "a")));
    } else if (std.mem.eql(u8, code, "f") or std.mem.eql(u8, code, "l")) {
        try output.object.put("l", runtime.field(ir, "l"));
        if (std.mem.eql(u8, code, "f")) try output.object.put("b", try normalizeTree(a, runtime.field(ir, "b"))) else {
            try output.object.put("v", try normalizeTree(a, runtime.field(ir, "v")));
            try output.object.put("t", try normalizeTree(a, runtime.field(ir, "t")));
        }
    } else if (std.mem.eql(u8, code, "i")) {
        try output.object.put("v", .{ .integer = @intFromFloat(codec.jsonInteger(runtime.field(ir, "v")).?) });
    } else if (std.mem.eql(u8, code, "s")) {
        try output.object.put("v", runtime.field(ir, "v"));
    } else if (std.mem.eql(u8, code, "x")) {
        try output.object.put("v", try runtime.encodeBytes(a, try runtime.decodeBytes(a, runtime.field(ir, "v"))));
    } else if (std.mem.eql(u8, code, "@")) {
        try output.object.put("p", runtime.field(ir, "p"));
        if (ir.object.contains("r")) {
            const version = codec.jsonInteger(runtime.field(ir, "r")).?;
            try output.object.put("r", if (version >= -9007199254740991 and version <= 9007199254740991) .{ .integer = @intFromFloat(version) } else .{ .float = version });
        }
        if (ir.object.contains("l")) try output.object.put("l", try runtime.object(a, &.{.{ "/", .{ .string = try cidField(a, ir, "l") } }}));
    } else if (std.mem.eql(u8, code, "#")) {
        try output.object.put("l", try runtime.object(a, &.{.{ "/", .{ .string = try cidField(a, ir, "l") } }}));
    } else if (std.mem.eql(u8, code, ".")) {
        try output.object.put("i", runtime.field(ir, "i"));
    } else if (code.len == 1 and std.mem.indexOfScalar(u8, "veogtmphb", code[0]) != null) {
        try output.object.put("l", runtime.field(ir, "l"));
    }
    return output;
}
fn writeCanonical(a: A, value: J, writer: anytype) anyerror!void {
    if (value == .float) return writer.writeAll(try codec.ecmaNumber(a, value.float));
    if (value != .object) return std.json.stringify(value, .{}, writer);
    const keys = try a.dupe([]const u8, value.object.keys());
    std.mem.sort([]const u8, keys, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    try writer.writeByte('{');
    for (keys, 0..) |key, i| {
        if (i > 0) try writer.writeByte(',');
        try std.json.stringify(key, .{}, writer);
        try writer.writeByte(':');
        try writeCanonical(a, value.object.get(key).?, writer);
    }
    try writer.writeByte('}');
}

pub fn canonicalBytes(a: A, program: J) ![]const u8 {
    var output = std.ArrayList(u8).init(a);
    try writeCanonical(a, try canonicalTree(a, program), output.writer());
    return output.toOwnedSlice();
}
pub fn canonicalCID(a: A, program: J) ![]const u8 {
    const bytes = try canonicalBytes(a, program);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var raw: [37]u8 = undefined;
    raw[0..5].* = .{ 1, 0xa9, 2, 0x12, 0x20 };
    raw[5..].* = digest;
    var result = std.ArrayList(u8).init(a);
    try result.append('b');
    const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    var buffer: u16 = 0;
    var bits: u5 = 0;
    for (raw) |byte| {
        buffer = (buffer << 8) | byte;
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            try result.append(alphabet[(buffer >> @intCast(bits)) & 31]);
        }
        buffer &= (@as(u16, 1) << @intCast(bits)) - 1;
    }
    if (bits > 0) try result.append(alphabet[(buffer << @intCast(5 - bits)) & 31]);
    return result.toOwnedSlice();
}

test "canonical module CID is oracle derived and rejects corrupt bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = (try std.json.parseFromSlice(J, a, "{\"extra\":true,\"v\":42,\"0\":\"i\"}", .{})).value;
    const cid = try canonicalCID(a, program);
    try std.testing.expectEqualStrings("baguqeerav7573zvsbhxirlmt7vqixxn5frippicgputyjumyzekzi2md4usa", cid);
    var cache = try Cache.init(a, "https://eyg.run/ignored?query=1");
    try std.testing.expectEqualStrings("https://eyg.run", cache.origin);
    const large_version = try runtime.object(a, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = "demo" } }, .{ "r", .{ .float = 1e18 } } });
    try std.testing.expectEqualStrings("{\"0\":\"@\",\"p\":\"demo\",\"r\":1000000000000000000}", try canonicalBytes(a, large_version));
    _ = try cache.ingestModule(cid, "{\"v\":42,\"0\":\"i\"}");
    try std.testing.expectError(error.ModuleHashMismatch, cache.ingestModule(cid, "{\"0\":\"i\",\"v\":41}"));
    try cache.addPackage("demo", 1, cid, 2);
    try cache.addPackage("demo", 2, cid, 1);
    try std.testing.expectEqual(@as(i64, 1), (try cache.packageList(a))[0].version);
    const reference = try runtime.object(a, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = "demo" } } });
    var engine = runtime.Engine.init(a);
    try std.testing.expectEqual(@as(i64, 42), (try cache.resolve(&engine, reference)).integer);
}

test "offline hub paginates, refreshes misses, verifies modules and rejects invalid ledger pages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try runtime.object(a, &.{ .{ "0", .{ .string = "i" } }, .{ "v", .{ .integer = 42 } } });
    const cid = try canonicalCID(a, program);
    const link = try runtime.object(a, &.{.{ "/", .{ .string = cid } }});
    const payload = try runtime.object(a, &.{
        .{ "sequence", .{ .integer = 1 } },   .{ "previous", .null },                .{ "signatory", link },
        .{ "key", .{ .string = "fixture" } }, .{ "type", .{ .string = "release" } }, .{ "content", try runtime.object(a, &.{ .{ "package", .{ .string = "demo" } }, .{ "version", .{ .integer = 1 } }, .{ "module", link } }) },
    });
    const entry = try runtime.object(a, &.{
        .{ "cursor", .{ .integer = 5 } },      .{ "sequence", .{ .integer = 1 } },
        .{ "cid", link },                      .{ "entity", link },
        .{ "type", .{ .string = "release" } }, .{ "payload", .{ .string = try std.json.stringifyAlloc(a, payload, .{}) } },
    });
    var entries = std.json.Array.init(a);
    try entries.append(entry);
    const page = try runtime.object(a, &.{.{ "entries", .{ .array = entries } }});
    const Fixture = struct {
        ledger: []const u8,
        module: []const u8,
        cid: []const u8,
        requests: usize = 0,
        next_ledger: ?[]const u8 = null,
        fn get(context: ?*anyopaque, _: A, url: []const u8) !Response {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.requests += 1;
            const body = if (std.mem.endsWith(u8, url, "/packages/pull")) self.ledger else if (std.mem.indexOf(u8, url, "/packages/pull?since=") != null) refresh: {
                const next = self.next_ledger orelse break :refresh "{\"entries\":[]}";
                self.next_ledger = null;
                break :refresh next;
            } else if (std.mem.endsWith(u8, url, self.cid)) self.module else return error.UnexpectedFixtureURL;
            return .{ .status = 200, .headers = &.{}, .body = body };
        }
    };
    var fixture = Fixture{ .ledger = try std.json.stringifyAlloc(a, page, .{}), .module = try canonicalBytes(a, program), .cid = cid };
    var cache = try Cache.init(a, "https://eyg.test");
    cache.transport = Fixture.get;
    cache.transport_context = &fixture;
    const reference = try runtime.object(a, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = "demo" } } });
    var engine = runtime.Engine.init(a);
    try std.testing.expectEqual(@as(i64, 42), (try cache.resolve(&engine, reference)).integer);
    try std.testing.expectEqual(@as(usize, 3), fixture.requests);
    try std.testing.expect(cache.pulled);
    try std.testing.expectEqual(@as(i64, 5), cache.cursor);
    try std.testing.expectEqual(@as(i64, 42), (try cache.resolve(&engine, reference)).integer);
    try std.testing.expectEqual(@as(usize, 3), fixture.requests);

    var invalid_page = page;
    try invalid_page.object.getPtr("entries").?.array.append(try runtime.object(a, &.{.{ "cursor", .{ .string = "bad" } }}));
    var fresh = try Cache.init(a, "https://eyg.test");
    try std.testing.expectError(error.InvalidHubData, fresh.ingestLedger(try std.json.stringifyAlloc(a, invalid_page, .{})));
    try std.testing.expectEqual(@as(i64, 0), fresh.cursor);
    try std.testing.expectEqual(@as(usize, 0), fresh.latest.count());

    // A content dependency resolves through the cache, while the module itself
    // remains unable to run host effects or follow mutable package references.
    const dependent = try runtime.object(a, &.{ .{ "0", .{ .string = "#" } }, .{ "l", link } });
    const dependent_cid = try canonicalCID(a, dependent);
    _ = try cache.ingestModule(dependent_cid, try canonicalBytes(a, dependent));
    const outer = try runtime.object(a, &.{ .{ "0", .{ .string = "#" } }, .{ "l", try runtime.object(a, &.{.{ "/", .{ .string = dependent_cid } }}) } });
    try std.testing.expectEqual(@as(i64, 42), (try cache.resolve(&engine, outer)).integer);
    const impure = try runtime.object(a, &.{ .{ "0", .{ .string = "a" } }, .{ "f", try runtime.object(a, &.{ .{ "0", .{ .string = "p" } }, .{ "l", .{ .string = "Probe" } } }) }, .{ "a", try runtime.object(a, &.{.{ "0", .{ .string = "u" } }}) } });
    const impure_cid = try canonicalCID(a, impure);
    _ = try cache.ingestModule(impure_cid, try canonicalBytes(a, impure));
    const bad_ref = try runtime.object(a, &.{ .{ "0", .{ .string = "#" } }, .{ "l", try runtime.object(a, &.{.{ "/", .{ .string = impure_cid } }}) } });
    try std.testing.expectError(error.Runtime, cache.resolve(&engine, bad_ref));
    try std.testing.expect(engine.failure.? == .undefined_reference);
    try std.testing.expect(cache.invalid.get(impure_cid).? == .unhandled_effect);

    // A new name/version can appear after startup reached an empty page.
    // A miss refreshes once; a known name does not poll on every evaluation.
    var changed_payload = payload;
    try changed_payload.object.getPtr("content").?.object.put("package", .{ .string = "later" });
    try changed_payload.object.getPtr("content").?.object.put("version", .{ .integer = 2 });
    var changed_entry = entry;
    try changed_entry.object.put("cursor", .{ .integer = 6 });
    try changed_entry.object.put("payload", .{ .string = try std.json.stringifyAlloc(a, changed_payload, .{}) });
    var changed_entries = std.json.Array.init(a);
    try changed_entries.append(changed_entry);
    const changed_page = try runtime.object(a, &.{.{ "entries", .{ .array = changed_entries } }});
    fixture.next_ledger = try std.json.stringifyAlloc(a, changed_page, .{});
    const later = try runtime.object(a, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = "later" } } });
    try std.testing.expectEqual(@as(i64, 42), (try cache.resolve(&engine, later)).integer);
    try std.testing.expectEqual(@as(usize, 5), fixture.requests);
    _ = try cache.resolve(&engine, reference);
    try std.testing.expectEqual(@as(usize, 5), fixture.requests);

    try changed_payload.object.getPtr("content").?.object.put("package", .{ .string = "demo" });
    try changed_entry.object.put("cursor", .{ .integer = 7 });
    try changed_entry.object.put("payload", .{ .string = try std.json.stringifyAlloc(a, changed_payload, .{}) });
    changed_entries.items[0] = changed_entry;
    fixture.next_ledger = try std.json.stringifyAlloc(a, changed_page, .{});
    const later_version = try runtime.object(a, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = "demo" } }, .{ "r", .{ .integer = 2 } } });
    try std.testing.expectEqual(@as(i64, 42), (try cache.resolve(&engine, later_version)).integer);
    try std.testing.expectEqual(@as(usize, 7), fixture.requests);
    try std.testing.expectEqual(@as(i64, 2), (try cache.packageList(a))[0].version);

    var seeded = try Cache.init(a, "https://eyg.test");
    seeded.transport = Fixture.get;
    seeded.transport_context = &fixture;
    const fixtures = try runtime.object(a, &.{.{ "demo", try runtime.object(a, &.{.{ "program", program }}) }});
    try seeded.ingestPackages(fixtures);
    try std.testing.expect(!seeded.refresh_on_miss);
    try std.testing.expectError(error.UnknownPackage, seeded.referenceCID(try runtime.object(a, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = "missing" } } })));
    try std.testing.expectEqual(@as(usize, 7), fixture.requests);
}
