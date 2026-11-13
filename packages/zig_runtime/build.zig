const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{ .name = "eyg", .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });
    exe.root_module.strip = b.option(bool, "strip", "Strip debug information from the executable") orelse (optimize != .Debug);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run EYG (interactive by default)").dependOn(&run.step);
    const tests = b.addTest(.{ .root_source_file = b.path("src/tests.zig"), .target = target, .optimize = optimize });
    b.step("test", "Run runtime unit tests").dependOn(&b.addRunArtifact(tests).step);
}
