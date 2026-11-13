const std = @import("std");
const core = @import("eyg_native");
const inference = core.inference;
const runtime = core.interpreter;
const J = std.json.Value;
pub fn main() !void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader());
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try reader.reader().readUntilDelimiterOrEofAlloc(a, '\n', 16 * 1024 * 1024) orelse break;
        const input = try std.json.parseFromSlice(J, a, line, .{});
        var engine = runtime.Engine.init(a);
        const scope = runtime.field(input.value, "scope");
        if (scope == .array) for (scope.array.items) |b| {
            const value = try engine.eval(runtime.field(b, "program"));
            try engine.bind(runtime.stringField(b, "name").?, value);
        };
        const result = try inference.analyze(a, runtime.field(input.value, "program"), engine.scope);
        var map = std.json.ObjectMap.init(a);
        try map.put("root_type", .{ .string = result.root_type });
        try map.put("error_count", .{ .integer = @intCast(result.error_count) });
        try map.put("loading_count", .{ .integer = @intCast(result.loading_count) });
        var info = std.json.ObjectMap.init(a);
        var it = result.info.iterator();
        while (it.next()) |entry| {
            var fields = std.json.ObjectMap.init(a);
            try fields.put("type", .{ .string = entry.value_ptr.type_text });
            try fields.put("problem", if (entry.value_ptr.problem) |p| .{ .string = p } else .null);
            try fields.put("effect", .{ .string = entry.value_ptr.effect_text });
            try info.put(try std.fmt.allocPrint(a, "{d}", .{entry.key_ptr.*}), .{ .object = fields });
        }
        try map.put("info", .{ .object = info });
        try std.json.stringify(J{ .object = map }, .{}, std.io.getStdOut().writer());
        try std.io.getStdOut().writeAll("\n");
    }
}
