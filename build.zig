const std = @import("std");

/// Wires up a config project: `@import("kosm").addConfigProject(b, @import("build.zig.zon"))`.
pub const addConfigProject = @import("build/config_project.zig").addConfigProject;
/// The whole build of a directory package (D62): `@import("kosm").package(b)`.
pub const package = @import("build/package.zig").package;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core imports nothing: it knows no apps, packages or command line (D1).
    const kosm_module = b.addModule("kosm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The record of the last apply: the runner writes it, the command line reads it (D75).
    const current_module = b.createModule(.{
        .root_source_file = b.path("src/current/Record.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The runner only sees core's public API, like any package (D2).
    const runner_module = b.addModule("kosm_runner", .{
        .root_source_file = b.path("src/runner/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "kosm", .module = kosm_module },
            .{ .name = "kosm_current", .module = current_module },
        },
    });
    // The command line only drives zig build and the runner; it imports nothing but kosm_current.
    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "kosm_current", .module = current_module }},
    });
    const cli = b.addExecutable(.{ .name = "kosm", .root_module = cli_module });
    b.installArtifact(cli);

    const run_cli = b.addRunArtifact(cli);
    run_cli.addPassthruArgs();
    b.step("run", "Run kosm").dependOn(&run_cli.step);

    const build_helpers_module = b.createModule(.{
        .root_source_file = b.path("build/package.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run tests");
    for ([_]*std.Build.Module{ kosm_module, current_module, runner_module, cli_module, build_helpers_module }) |module| {
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = module })).step);
    }
    addPackageTests(b, test_step, kosm_module, target, optimize);
}

/// The built-in packages in packages/ (D67), tested against this kosm.
const built_in_packages = [_][]const u8{ "kosm_kitty", "kosm_css", "kosm_zen", "kosm_nvim" };

/// Tests each built-in package with every other one importable by name, as a config sees them.
fn addPackageTests(b: *std.Build, test_step: *std.Build.Step, kosm_module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    var modules: [built_in_packages.len]*std.Build.Module = undefined;
    for (built_in_packages, &modules) |name, *module| {
        module.* = b.createModule(.{
            .root_source_file = b.path(b.fmt("packages/{s}/root.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "kosm", .module = kosm_module }},
        });
    }
    for (modules, 0..) |module, index| {
        for (built_in_packages, modules, 0..) |other_name, other, other_index| {
            if (other_index != index) module.addImport(other_name, other);
        }
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = module, .name = built_in_packages[index] })).step);
    }
}
