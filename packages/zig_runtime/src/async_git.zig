//! A Git effect runs outside the UI thread. The worker owns all its memory;
//! only a completed immutable result crosses back to the interpreter.
const std = @import("std");
const git = @import("git.zig");
const J = std.json.Value;

pub const Worker = struct {
    arena: std.heap.ArenaAllocator,
    request: J,
    response: union(enum) { pending, success: J, failure: anyerror } = .pending,
    completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    owners: std.atomic.Value(usize) = std.atomic.Value(usize).init(2),
    thread: ?std.Thread = null,
    cancelled: bool = false,

    pub fn start(request: J) !*Worker {
        const self = try std.heap.page_allocator.create(Worker);
        self.* = .{ .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator), .request = .null };
        errdefer {
            self.arena.deinit();
            std.heap.page_allocator.destroy(self);
        }
        const a = self.arena.allocator();
        const bytes = try std.json.stringifyAlloc(a, request, .{});
        self.request = (try std.json.parseFromSlice(J, a, bytes, .{ .allocate = .alloc_always })).value;
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }
    fn run(self: *Worker) void {
        defer self.release();
        if (git.request(self.arena.allocator(), self.request)) |value| self.response = .{ .success = value } else |err| self.response = .{ .failure = err };
        self.completed.store(true, .release);
    }
    pub fn ready(self: *Worker) bool {
        return self.completed.load(.acquire);
    }
    /// The caller consumes/clones a ready response before releasing its owner.
    /// An unfinished job owns its snapshot until completion, so terminal
    /// shutdown never waits for filesystem I/O and cannot free worker storage.
    pub fn destroy(self: *Worker) void {
        if (self.thread) |thread| thread.detach();
        self.release();
    }
    fn release(self: *Worker) void {
        if (self.owners.fetchSub(1, .acq_rel) != 1) return;
        self.arena.deinit();
        std.heap.page_allocator.destroy(self);
    }
};

test "worker error result crosses an acquire/release boundary" {
    var request = std.json.ObjectMap.init(std.testing.allocator);
    defer request.deinit();
    try request.put("repo", .{ .string = "/definitely-missing-eyg-repository" });
    const job = try Worker.start(.{ .object = request });
    defer job.destroy();
    while (!job.ready()) std.Thread.yield() catch {};
    try std.testing.expect(job.response == .failure);
}

test "releasing the UI owner does not wait for the worker" {
    const Flag = std.atomic.Value(bool);
    const Gate = struct {
        worker: *Worker,
        started: Flag = Flag.init(false),
        proceed: Flag = Flag.init(false),
        finished: Flag = Flag.init(false),

        fn run(gate: *@This()) void {
            gate.started.store(true, .release);
            while (!gate.proceed.load(.acquire)) std.Thread.yield() catch {};
            gate.worker.completed.store(true, .release);
            gate.worker.release();
            gate.finished.store(true, .release);
        }
    };
    const worker = try std.heap.page_allocator.create(Worker);
    worker.* = .{ .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator), .request = .null };
    var gate = Gate{ .worker = worker };
    worker.thread = try std.Thread.spawn(.{}, Gate.run, .{&gate});
    while (!gate.started.load(.acquire)) std.Thread.yield() catch {};
    worker.destroy();
    // A join here would deadlock: only the returning UI can open this gate.
    gate.proceed.store(true, .release);
    while (!gate.finished.load(.acquire)) std.Thread.yield() catch {};
}
