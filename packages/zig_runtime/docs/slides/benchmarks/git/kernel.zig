const std = @import("std");
const git = @import("git");
pub fn main() !void {
    var input = std.io.bufferedReader(std.io.getStdIn().reader());
    const writer = std.io.getStdOut().writer();
    const body = try std.heap.page_allocator.alloc(u8, 1024 * 1024);
    defer std.heap.page_allocator.free(body);
    const phrase = "let commit = {tree: tree, author: author, message: message}\n";
    for (body, 0..) |*b, i| b.* = phrase[i % phrase.len];
    // Base and target varints encode 1 MiB. Sixty-four 16KiB copies generate the target.
    var delta = std.ArrayList(u8).init(std.heap.page_allocator);
    defer delta.deinit();
    try delta.appendSlice(&.{0x80,0x80,0x40,0x80,0x80,0x40});
    for (0..64) |i| {
        const offset = i * 16384;
        // copy opcode: all three offset bytes and two size bytes.
        try delta.appendSlice(&.{0xb7, @truncate(offset), @truncate(offset >> 8), @truncate(offset >> 16), 0, 0x40});
    }
    while (input.reader().readByte()) |op| {
        if (op == '\n') continue;
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var timer = try std.time.Timer.start();
        var bytes: usize = 0;
        var checksum: [20]u8 = [_]u8{0} ** 20;
        var compressed: ?[]const u8 = null;
        if (op == 'd') {
            const result = try git.applyDelta(a, body, delta.items);
            if (!std.mem.eql(u8, result, body)) return error.IncorrectDelta;
            bytes = result.len;
        } else if (op == 'f' or op == 'c') {
            var source = std.io.fixedBufferStream(body);
            var out = std.ArrayList(u8).init(a);
            try std.compress.zlib.compress(source.reader(), out.writer(), .{.level = if (op == 'f') .fast else .default});
            bytes = out.items.len;
            compressed = out.items;
        } else if (op == 'i') {
            var hash = std.crypto.hash.Sha1.init(.{});
            hash.update("blob 1048576\x00"); hash.update(body);
            checksum = hash.finalResult();
            bytes = checksum[0];
        } else if (op == 'h') {
            var raw = std.ArrayList(u8).init(a);
            try raw.appendSlice("blob 1048576\x00"); try raw.appendSlice(body);
            std.crypto.hash.Sha1.hash(raw.items, &checksum, .{});
            bytes = checksum[0];
        } else return error.BadMode;
        const elapsed = timer.read();
        if (compressed) |encoded| {
            const decoded = try git.inflate(a, encoded);
            if (!std.mem.eql(u8, decoded, body)) return error.IncorrectCompression;
        }
        const hex = std.fmt.bytesToHex(checksum, .lower);
        try writer.print("{{\"duration_ns\":{d},\"bytes\":{d},\"sha1\":\"{s}\",\"validated\":true}}\n", .{elapsed,bytes,if (op == 'i' or op == 'h') hex[0..] else ""});
    } else |err| if (err != error.EndOfStream) return err;
}
