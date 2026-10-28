//! Local immutable object writes and cooperative compare-and-swap branch refs.
//! No working tree/index mutations; all paths are repository-local.
const std = @import("std");
const git = @import("git.zig");
const A = std.mem.Allocator;
const J = std.json.Value;

pub fn handles(action: []const u8) bool {
    for ([_][]const u8{ "init", "write_object", "write_blob", "write_tree", "commit_tree", "update_ref", "create_branch", "snapshot_tree", "commit_snapshot" }) |known|
        if (std.mem.eql(u8, known, action)) return true;
    return false;
}

pub fn request(a: A, input: J) !J {
    const action = try text(input, "action", "");
    const root = try text(input, "repo", ".");
    if (std.mem.eql(u8, action, "init")) return .{ .string = try initialize(a, root, try text(input, "branch", "main")) };
    var repo = try git.Repository.init(a, root);
    if (std.mem.eql(u8, action, "write_blob") or std.mem.eql(u8, action, "write_object")) {
        const kind = if (std.mem.eql(u8, action, "write_blob")) "blob" else try text(input, "kind", "blob");
        return .{ .string = try writeObject(&repo, kind, try contents(a, input)) };
    }
    if (std.mem.eql(u8, action, "write_tree")) return .{ .string = try writeTree(&repo, get(input, "entries") orelse return error.InvalidRequest) };
    if (std.mem.eql(u8, action, "commit_tree")) return .{ .string = try commitTree(&repo, input) };
    if (std.mem.eql(u8, action, "snapshot_tree")) return .{ .string = try snapshotTree(&repo, get(input, "files") orelse return error.InvalidRequest) };
    if (std.mem.eql(u8, action, "update_ref") or std.mem.eql(u8, action, "create_branch")) {
        const ref = if (std.mem.eql(u8, action, "create_branch")) try std.fmt.allocPrint(a, "refs/heads/{s}", .{try text(input, "name", "")}) else try text(input, "ref", "");
        const id = try text(input, "id", "");
        const expected = if (std.mem.eql(u8, action, "create_branch")) null else get(input, "expected");
        try updateRef(&repo, ref, expected, id);
        return .{ .string = id };
    }
    if (std.mem.eql(u8, action, "commit_snapshot")) {
        var options = input;
        const tree_id = try snapshotTree(&repo, get(input, "files") orelse return error.InvalidRequest);
        try options.object.put("tree", .{ .string = tree_id });
        const expected = get(input, "expected");
        if (get(input, "parents") == null) {
            var parents = std.json.Array.init(a);
            if (expected) |old| if (old == .string) {
                try parents.append(old);
            };
            try options.object.put("parents", .{ .array = parents });
        }
        const id = try commitTree(&repo, options);
        try updateRef(&repo, try text(input, "ref", "refs/heads/main"), expected, id);
        var out = std.json.ObjectMap.init(a);
        try out.put("id", .{ .string = id });
        try out.put("tree", .{ .string = tree_id });
        return .{ .object = out };
    }
    return error.UnknownGitAction;
}

fn initialize(a: A, root: []const u8, branch: []const u8) ![]const u8 {
    const ref = try std.fmt.allocPrint(a, "refs/heads/{s}", .{branch});
    try validRef(ref);
    const abs = try std.fs.path.resolve(a, &.{root});
    const dotgit = try std.fs.path.join(a, &.{ abs, ".git" });
    try std.fs.cwd().makePath(dotgit);
    var dir = try std.fs.openDirAbsolute(dotgit, .{});
    defer dir.close();
    // Initialization refuses any existing configuration or HEAD.
    if (dir.access("HEAD", .{})) |_| return error.RepositoryExists else |err| if (err != error.FileNotFound) return err;
    if (dir.access("config", .{})) |_| return error.RepositoryExists else |err| if (err != error.FileNotFound) return err;
    try dir.makePath("objects/pack");
    try dir.makePath("refs/heads");
    var config = try dir.createFile("config", .{ .exclusive = true });
    defer config.close();
    try config.writeAll("[core]\n\trepositoryformatversion = 0\n\tbare = false\n\tfilemode = true\n");
    try config.sync();
    var head = try dir.createFile("HEAD", .{ .exclusive = true });
    defer head.close();
    try head.writer().print("ref: {s}\n", .{ref});
    try head.sync();
    return abs;
}

pub fn writeObject(repo: *git.Repository, kind: []const u8, bytes: []const u8) ![]const u8 {
    if (!std.mem.eql(u8, kind, "blob") and !std.mem.eql(u8, kind, "tree") and !std.mem.eql(u8, kind, "commit") and !std.mem.eql(u8, kind, "tag")) return error.InvalidObjectKind;
    if (bytes.len > 64 * 1024 * 1024) return error.ObjectTooLarge;
    const a = repo.allocator;
    var raw = std.ArrayList(u8).init(a);
    try raw.writer().print("{s} {d}\x00", .{ kind, bytes.len });
    try raw.appendSlice(bytes);
    const id = try git.sha1Hex(a, raw.items);
    const directory = try std.fs.path.join(a, &.{ repo.common, "objects", id[0..2] });
    try std.fs.cwd().makePath(directory);
    var dir = try std.fs.openDirAbsolute(directory, .{});
    defer dir.close();
    if (dir.access(id[2..], .{})) |_| {
        // Never replace an existing corrupt immutable object.
        _ = try repo.object(id);
        return id;
    } else |err| if (err != error.FileNotFound) return err;
    const temp = try std.fmt.allocPrint(a, "tmp_obj_{x}", .{std.crypto.random.int(u64)});
    var file = try dir.createFile(temp, .{ .exclusive = true, .mode = 0o444 });
    defer file.close();
    defer dir.deleteFile(temp) catch {};
    var source = std.io.fixedBufferStream(raw.items);
    try std.compress.zlib.compress(source.reader(), file.writer(), .{ .level = .fast });
    try file.sync();
    // Both sides of a race publish the same content-addressed immutable bytes.
    try dir.rename(temp, id[2..]);
    return id;
}

const TreeEntry = struct { name: []const u8, key: []const u8, mode: []const u8, id: []const u8 };
fn writeTree(repo: *git.Repository, items: J) ![]const u8 {
    if (items != .array) return error.InvalidRequest;
    const a = repo.allocator;
    var entries = std.ArrayList(TreeEntry).init(a);
    for (items.array.items) |item| {
        const name = try text(item, "name", "");
        try validName(name);
        const mode = try text(item, "mode", "100644");
        if (!validMode(mode, true)) return error.InvalidMode;
        const id = try text(item, "id", "");
        try validOid(id);
        // Gitlinks point into another repository and need not be locally present.
        if (!std.mem.eql(u8, mode, "160000")) {
            const object = try repo.object(id);
            const expected = if (std.mem.eql(u8, mode, "40000")) "tree" else "blob";
            if (!std.mem.eql(u8, object.kind, expected)) return error.InvalidTreeTarget;
        }
        try entries.append(.{ .name = name, .mode = mode, .id = id, .key = if (std.mem.eql(u8, mode, "40000")) try std.fmt.allocPrint(a, "{s}/", .{name}) else name });
    }
    std.mem.sort(TreeEntry, entries.items, {}, struct {
        fn less(_: void, lhs: TreeEntry, rhs: TreeEntry) bool {
            return std.mem.lessThan(u8, lhs.key, rhs.key);
        }
    }.less);
    var raw = std.ArrayList(u8).init(a);
    var seen = std.StringHashMap(void).init(a);
    for (entries.items) |entry| {
        if (seen.contains(entry.name)) return error.DuplicatePath;
        try seen.put(entry.name, {});
        try raw.writer().print("{s} {s}\x00", .{ entry.mode, entry.name });
        var hash: [20]u8 = undefined;
        _ = try std.fmt.hexToBytes(&hash, entry.id);
        try raw.appendSlice(&hash);
    }
    return writeObject(repo, "tree", raw.items);
}

fn commitTree(repo: *git.Repository, options: J) ![]const u8 {
    const a = repo.allocator;
    const tree_id = try text(options, "tree", "");
    const tree = try repo.object(tree_id);
    if (!std.mem.eql(u8, tree.kind, "tree")) return error.ExpectedTree;
    const parents: J = get(options, "parents") orelse .{ .array = std.json.Array.init(a) };
    if (parents != .array) return error.InvalidRequest;
    var raw = std.ArrayList(u8).init(a);
    try raw.writer().print("tree {s}\n", .{tree_id});
    for (parents.array.items) |parent| {
        if (parent != .string) return error.InvalidRequest;
        const object = try repo.object(parent.string);
        if (!std.mem.eql(u8, object.kind, "commit")) return error.ExpectedCommit;
        try raw.writer().print("parent {s}\n", .{parent.string});
    }
    const author = try identity(a, get(options, "author") orelse return error.InvalidIdentity);
    const committer = try identity(a, get(options, "committer") orelse return error.InvalidIdentity);
    const message = try text(options, "message", "");
    if (std.mem.indexOfScalar(u8, message, 0) != null) return error.InvalidCommit;
    try raw.writer().print("author {s}\ncommitter {s}\n\n{s}", .{ author, committer, message });
    if (message.len == 0 or message[message.len - 1] != '\n') try raw.append('\n');
    return writeObject(repo, "commit", raw.items);
}

fn identity(a: A, input: J) ![]const u8 {
    const name = try text(input, "name", "");
    const email = try text(input, "email", "");
    const timestamp = get(input, "timestamp") orelse return error.InvalidIdentity;
    const timezone = try text(input, "timezone", "+0000");
    if (name.len == 0 or email.len == 0 or std.mem.indexOfAny(u8, name, "\x00\r\n<>") != null or std.mem.indexOfAny(u8, email, "\x00\r\n<> ") != null or timestamp != .integer) return error.InvalidIdentity;
    if (timezone.len != 5 or (timezone[0] != '+' and timezone[0] != '-')) return error.InvalidIdentity;
    for (timezone[1..]) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidIdentity;
    if (try std.fmt.parseInt(u8, timezone[1..3], 10) > 23 or try std.fmt.parseInt(u8, timezone[3..5], 10) > 59) return error.InvalidIdentity;
    return std.fmt.allocPrint(a, "{s} <{s}> {d} {s}", .{ name, email, timestamp.integer, timezone });
}

fn updateRef(repo: *git.Repository, ref: []const u8, expected: ?J, id: []const u8) !void {
    try validRef(ref);
    try validOid(id);
    const object = try repo.object(id);
    if (!std.mem.eql(u8, object.kind, "commit")) return error.ExpectedCommit;
    const a = repo.allocator;
    const packed_lock_path = try std.fs.path.join(a, &.{ repo.common, "packed-refs.lock" });
    var packed_lock = try std.fs.createFileAbsolute(packed_lock_path, .{ .exclusive = true });
    defer packed_lock.close();
    defer std.fs.deleteFileAbsolute(packed_lock_path) catch {};
    const path = try std.fs.path.join(a, &.{ repo.common, ref });
    try std.fs.cwd().makePath(std.fs.path.dirname(path).?);
    const lock_path = try std.fmt.allocPrint(a, "{s}.lock", .{path});
    var lock = try std.fs.createFileAbsolute(lock_path, .{ .exclusive = true });
    defer lock.close();
    defer std.fs.deleteFileAbsolute(lock_path) catch {};
    // Branch refs must be direct. Updating symbolic branch refs would require
    // locking the complete chain to avoid a race with a retargeting writer.
    if (std.fs.openFileAbsolute(path, .{})) |file| {
        defer file.close();
        var prefix: [5]u8 = undefined;
        if (try file.readAll(&prefix) == 5 and std.mem.eql(u8, &prefix, "ref: ")) return error.SymbolicWriteRef;
    } else |err| if (err != error.FileNotFound) return err;
    const previous: ?[]const u8 = repo.resolve(ref) catch |err| blk: {
        if (err != error.UnknownReference and err != error.FileNotFound) return err;
        break :blk null;
    };
    const wanted: ?[]const u8 = if (expected) |value| switch (value) {
        .null => null,
        .string => value.string,
        else => return error.InvalidRequest,
    } else null;
    if (wanted) |old| {
        try validOid(old);
        if (previous == null or !std.mem.eql(u8, previous.?, old)) return error.StaleReference;
    } else if (previous != null) return error.StaleReference;
    try lock.writer().print("{s}\n", .{id});
    try lock.sync();
    try std.fs.renameAbsolute(lock_path, path);
}

const Snapshot = struct { files: std.ArrayList(J), children: std.StringHashMap(*Snapshot) };
fn snapshotTree(repo: *git.Repository, files: J) ![]const u8 {
    if (files != .array) return error.InvalidRequest;
    var root = Snapshot{ .files = std.ArrayList(J).init(repo.allocator), .children = std.StringHashMap(*Snapshot).init(repo.allocator) };
    for (files.array.items) |file| {
        const path = try text(file, "path", "");
        var parts = std.mem.splitScalar(u8, path, '/');
        var node = &root;
        var part = parts.next() orelse return error.InvalidPath;
        while (parts.next()) |next| {
            try validName(part);
            const entry = try node.children.getOrPut(part);
            if (!entry.found_existing) {
                const child = try repo.allocator.create(Snapshot);
                child.* = .{ .files = std.ArrayList(J).init(repo.allocator), .children = std.StringHashMap(*Snapshot).init(repo.allocator) };
                entry.value_ptr.* = child;
            }
            node = entry.value_ptr.*;
            part = next;
        }
        try validName(part);
        const mode = try text(file, "mode", "100644");
        if (!validMode(mode, false)) return error.InvalidMode;
        const id = try writeObject(repo, "blob", try contents(repo.allocator, file));
        var object = std.json.ObjectMap.init(repo.allocator);
        try object.put("name", .{ .string = part });
        try object.put("mode", .{ .string = mode });
        try object.put("id", .{ .string = id });
        try node.files.append(.{ .object = object });
    }
    return snapshotNode(repo, &root);
}
fn snapshotNode(repo: *git.Repository, node: *Snapshot) anyerror![]const u8 {
    var entries = node.files;
    var iter = node.children.iterator();
    while (iter.next()) |child| {
        const id = try snapshotNode(repo, child.value_ptr.*);
        var object = std.json.ObjectMap.init(repo.allocator);
        try object.put("name", .{ .string = child.key_ptr.* });
        try object.put("mode", .{ .string = "40000" });
        try object.put("id", .{ .string = id });
        try entries.append(.{ .object = object });
    }
    return writeTree(repo, .{ .array = entries });
}

fn validName(name: []const u8) !void {
    if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or std.ascii.eqlIgnoreCase(name, ".git") or std.mem.indexOfAny(u8, name, "/\x00") != null) return error.InvalidPath;
}
fn validMode(mode: []const u8, tree: bool) bool {
    for ([_][]const u8{ "100644", "100755", "120000" }) |candidate| if (std.mem.eql(u8, candidate, mode)) return true;
    return tree and (std.mem.eql(u8, mode, "40000") or std.mem.eql(u8, mode, "160000"));
}
fn validRef(ref: []const u8) !void {
    if (!std.mem.startsWith(u8, ref, "refs/heads/") or ref.len <= 11 or ref[ref.len - 1] == '.' or std.mem.indexOfAny(u8, ref, " ~^:?*[\\\x00\r\n\t") != null or std.mem.indexOf(u8, ref, "..") != null or std.mem.indexOf(u8, ref, "@{") != null) return error.InvalidReference;
    var parts = std.mem.splitScalar(u8, ref, '/');
    while (parts.next()) |part| if (part.len == 0 or part[0] == '.' or std.mem.endsWith(u8, part, ".lock")) return error.InvalidReference;
}
fn validOid(id: []const u8) !void {
    if (id.len != 40) return error.InvalidObjectId;
    for (id) |digit| if (!std.ascii.isHex(digit)) return error.InvalidObjectId;
}
fn get(input: J, key: []const u8) ?J {
    return if (input == .object) input.object.get(key) else null;
}
fn text(input: J, key: []const u8, default: []const u8) ![]const u8 {
    const value = get(input, key) orelse return default;
    if (value != .string) return error.InvalidRequest;
    return value.string;
}
fn contents(a: A, input: J) ![]const u8 {
    if (get(input, "text")) |value| {
        if (value != .string) return error.InvalidRequest;
        return value.string;
    }
    if (get(input, "contents")) |value| {
        if (value != .string) return error.InvalidRequest;
        return value.string;
    }
    const value = try text(input, "bytes", "");
    const decoder = std.base64.standard.Decoder;
    const bytes = try a.alloc(u8, try decoder.calcSizeForSlice(value));
    try decoder.decode(bytes, value);
    return bytes;
}
