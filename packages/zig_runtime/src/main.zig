//! Native entry point and deterministic JSONL test transport.
const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser.zig");
const interpreter = @import("interpreter.zig");
const tui = @import("tui.zig");
const git = @import("git.zig");
const platform = @import("platform.zig");
const input = @import("input.zig");
const json_wire = @import("json_wire.zig");
const J = std.json.Value;
const A = std.mem.Allocator;
var resize_write_fd: std.posix.fd_t = -1;

fn onResize(_: c_int) callconv(.c) void {
    if (resize_write_fd >= 0) _ = std.posix.write(resize_write_fd, "r") catch {};
}

fn field(value: J, key: []const u8) J {
    return if (value == .object) value.object.get(key) orelse .null else .null;
}
fn str(value: J) []const u8 {
    return if (value == .string) value.string else "";
}
fn number(value: J, default: usize) usize {
    return if (value == .integer and value.integer >= 0) @intCast(value.integer) else default;
}
fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn threadCpuNanoseconds() !u64 {
    const time = try std.posix.clock_gettime(std.posix.CLOCK.THREAD_CPUTIME_ID);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try std.process.argsAlloc(a);
    if (args.len == 1 or equal(args[1], "tui")) return interactive(a);
    if (equal(args[1], "--protocol")) return protocol();
    if (equal(args[1], "--help") or equal(args[1], "-h")) {
        try std.io.getStdOut().writeAll("EYG native runtime\n  eyg [tui]              Interactive structural shell\n  eyg eval -c SOURCE     Evaluate source\n  eyg eval FILE          Evaluate .eyg or canonical JSON IR\n  eyg parse -c SOURCE    Print canonical IR\n  eyg --protocol         Deterministic JSONL test transport\n");
        return;
    }
    if (equal(args[1], "--version")) {
        try std.io.getStdOut().writeAll("eyg-zig 0.1.0 (oracle next-tui be502aa)\n");
        return;
    }
    if (equal(args[1], "eval") or equal(args[1], "run") or equal(args[1], "parse")) {
        if (args.len < 3) return cliError("Expected -c SOURCE or a source file");
        const source = if (equal(args[2], "-c")) blk: {
            if (args.len != 4) return cliError("Expected one source argument after -c");
            break :blk args[3];
        } else try std.fs.cwd().readFileAlloc(a, args[2], 64 * 1024 * 1024);
        if (equal(args[1], "parse")) {
            const ir = if (!equal(args[2], "-c") and std.mem.endsWith(u8, args[2], ".json")) (try std.json.parseFromSlice(J, a, source, .{ .allocate = .alloc_always })).value else parser.parse(a, source) catch |err| return cliError(@errorName(err));
            try printJson(ir);
            return;
        }
        const sources = @import("source.zig");
        const resolved = if (equal(args[2], "-c")) null else try std.fs.path.resolve(a, &.{args[2]});
        const parsed = sources.parse(a, source, if (resolved) |path| .{ .disk = path } else .inline_code) catch |err| return cliError(@errorName(err));
        var engine = interpreter.Engine.init(a);
        var host = platform.Host.init(a);
        if (resolved) |path| host.directory = std.fs.path.dirname(path) orelse ".";
        host.attach(&engine);
        engine.inspection_meta = parsed.meta;
        const value = engine.eval(parsed.program) catch |err| {
            if (engine.failure) |reason| try printJson(try parser.object(a, &.{.{ "break", try engine.reasonJson(reason) }}));
            return cliError(@errorName(err));
        };
        try std.io.getStdOut().writeAll(try engine.inspect(value));
        try std.io.getStdOut().writeAll("\n");
        return;
    }
    return cliError("Unknown command; run eyg --help");
}

fn cliError(message: []const u8) error{CliFailure} {
    std.io.getStdErr().writer().print("eyg: {s}\n", .{message}) catch {};
    return error.CliFailure;
}
fn printJson(value: J) !void {
    var output = std.io.bufferedWriter(std.io.getStdOut().writer());
    try json_wire.write(value, output.writer());
    try output.writer().writeByte('\n');
    try output.flush();
}

fn protocol() !void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader());
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const line = try reader.reader().readUntilDelimiterOrEofAlloc(a, '\n', 128 * 1024 * 1024) orelse break;
        const parsed = std.json.parseFromSlice(J, a, line, .{ .allocate = .alloc_always }) catch |err| {
            try printJson(try parser.object(a, &.{.{ "error", .{ .string = @errorName(err) } }}));
            continue;
        };
        const response = request(a, parsed.value) catch |err| try parser.object(a, &.{.{ "error", .{ .string = @errorName(err) } }});
        try printJson(response);
    }
}

pub fn request(a: A, req: J) !J {
    const op = str(field(req, "op"));
    if (equal(op, "info")) return parser.object(a, &.{
        .{ "zig", .{ .string = builtin.zig_version_string } },
        .{ "mode", .{ .string = @tagName(builtin.mode) } },
        .{ "oracle", .{ .string = "be502aa03df926a8f9df474a0a7fe16c8fb14fbd" } },
        .{ "git_reference", .{ .string = "f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9" } },
        .{ "protocol", .{ .integer = 1 } },
    });
    if (equal(op, "eval")) {
        const effects = field(req, "effects");
        if (effects == .array and effects.array.items.len > 0) return interpreter.evaluateFixture(a, try parser.object(a, &.{ .{ "source", field(req, "program") }, .{ "effects", effects } }));
        return interpreter.evaluate(a, field(req, "program"));
    }
    if (equal(op, "input")) {
        const flush_value = field(req, "flush");
        const parsed = try input.parse(a, str(field(req, "text")), flush_value == .bool and flush_value.bool);
        return parser.object(a, &.{ .{ "events", .{ .array = parsed.events } }, .{ "remainder", .{ .string = parsed.remainder } } });
    }
    if (equal(op, "fixture")) return interpreter.evaluateFixture(a, field(req, "fixture"));
    if (equal(op, "parse")) {
        const ir = parser.parse(a, str(field(req, "source"))) catch return parser.object(a, &.{.{ "parse_error", .{ .bool = true } }});
        return parser.object(a, &.{.{ "program", ir }});
    }
    if (equal(op, "diagnostic")) return parser.object(a, &.{.{ "message", .{ .string = try parser.diagnostic(a, str(field(req, "source"))) } }});
    if (equal(op, "git")) return git.request(a, req);
    if (equal(op, "tui")) {
        var shell = tui.Tui.init(a);
        defer shell.shutdown();
        shell.sandboxed = true;
        shell.files = field(req, "files");
        shell.package_fixtures = field(req, "packages");
        var width = number(field(req, "width"), 80);
        var height = number(field(req, "height"), 24);
        if (width > 1000 or height > 1000) return error.InvalidDimensions;
        var frames = std.ArrayList(J).init(a);
        try frames.append(try shell.frame(width, height));
        const events = field(req, "events");
        if (events == .array) for (events.array.items) |event| {
            const size = field(event, "resize");
            if (size == .object or size == .array) {
                if (size == .array and size.array.items.len == 2) {
                    width = number(size.array.items[0], width);
                    height = number(size.array.items[1], height);
                } else {
                    width = number(field(size, "width"), width);
                    height = number(field(size, "height"), height);
                }
                if (width > 1000 or height > 1000) return error.InvalidDimensions;
            } else try shell.event(event);
            try frames.append(try shell.frame(width, height));
        };
        return parser.object(a, &.{.{ "frames", .{ .array = frames } }});
    }
    if (equal(op, "bench_tui")) {
        const width = number(field(req, "width"), 80);
        const height = number(field(req, "height"), 24);
        if (width > 1000 or height > 1000) return error.InvalidDimensions;
        const events = field(req, "events");
        var samples = std.ArrayList(J).init(a);
        var cpu_samples = std.ArrayList(J).init(a);
        // Timed frames are discarded, unlike the retained trace snapshots.
        // Reuse their owned output storage without retaining it in VM history.
        var frame_output = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer frame_output.deinit();
        const iterations = @min(number(field(req, "iterations"), 100), 100000);
        for (0..iterations) |_| {
            var iteration = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer iteration.deinit();
            var shell = tui.Tui.init(iteration.allocator());
            defer shell.shutdown();
            shell.sandboxed = true;
            shell.files = field(req, "files");
            shell.package_fixtures = field(req, "packages");
            _ = try shell.frameAlloc(frame_output.allocator(), width, height);
            _ = frame_output.reset(.retain_capacity);
            if (events == .array) for (events.array.items) |event| {
                var timer = try std.time.Timer.start();
                const cpu_start = try threadCpuNanoseconds();
                try shell.event(event);
                _ = try shell.frameAlloc(frame_output.allocator(), width, height);
                _ = frame_output.reset(.retain_capacity);
                const cpu_elapsed = (try threadCpuNanoseconds()) - cpu_start;
                try samples.append(.{ .integer = @intCast(timer.read()) });
                try cpu_samples.append(.{ .integer = @intCast(cpu_elapsed) });
            };
        }
        return parser.object(a, &.{ .{ "samples_ns", .{ .array = samples } }, .{ "cpu_samples_ns", .{ .array = cpu_samples } } });
    }
    return error.UnknownOperation;
}

const TerminalSize = struct { width: usize, height: usize };
fn terminalSize() TerminalSize {
    var size: std.posix.winsize = .{ .row = 24, .col = 80, .xpixel = 0, .ypixel = 0 };
    _ = std.posix.system.ioctl(std.io.getStdOut().handle, std.posix.T.IOCGWINSZ, @intFromPtr(&size));
    return .{ .width = if (size.col == 0) 80 else size.col, .height = if (size.row == 0) 24 else size.row };
}

fn interactive(a: A) !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    if (!std.posix.isatty(stdin.handle) or !std.posix.isatty(stdout.handle)) return cliError("The TUI needs terminal input and output");
    const previous = try std.posix.tcgetattr(stdin.handle);
    var raw = previous;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.oflag.OPOST = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(stdin.handle, .FLUSH, raw);
    defer std.posix.tcsetattr(stdin.handle, .FLUSH, previous) catch {};
    const resize_pipe = try std.posix.pipe2(.{ .CLOEXEC = true, .NONBLOCK = true });
    defer std.posix.close(resize_pipe[0]);
    defer std.posix.close(resize_pipe[1]);
    var previous_resize: std.posix.Sigaction = undefined;
    const resize_action = std.posix.Sigaction{ .handler = .{ .handler = onResize }, .mask = std.posix.empty_sigset, .flags = 0 };
    resize_write_fd = resize_pipe[1];
    std.posix.sigaction(std.posix.SIG.WINCH, &resize_action, &previous_resize);
    defer {
        std.posix.sigaction(std.posix.SIG.WINCH, &previous_resize, null);
        resize_write_fd = -1;
    }
    try stdout.writeAll("\x1b[?2004h");
    defer stdout.writeAll("\x1b[?2026l\x1b[?2004l\x1b[0m\x1b[?25h") catch {};
    var shell = tui.Tui.init(a);
    defer shell.shutdown();
    try shell.startHub();
    var size = terminalSize();
    try draw(&shell, size);
    var pending = std.ArrayList(u8).init(a);
    var raw_input = std.ArrayList(u8).init(a);
    var chunk: [4096]u8 = undefined;
    var poll_fds = [_]std.posix.pollfd{
        .{ .fd = stdin.handle, .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = resize_pipe[0], .events = std.posix.POLL.IN, .revents = 0 },
    };
    var last_input_ns: i128 = 0;
    while (true) {
        if (try shell.pollWork()) try draw(&shell, size);
        const ready = try std.posix.poll(&poll_fds, if (shell.hasPendingWork()) 1 else if (pending.items.len > 0) 40 else 100);
        if (poll_fds[0].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) return;
        const count = if (ready > 0 and poll_fds[0].revents & std.posix.POLL.IN != 0) try stdin.read(&chunk) else 0;
        if (poll_fds[1].revents & std.posix.POLL.IN != 0) {
            var notifications: [64]u8 = undefined;
            _ = try std.posix.read(resize_pipe[0], &notifications);
        }
        const new_size = terminalSize();
        if (new_size.width != size.width or new_size.height != size.height) {
            size = new_size;
            try draw(&shell, size);
        }
        if (count > 0) {
            last_input_ns = std.time.nanoTimestamp();
            try raw_input.appendSlice(chunk[0..count]);
            try decodeUtf8(&raw_input, &pending);
        }
        if (pending.items.len == 0) continue;
        const paste_pending = std.mem.startsWith(u8, pending.items, "\x1b[200~");
        // Editable nodes and closures retain labels from pasted source. Keep
        // their backing bytes independent from the reusable terminal buffer.
        const flush = std.time.nanoTimestamp() - last_input_ns >= 40 * std.time.ns_per_ms;
        const parsed = try input.parse(a, try a.dupe(u8, pending.items), flush and !paste_pending);
        for (parsed.events.items) |event| {
            if (equal(str(field(event, "key")), "ctrl+q")) return;
            try shell.event(event);
        }
        std.mem.copyForwards(u8, pending.items, parsed.remainder);
        pending.shrinkRetainingCapacity(parsed.remainder.len);
        if (parsed.events.items.len > 0) try draw(&shell, size);
    }
}

// Node's UTF-8 stream decoder retains incomplete scalars between reads. Match
// that boundary before etui's grapheme parser sees the input.
fn decodeUtf8(raw: *std.ArrayList(u8), decoded: *std.ArrayList(u8)) !void {
    var i: usize = 0;
    while (i < raw.items.len) {
        const length = std.unicode.utf8ByteSequenceLength(raw.items[i]) catch {
            try decoded.appendSlice("\xef\xbf\xbd");
            i += 1;
            continue;
        };
        var consumed: usize = 1;
        while (consumed < length and i + consumed < raw.items.len) : (consumed += 1) {
            const next = raw.items[i + consumed];
            const lead = raw.items[i];
            if (next < 0x80 or next > 0xbf or (consumed == 1 and ((lead == 0xe0 and next < 0xa0) or (lead == 0xed and next > 0x9f) or (lead == 0xf0 and next < 0x90) or (lead == 0xf4 and next > 0x8f)))) break;
        }
        if (consumed < length and i + consumed < raw.items.len) {
            try decoded.appendSlice("\xef\xbf\xbd");
            i += consumed;
            continue;
        }
        if (i + length > raw.items.len) break;
        try decoded.appendSlice(raw.items[i..][0..length]);
        i += length;
    }
    std.mem.copyForwards(u8, raw.items, raw.items[i..]);
    raw.shrinkRetainingCapacity(raw.items.len - i);
}

test "UTF-8 terminal reads retain incomplete scalars" {
    var raw = std.ArrayList(u8).init(std.testing.allocator);
    defer raw.deinit();
    var decoded = std.ArrayList(u8).init(std.testing.allocator);
    defer decoded.deinit();
    try raw.append(0xce);
    try decodeUtf8(&raw, &decoded);
    try std.testing.expectEqual(@as(usize, 0), decoded.items.len);
    try raw.append(0xbb);
    try decodeUtf8(&raw, &decoded);
    try std.testing.expectEqualStrings("λ", decoded.items);
    try std.testing.expectEqual(@as(usize, 0), raw.items.len);
    decoded.clearRetainingCapacity();
    try raw.appendSlice("\xe2\x82A");
    try decodeUtf8(&raw, &decoded);
    try std.testing.expectEqualStrings("\u{fffd}A", decoded.items);
    decoded.clearRetainingCapacity();
    try raw.appendSlice("\xe2A");
    try decodeUtf8(&raw, &decoded);
    try std.testing.expectEqualStrings("\u{fffd}A", decoded.items);
}

fn draw(shell: *tui.Tui, size: TerminalSize) !void {
    const frame = try shell.renderAnsiAlloc(std.heap.page_allocator, size.width, size.height);
    defer std.heap.page_allocator.free(frame);
    try std.io.getStdOut().writeAll(frame);
}
