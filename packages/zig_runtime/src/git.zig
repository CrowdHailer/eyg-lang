//! Native Git object plumbing. Git is used only by the independent verifier.
//! All allocations belong to the caller; use one arena per request or session.
const std = @import("std");
const Allocator = std.mem.Allocator;
const J = std.json.Value;
const max_object = 64 * 1024 * 1024;
const max_index = 128 * 1024 * 1024;
const max_delta_depth = 64;

pub const Object = struct { kind: []const u8, bytes: []const u8 };
const Index = struct { path: []const u8, bytes: []const u8, count: usize };
pub const Commit = struct {
    id: []const u8,
    tree: []const u8,
    parents: []const []const u8,
    author: []const u8,
    committer: []const u8,
    subject: []const u8,
    message: []const u8,
    timestamp: i64,
};
pub const Entry = struct { name: []const u8, mode: []const u8, kind: []const u8, id: []const u8 };

pub const Repository = struct {
    allocator: Allocator,
    root: []const u8,
    gitdir: []const u8,
    common: []const u8,
    indexes: std.ArrayList(Index),
    indexed: bool = false,
    cache: std.StringHashMap(Object),
    cache_bytes: usize = 0,

    pub fn init(a: Allocator, root: []const u8) !Repository {
        const abs = try std.fs.path.resolve(a, &.{root});
        const dotgit = try std.fs.path.join(a, &.{ abs, ".git" });
        const gitdir = blk: {
            var dir = std.fs.openDirAbsolute(dotgit, .{}) catch {
                const marker = readFile(a, dotgit, 16 * 1024) catch {
                    // Bare repositories are accepted as well as ordinary checkouts.
                    const head_path = try std.fs.path.join(a, &.{ abs, "HEAD" });
                    std.fs.accessAbsolute(head_path, .{}) catch return error.NotRepository;
                    break :blk abs;
                };
                if (!std.mem.startsWith(u8, marker, "gitdir: ")) return error.NotRepository;
                break :blk try std.fs.path.resolve(a, &.{ abs, std.mem.trim(u8, marker[8..], "\r\n ") });
            };
            dir.close();
            break :blk dotgit;
        };
        const common_path = try std.fs.path.join(a, &.{ gitdir, "commondir" });
        const common = if (readFile(a, common_path, 16 * 1024)) |marker|
            try std.fs.path.resolve(a, &.{ gitdir, std.mem.trim(u8, marker, "\r\n ") })
        else |_|
            gitdir;
        // SHA-256 object formats need a distinct index and tree decoder.
        const config = readFile(a, try std.fs.path.join(a, &.{ common, "config" }), 4 * 1024 * 1024) catch "";
        if (std.mem.indexOf(u8, config, "objectformat = sha256") != null or std.mem.indexOf(u8, config, "objectFormat = sha256") != null)
            return error.UnsupportedObjectFormat;
        return .{ .allocator = a, .root = abs, .gitdir = gitdir, .common = common, .indexes = std.ArrayList(Index).init(a), .cache = std.StringHashMap(Object).init(a) };
    }

    fn join(self: *Repository, pieces: []const []const u8) ![]const u8 {
        return std.fs.path.join(self.allocator, pieces);
    }

    pub fn head(self: *Repository) !J {
        const bytes = try readFile(self.allocator, try self.join(&.{ self.gitdir, "HEAD" }), 4096);
        const value = std.mem.trim(u8, bytes, "\r\n ");
        const branch = if (std.mem.startsWith(u8, value, "ref: ")) value[5..] else "(detached)";
        return obj(self.allocator, &.{ .{ "branch", str(branch) }, .{ "id", str(try self.resolve("HEAD")) } });
    }

    pub fn resolve(self: *Repository, revision: []const u8) anyerror![]const u8 {
        if (std.mem.indexOfAny(u8, revision, "~^")) |at| {
            var id = try self.resolve(revision[0..at]);
            var cursor = at;
            while (cursor < revision.len) {
                const operator = revision[cursor];
                if (operator != '~' and operator != '^') return error.InvalidRevision;
                cursor += 1;
                const start = cursor;
                while (cursor < revision.len and std.ascii.isDigit(revision[cursor])) : (cursor += 1) {}
                const n = if (cursor == start) 1 else std.fmt.parseInt(usize, revision[start..cursor], 10) catch return error.InvalidRevision;
                if (n > 100000) return error.QueryLimit;
                if (operator == '^') {
                    if (n == 0) continue;
                    const c = try self.commit(id);
                    if (n > c.parents.len) return error.NoParent;
                    id = c.parents[n - 1];
                } else {
                    for (0..n) |_| {
                        const c = try self.commit(id);
                        if (c.parents.len == 0) return error.NoParent;
                        id = c.parents[0];
                    }
                }
            }
            return id;
        }
        if (isOid(revision)) return std.ascii.allocLowerString(self.allocator, revision);
        if (revision.len == 0 or std.mem.indexOf(u8, revision, "..") != null or std.fs.path.isAbsolute(revision) or std.mem.indexOfScalar(u8, revision, '\\') != null)
            return error.InvalidReference;
        const names: []const []const u8 = if (std.mem.eql(u8, revision, "HEAD") or std.mem.startsWith(u8, revision, "refs/")) &.{revision} else &.{ revision, try std.fmt.allocPrint(self.allocator, "refs/heads/{s}", .{revision}), try std.fmt.allocPrint(self.allocator, "refs/tags/{s}", .{revision}) };
        for (names) |name| {
            if (self.resolveRef(name, 0)) |id| return id else |err| switch (err) {
                error.FileNotFound, error.UnknownReference => {},
                else => return err,
            }
        }
        return error.UnknownReference;
    }

    fn resolveRef(self: *Repository, ref: []const u8, depth: usize) anyerror![]const u8 {
        if (depth >= 16) return error.ReferenceCycle;
        if (ref.len == 0 or std.mem.indexOf(u8, ref, "..") != null or std.fs.path.isAbsolute(ref)) return error.InvalidReference;
        const path = try self.join(&.{ if (std.mem.eql(u8, ref, "HEAD")) self.gitdir else self.common, ref });
        if (readFile(self.allocator, path, 4096)) |bytes| {
            const value = std.mem.trim(u8, bytes, "\r\n ");
            if (std.mem.startsWith(u8, value, "ref: ")) return self.resolveRef(value[5..], depth + 1);
            if (!isOid(value)) return error.InvalidReference;
            return std.ascii.allocLowerString(self.allocator, value);
        } else |err| {
            if (err != error.FileNotFound) return err;
        }
        const packed_path = try self.join(&.{ self.common, "packed-refs" });
        const packed_refs = readFile(self.allocator, packed_path, 32 * 1024 * 1024) catch |err| {
            if (err == error.FileNotFound) return error.UnknownReference;
            return err;
        };
        var lines = std.mem.splitScalar(u8, packed_refs, '\n');
        while (lines.next()) |line| {
            if (line.len >= 42 and line[40] == ' ' and std.mem.eql(u8, std.mem.trimRight(u8, line[41..], "\r"), ref)) {
                if (!isOid(line[0..40])) return error.InvalidReference;
                return self.allocator.dupe(u8, line[0..40]);
            }
        }
        return error.UnknownReference;
    }

    fn loadIndexes(self: *Repository) !void {
        if (self.indexed) return;
        self.indexed = true;
        const path = try self.join(&.{ self.common, "objects", "pack" });
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer dir.close();
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".idx")) continue;
            const idx_path = try self.join(&.{ path, entry.name });
            const bytes = try readFile(self.allocator, idx_path, max_index);
            if (bytes.len < 1072 or !std.mem.eql(u8, bytes[0..8], "\xfftOc\x00\x00\x00\x02")) return error.UnsupportedPackIndex;
            const n = be32(bytes[1028..1032]);
            const minimum = std.math.mul(usize, n, 28) catch return error.InvalidPackIndex;
            if (minimum > bytes.len - 1072) return error.InvalidPackIndex;
            // The checksum covers fanout, names, CRCs, offsets and pack identity.
            const digest = sha1(bytes[0 .. bytes.len - 20]);
            if (!std.mem.eql(u8, &digest, bytes[bytes.len - 20 ..])) return error.IndexChecksum;
            var previous: u32 = 0;
            for (0..256) |i| {
                const fan = be32(bytes[8 + i * 4 ..][0..4]);
                if (fan < previous or fan > n) return error.InvalidPackIndex;
                previous = fan;
            }
            const pack_path = try std.fmt.allocPrint(self.allocator, "{s}.pack", .{idx_path[0 .. idx_path.len - 4]});
            try self.indexes.append(.{ .path = pack_path, .bytes = bytes, .count = n });
        }
    }

    fn locate(self: *Repository, id: []const u8) !struct { path: []const u8, offset: u64 } {
        try self.loadIndexes();
        const hash = try parseOid(id);
        for (self.indexes.items) |idx| {
            const bucket = hash[0];
            var low: usize = if (bucket == 0) 0 else be32(idx.bytes[8 + (@as(usize, bucket) - 1) * 4 ..][0..4]);
            var high: usize = be32(idx.bytes[8 + @as(usize, bucket) * 4 ..][0..4]);
            while (low < high) {
                const mid = low + (high - low) / 2;
                const candidate = idx.bytes[1032 + mid * 20 ..][0..20];
                switch (std.mem.order(u8, candidate, &hash)) {
                    .lt => low = mid + 1,
                    .gt => high = mid,
                    .eq => {
                        const word = be32(idx.bytes[1032 + idx.count * 24 + mid * 4 ..][0..4]);
                        var offset: u64 = word;
                        if (word & 0x80000000 != 0) {
                            const index: usize = word & 0x7fffffff;
                            const start = 1032 + idx.count * 28 + index * 8;
                            if (start + 8 > idx.bytes.len - 40) return error.InvalidPackIndex;
                            offset = std.mem.readInt(u64, idx.bytes[start..][0..8], .big);
                        }
                        return .{ .path = idx.path, .offset = offset };
                    },
                }
            }
        }
        return error.ObjectNotFound;
    }

    pub fn object(self: *Repository, id: []const u8) anyerror!Object {
        return self.objectDepth(id, 0);
    }

    fn remember(self: *Repository, key: []const u8, value: Object) !void {
        // Budget decoded immutable data; refs and config are always read anew.
        if (self.cache.count() >= 512 or self.cache_bytes + value.bytes.len > 16 * 1024 * 1024) return;
        try self.cache.put(try self.allocator.dupe(u8, key), value);
        self.cache_bytes += value.bytes.len;
    }

    fn objectDepth(self: *Repository, id: []const u8, depth: usize) anyerror!Object {
        if (depth >= max_delta_depth) return error.DeltaDepth;
        if (!isOid(id)) return error.InvalidObjectId;
        if (self.cache.get(id)) |cached| return cached;
        const path = try self.join(&.{ self.common, "objects", id[0..2], id[2..] });
        const value = if (readFile(self.allocator, path, max_object)) |compressed| blk: {
            const raw = try inflate(self.allocator, compressed);
            const nul = std.mem.indexOfScalar(u8, raw, 0) orelse return error.InvalidLooseObject;
            const space = std.mem.indexOfScalar(u8, raw[0..nul], ' ') orelse return error.InvalidLooseObject;
            const kind = raw[0..space];
            if (!isKind(kind)) return error.InvalidObjectKind;
            const size = try std.fmt.parseInt(usize, raw[space + 1 .. nul], 10);
            if (raw.len - nul - 1 != size) return error.ObjectSize;
            break :blk Object{ .kind = kind, .bytes = raw[nul + 1 ..] };
        } else |err| blk: {
            if (err != error.FileNotFound) return err;
            const at = try self.locate(id);
            break :blk try self.packedObject(at.path, at.offset, depth);
        };
        try verifyObject(id, value);
        try self.remember(id, value);
        return value;
    }

    fn packedObject(self: *Repository, path: []const u8, offset: u64, depth: usize) anyerror!Object {
        if (depth >= max_delta_depth) return error.DeltaDepth;
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ path, offset });
        if (self.cache.get(key)) |cached| return cached;
        var file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        var header: [12]u8 = undefined;
        if (try file.preadAll(&header, 0) != 12 or !std.mem.eql(u8, header[0..4], "PACK") or (be32(header[4..8]) != 2 and be32(header[4..8]) != 3)) return error.InvalidPack;
        const stat = try file.stat();
        if (stat.size < 32 or offset < 12 or offset >= stat.size - 20) return error.InvalidPackOffset;
        try file.seekTo(offset);
        var buffered = std.io.bufferedReader(file.reader());
        const reader = buffered.reader();
        var byte = try reader.readByte();
        const kind = (byte >> 4) & 7;
        var size: u64 = byte & 15;
        var shift: u6 = 4;
        while (byte & 128 != 0) {
            if (shift > 60) return error.InvalidPackSize;
            byte = try reader.readByte();
            size |= @as(u64, byte & 127) << shift;
            shift = std.math.add(u6, shift, 7) catch return error.InvalidPackSize;
        }
        if (size > max_object) return error.ObjectTooLarge;
        var base: ?Object = null;
        if (kind == 6) {
            byte = try reader.readByte();
            var distance: u64 = byte & 127;
            var count: usize = 1;
            while (byte & 128 != 0) {
                if (count >= 9) return error.InvalidDelta;
                byte = try reader.readByte();
                distance = std.math.mul(u64, std.math.add(u64, distance, 1) catch return error.InvalidDelta, 128) catch return error.InvalidDelta;
                distance += byte & 127;
                count += 1;
            }
            if (distance == 0 or distance > offset - 12) return error.InvalidDelta;
            base = try self.packedObject(path, offset - distance, depth + 1);
        } else if (kind == 7) {
            const hash = try reader.readBytesNoEof(20);
            const id = std.fmt.bytesToHex(hash, .lower);
            base = try self.objectDepth(&id, depth + 1);
        } else if (kind < 1 or kind > 4) return error.InvalidObjectKind;
        var sink = LimitedOutput.init(self.allocator, @intCast(size));
        try std.compress.zlib.decompress(reader, sink.writer());
        const bytes = try sink.list.toOwnedSlice();
        if (bytes.len != size) return error.ObjectSize;
        const result = if (base) |value| Object{ .kind = value.kind, .bytes = try applyDelta(self.allocator, value.bytes, bytes) } else Object{ .kind = ([_][]const u8{ "", "commit", "tree", "blob", "tag" })[kind], .bytes = bytes };
        try self.remember(key, result);
        return result;
    }

    pub fn commit(self: *Repository, revision: []const u8) anyerror!Commit {
        var id = try self.resolve(revision);
        var value = try self.object(id);
        var tags: usize = 0;
        while (std.mem.eql(u8, value.kind, "tag")) : (tags += 1) {
            if (tags >= 16 or !std.mem.startsWith(u8, value.bytes, "object ") or value.bytes.len < 47) return error.InvalidTag;
            id = value.bytes[7..47];
            value = try self.object(id);
        }
        if (!std.mem.eql(u8, value.kind, "commit")) return error.ExpectedCommit;
        return parseCommit(self.allocator, id, value.bytes);
    }

    pub fn tree(self: *Repository, id: []const u8) ![]Entry {
        const value = try self.object(id);
        if (!std.mem.eql(u8, value.kind, "tree")) return error.ExpectedTree;
        return parseTree(self.allocator, value.bytes);
    }

    fn pathId(self: *Repository, tree_id: []const u8, path: []const u8) !?[]const u8 {
        if (path.len == 0) return tree_id;
        var id = tree_id;
        var pieces = std.mem.splitScalar(u8, path, '/');
        while (pieces.next()) |name| {
            if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return error.InvalidPath;
            const entries = self.tree(id) catch |err| {
                if (err == error.ExpectedTree) return null;
                return err;
            };
            var found: ?[]const u8 = null;
            for (entries) |entry| if (std.mem.eql(u8, entry.name, name)) {
                found = entry.id;
                break;
            };
            id = found orelse return null;
        }
        return id;
    }

    pub fn show(self: *Repository, revision: []const u8, path: []const u8) !Object {
        const c = try self.commit(revision);
        const id = (try self.pathId(c.tree, path)) orelse return error.PathNotFound;
        return self.object(id);
    }
};

pub fn parseCommit(a: Allocator, id: []const u8, bytes: []const u8) !Commit {
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.NonUtf8Metadata;
    const split = std.mem.indexOf(u8, bytes, "\n\n") orelse return error.InvalidCommit;
    var lines = std.mem.splitScalar(u8, bytes[0..split], '\n');
    var parents = std.ArrayList([]const u8).init(a);
    var result = Commit{ .id = id, .tree = "", .parents = &.{}, .author = "", .committer = "", .subject = "", .message = bytes[split + 2 ..], .timestamp = 0 };
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "tree ")) result.tree = line[5..] else if (std.mem.startsWith(u8, line, "parent ")) {
            if (!isOid(line[7..])) return error.InvalidCommit;
            try parents.append(line[7..]);
        } else if (std.mem.startsWith(u8, line, "author ")) result.author = line[7..] else if (std.mem.startsWith(u8, line, "committer ")) result.committer = line[10..];
    }
    if (!isOid(result.tree)) return error.InvalidCommit;
    result.parents = try parents.toOwnedSlice();
    result.subject = if (std.mem.indexOfScalar(u8, result.message, '\n')) |end| result.message[0..end] else result.message;
    if (std.mem.lastIndexOfScalar(u8, result.committer, ' ')) |tz| {
        if (std.mem.lastIndexOfScalar(u8, result.committer[0..tz], ' ')) |at| result.timestamp = std.fmt.parseInt(i64, result.committer[at + 1 .. tz], 10) catch 0;
    }
    return result;
}

pub fn parseTree(a: Allocator, bytes: []const u8) ![]Entry {
    var entries = std.ArrayList(Entry).init(a);
    var at: usize = 0;
    while (at < bytes.len) {
        const space = std.mem.indexOfScalarPos(u8, bytes, at, ' ') orelse return error.InvalidTree;
        const nul = std.mem.indexOfScalarPos(u8, bytes, space + 1, 0) orelse return error.InvalidTree;
        if (nul + 21 > bytes.len) return error.InvalidTree;
        const mode = bytes[at..space];
        const name = bytes[space + 1 .. nul];
        if (!std.unicode.utf8ValidateSlice(name)) return error.NonUtf8Metadata;
        if (mode.len == 0 or name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null) return error.InvalidTree;
        for (mode) |digit| if (digit < '0' or digit > '7') return error.InvalidTree;
        const raw = bytes[nul + 1 ..][0..20].*;
        const hex = std.fmt.bytesToHex(raw, .lower);
        const kind: []const u8 = if (std.mem.eql(u8, mode, "40000") or std.mem.eql(u8, mode, "040000")) "tree" else if (std.mem.eql(u8, mode, "160000")) "commit" else "blob";
        try entries.append(.{ .name = name, .mode = mode, .kind = kind, .id = try a.dupe(u8, &hex) });
        at = nul + 21;
    }
    return entries.toOwnedSlice();
}

pub fn applyDelta(a: Allocator, base: []const u8, bytes: []const u8) ![]const u8 {
    var at: usize = 0;
    const source_size = try deltaSize(bytes, &at);
    const target_size = try deltaSize(bytes, &at);
    if (source_size != base.len) return error.DeltaBaseSize;
    if (target_size > max_object) return error.ObjectTooLarge;
    var result = try std.ArrayList(u8).initCapacity(a, target_size);
    while (at < bytes.len) {
        const op = bytes[at];
        at += 1;
        if (op == 0) return error.InvalidDelta;
        if (op & 128 == 0) {
            if (at + op > bytes.len or result.items.len + op > target_size) return error.InvalidDelta;
            try result.appendSlice(bytes[at .. at + op]);
            at += op;
        } else {
            var offset: usize = 0;
            var size: usize = 0;
            for (0..7) |bit| {
                if (op & (@as(u8, 1) << @as(u3, @intCast(bit))) == 0) continue;
                if (at >= bytes.len) return error.InvalidDelta;
                if (bit < 4) offset |= @as(usize, bytes[at]) << @as(u6, @intCast(bit * 8)) else size |= @as(usize, bytes[at]) << @as(u6, @intCast((bit - 4) * 8));
                at += 1;
            }
            if (size == 0) size = 65536;
            if (offset > base.len or size > base.len - offset or result.items.len + size > target_size) return error.InvalidDelta;
            try result.appendSlice(base[offset .. offset + size]);
        }
    }
    if (result.items.len != target_size) return error.DeltaTargetSize;
    return result.toOwnedSlice();
}

fn deltaSize(bytes: []const u8, at: *usize) !usize {
    var result: usize = 0;
    var shift: u6 = 0;
    while (at.* < bytes.len) {
        const byte = bytes[at.*];
        at.* += 1;
        if (shift > 56) return error.InvalidDelta;
        result |= @as(usize, byte & 127) << shift;
        if (byte & 128 == 0) return result;
        shift += 7;
    }
    return error.InvalidDelta;
}

const LimitedOutput = struct {
    list: std.ArrayList(u8),
    limit: usize,
    fn init(a: Allocator, limit: usize) LimitedOutput {
        return .{ .list = std.ArrayList(u8).init(a), .limit = limit };
    }
    fn write(self: *LimitedOutput, bytes: []const u8) error{ OutOfMemory, ObjectTooLarge }!usize {
        if (bytes.len > self.limit - self.list.items.len) return error.ObjectTooLarge;
        try self.list.appendSlice(bytes);
        return bytes.len;
    }
    fn writer(self: *LimitedOutput) std.io.Writer(*LimitedOutput, error{ OutOfMemory, ObjectTooLarge }, write) {
        return .{ .context = self };
    }
};

pub fn inflate(a: Allocator, compressed: []const u8) ![]const u8 {
    var input = std.io.fixedBufferStream(compressed);
    var output = LimitedOutput.init(a, max_object);
    try std.compress.zlib.decompress(input.reader(), output.writer());
    return output.list.toOwnedSlice();
}

pub fn sha1(bytes: []const u8) [20]u8 {
    var out: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(bytes, &out, .{});
    return out;
}
pub fn sha1Hex(a: Allocator, bytes: []const u8) ![]const u8 {
    const hex = std.fmt.bytesToHex(sha1(bytes), .lower);
    return a.dupe(u8, &hex);
}
fn verifyObject(id: []const u8, value: Object) !void {
    var hash = std.crypto.hash.Sha1.init(.{});
    hash.update(value.kind);
    hash.update(" ");
    var size: [32]u8 = undefined;
    hash.update(try std.fmt.bufPrint(&size, "{d}", .{value.bytes.len}));
    hash.update(&.{0});
    hash.update(value.bytes);
    const digest = hash.finalResult();
    const wanted = try parseOid(id);
    if (!std.mem.eql(u8, &digest, &wanted)) return error.ObjectChecksum;
}
fn parseOid(id: []const u8) ![20]u8 {
    if (!isOid(id)) return error.InvalidObjectId;
    var bytes: [20]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes, id);
    return bytes;
}
fn isOid(id: []const u8) bool {
    if (id.len != 40) return false;
    for (id) |c| if (!std.ascii.isHex(c)) return false;
    return true;
}
fn isKind(kind: []const u8) bool {
    for ([_][]const u8{ "blob", "tree", "commit", "tag" }) |candidate| if (std.mem.eql(u8, kind, candidate)) return true;
    return false;
}
fn be32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .big);
}
fn readFile(a: Allocator, path: []const u8, limit: usize) ![]const u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(a, limit);
}
fn str(value: []const u8) J {
    return .{ .string = value };
}
fn obj(a: Allocator, fields: []const struct { []const u8, J }) !J {
    var map = std.json.ObjectMap.init(a);
    for (fields) |item| try map.put(item[0], item[1]);
    return .{ .object = map };
}
fn field(value: J, key: []const u8) ?J {
    return if (value == .object) value.object.get(key) else null;
}
fn textField(value: J, key: []const u8, default: []const u8) ![]const u8 {
    const v = field(value, key) orelse return default;
    if (v != .string) return error.InvalidRequest;
    return v.string;
}
fn intField(value: J, key: []const u8, default: i64) !i64 {
    const v = field(value, key) orelse return default;
    if (v != .integer) return error.InvalidRequest;
    return v.integer;
}
fn commitJson(a: Allocator, c: Commit) !J {
    var parents = std.json.Array.init(a);
    for (c.parents) |id| try parents.append(str(id));
    return obj(a, &.{ .{ "id", str(c.id) }, .{ "tree", str(c.tree) }, .{ "parents", .{ .array = parents } }, .{ "author", str(c.author) }, .{ "committer", str(c.committer) }, .{ "subject", str(c.subject) }, .{ "message", str(c.message) }, .{ "timestamp", .{ .integer = c.timestamp } } });
}
fn objectJson(a: Allocator, value: Object) !J {
    const encoder = std.base64.standard.Encoder;
    const bytes = try a.alloc(u8, encoder.calcSize(value.bytes.len));
    _ = encoder.encode(bytes, value.bytes);
    var result = try obj(a, &.{ .{ "kind", str(value.kind) }, .{ "bytes", str(bytes) }, .{ "encoding", str("base64") }, .{ "size", .{ .integer = @intCast(value.bytes.len) } } });
    if (std.unicode.utf8ValidateSlice(value.bytes)) try result.object.put("text", str(value.bytes));
    return result;
}
fn treeJson(a: Allocator, entries: []const Entry) !J {
    var result = std.json.Array.init(a);
    for (entries) |entry| try result.append(try obj(a, &.{ .{ "name", str(entry.name) }, .{ "mode", str(entry.mode) }, .{ "kind", str(entry.kind) }, .{ "id", str(entry.id) } }));
    return .{ .array = result };
}

/// Natural JSON request interface shared by CLI protocol and EYG GitQuery effect.
/// History is first-parent; filters do not change traversal order.
pub fn request(a: Allocator, input: J) !J {
    const action = try textField(input, "action", "query");
    if (@import("git_write.zig").handles(action)) return @import("git_write.zig").request(a, input);
    var repo = try Repository.init(a, try textField(input, "repo", "."));
    const revision = try textField(input, "ref", "HEAD");
    if (std.mem.eql(u8, action, "head")) return repo.head();
    if (std.mem.eql(u8, action, "remotes")) return @import("git_config.zig").remotes(a, try std.fs.path.join(a, &.{ repo.common, "config" }));
    if (std.mem.eql(u8, action, "resolve")) return str(try repo.resolve(revision));
    const id = try textField(input, "id", revision);
    if (std.mem.eql(u8, action, "object")) return objectJson(a, try repo.object(try repo.resolve(id)));
    if (std.mem.eql(u8, action, "commit")) return commitJson(a, try repo.commit(id));
    if (std.mem.eql(u8, action, "show")) return objectJson(a, try repo.show(revision, try textField(input, "path", "")));
    if (std.mem.eql(u8, action, "tree")) {
        const resolved = try repo.resolve(id);
        const value = try repo.object(resolved);
        return treeJson(a, try repo.tree(if (std.mem.eql(u8, value.kind, "commit")) (try repo.commit(resolved)).tree else resolved));
    }
    if (std.mem.eql(u8, action, "history") or std.mem.eql(u8, action, "query")) {
        const limit = try intField(input, "limit", 20);
        const scan_limit = try intField(input, "scan_limit", 10000);
        if (limit < 0 or limit > 10000 or scan_limit < 0 or scan_limit > 100000) return error.QueryLimit;
        const contains = try textField(input, "contains", "");
        const author = try textField(input, "author", "");
        const path = try textField(input, "path", "");
        const since = try intField(input, "since", std.math.minInt(i64));
        const until = try intField(input, "until", std.math.maxInt(i64));
        var result = std.json.Array.init(a);
        var next: ?[]const u8 = try repo.resolve(revision);
        var scanned: usize = 0;
        while (next) |current| {
            if (result.items.len >= limit or scanned >= scan_limit) break;
            const c = try repo.commit(current);
            scanned += 1;
            next = if (c.parents.len == 0) null else c.parents[0];
            if (c.timestamp < since or c.timestamp > until or std.mem.indexOf(u8, c.message, contains) == null or std.mem.indexOf(u8, c.author, author) == null) continue;
            if (path.len != 0) {
                const current_id = try repo.pathId(c.tree, path);
                const parent_id = if (next) |parent| try repo.pathId((try repo.commit(parent)).tree, path) else null;
                if (current_id == null and parent_id == null) continue;
                if (current_id != null and parent_id != null and std.mem.eql(u8, current_id.?, parent_id.?)) continue;
            }
            try result.append(try commitJson(a, c));
        }
        return .{ .array = result };
    }
    return error.UnknownGitAction;
}

test "delta reconstruction accepts insert/copy and rejects corrupt ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("hello EYG", try applyDelta(a, "hello", &.{ 5, 9, 0x90, 5, 4, ' ', 'E', 'Y', 'G' }));
    try std.testing.expectError(error.InvalidDelta, applyDelta(a, "hello", &.{ 5, 9, 0 }));
    try std.testing.expectError(error.InvalidDelta, applyDelta(a, "hello", &.{ 5, 9, 0x91, 99, 5 }));
    try std.testing.expectError(error.DeltaBaseSize, applyDelta(a, "hello", &.{ 4, 0 }));
}

test "zlib checks Adler checksum and empty stream" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("", try inflate(arena.allocator(), &.{ 0x78, 0x9c, 3, 0, 0, 0, 0, 1 }));
    try std.testing.expectError(error.WrongZlibChecksum, inflate(arena.allocator(), &.{ 0x78, 0x9c, 3, 0, 0, 0, 0, 2 }));
}
