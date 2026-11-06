const std = @import("std");

/// Wires up a config project: `@import("kosm").addConfigProject(b, @import("build.zig.zon"))`.
pub const addConfigProject = @import("build/config_project.zig").addConfigProject;
/// The whole build of a directory package (D62): `@import("kosm").package(b)`.
pub const package = package_build.package;

const package_build = @import("build/package.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core imports only the tree-sitter runtime: it knows no apps, packages or command line (D1).
    const kosm_module = b.addModule("kosm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addTreeSitter(b, kosm_module, target, optimize);
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

/// Compiles the tree-sitter runtime into core and imports its C API as `tree_sitter_api` (D41).
fn addTreeSitter(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const runtime = b.dependency("tree_sitter", .{});
    const header = b.addWriteFiles().add("tree_sitter_api.h", "#include <tree_sitter/api.h>\n");
    const api = b.addTranslateC(.{ .root_source_file = header, .target = target, .optimize = optimize });
    api.addIncludePath(runtime.path("include"));
    module.addImport("tree_sitter_api", api.createModule());
    module.addIncludePath(runtime.path("include"));
    module.addIncludePath(runtime.path("src"));
    module.addCSourceFile(.{
        .file = runtime.path("src/lib.c"),
        .flags = &.{ "-std=c11", "-D_POSIX_C_SOURCE=200112L", "-D_DEFAULT_SOURCE" },
    });
}

/// The built-in packages in packages/ (D67), tested against this kosm.
const built_in_packages = [_]BuiltInPackage{
    .{ .name = "kosm_kitty" },
    .{ .name = "kosm_css" },
    .{ .name = "kosm_zen" },
    .{ .name = "kosm_nvim" },
    .{ .name = "kosm_json", .grammars = &.{"tree_sitter_json"} },
    .{ .name = "kosm_lua", .grammars = &.{"tree_sitter_lua"} },
};

/// A package in packages/ and the grammars it compiles (D78), which this build.zig.zon lists too.
const BuiltInPackage = struct {
    name: []const u8,
    grammars: []const []const u8 = &.{},
};

/// Tests each built-in package with every other one importable by name, as a config sees them.
fn addPackageTests(b: *std.Build, test_step: *std.Build.Step, kosm_module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    var modules: [built_in_packages.len]*std.Build.Module = undefined;
    for (built_in_packages, &modules) |built_in, *module| {
        module.* = b.createModule(.{
            .root_source_file = b.path(b.fmt("packages/{s}/root.zig", .{built_in.name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "kosm", .module = kosm_module }},
        });
        for (built_in.grammars) |grammar| package_build.addGrammar(b, module.*, b.dependency(grammar, .{}));
    }
    for (modules, 0..) |module, index| {
        for (built_in_packages, modules, 0..) |other, other_module, other_index| {
            if (other_index != index) module.addImport(other.name, other_module);
        }
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = module, .name = built_in_packages[index].name })).step);
    }
}
