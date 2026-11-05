const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core data imports nothing: it knows no apps, files or adapters (D1).
    const kosm_module = b.addModule("kosm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const kosm_tests = b.addTest(.{ .root_module = kosm_module });
    const run_kosm_tests = b.addRunArtifact(kosm_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_kosm_tests.step);
}
