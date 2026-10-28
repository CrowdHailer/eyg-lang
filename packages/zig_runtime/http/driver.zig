//! Test-only direct Fetch transport, separate from the effect router.
const std = @import("std");
const http = @import("http");

const J = std.json.Value;
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try std.process.argsAlloc(a);
    if (args.len == 3 and std.mem.eql(u8, args[1], "--ca-directory")) {
        var bundle = std.crypto.Certificate.Bundle{};
        defer bundle.deinit(a);
        try http.addCertificatesFromDirectory(&bundle, a, args[2]);
        try std.io.getStdOut().writer().print("{d}\n", .{bundle.map.count()});
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "--get")) {
        const response = try http.get(a, args[2]);
        try std.json.stringify(response, .{}, std.io.getStdOut().writer());
        try std.io.getStdOut().writeAll("\n");
        return;
    }
    const bytes = try std.io.getStdIn().readToEndAlloc(a, 4 * 1024 * 1024);
    const input = try std.json.parseFromSlice(J, a, bytes, .{ .allocate = .alloc_always });
    var engine = http.Engine.init(a);
    const lift = try engine.fromJson(input.value);
    const result = try http.effect(&engine, lift);
    const json = try engine.toJson(result);
    try std.json.stringify(json, .{}, std.io.getStdOut().writer());
    try std.io.getStdOut().writeAll("\n");
}
