const std = @import("std");

/// Wires up a config project: `@import("kosm").addConfigProject(b, @import("build.zig.zon"))`.
pub const addConfigProject = @import("build/config_project.zig").addConfigProject;
/// The whole build of a directory package: `@import("kosm").package(b)`.
pub const package = package_build.package;

const package_build = @import("build/package.zig");

/// Where `kosm init` fetches kosm and the official packages from: each one's repository is
/// this followed by its name.
const repositories = "git+https://git.nnstdios.com/nnra6864/";
/// The official packages `kosm init` adds to a new config, sorted by name.
const official_packages = [_][]const u8{
    "kosm_css",
    "kosm_darkreader",
    "kosm_ghostty",
    "kosm_hyprland",
    "kosm_ini",
    "kosm_json",
    "kosm_kitty",
    "kosm_lua",
    "kosm_nvim",
    "kosm_toml",
    "kosm_userjs",
    "kosm_zen",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const network_tests = b.option(bool, "network", "Also run the tests that fetch kosm and the official packages from their repositories") orelse false;

    // Core imports only the tree-sitter runtime: it knows no apps, packages or command line.
    const kosm_module = b.addModule("kosm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addTreeSitter(b, kosm_module, target, optimize);
    // The number the command line and the runner check against each other.
    const interface_module = b.createModule(.{
        .root_source_file = b.path("src/interface.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The record of the last apply: the runner writes it, the command line reads it.
    const current_module = b.createModule(.{
        .root_source_file = b.path("src/current/Record.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The runner only sees core's public API, like any package.
    const runner_module = b.addModule("kosm_runner", .{
        .root_source_file = b.path("src/runner/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "kosm", .module = kosm_module },
            .{ .name = "kosm_current", .module = current_module },
            .{ .name = "kosm_interface", .module = interface_module },
        },
    });
    // The command line only drives zig build and the runner; it imports nothing but kosm_current,
    // kosm_interface and what kosm init writes.
    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "kosm_current", .module = current_module },
            .{ .name = "kosm_interface", .module = interface_module },
            .{ .name = "kosm_package", .module = packageOptions(b, network_tests).createModule() },
        },
    });
    const cli = b.addExecutable(.{ .name = "kosm", .root_module = cli_module });
    b.installArtifact(cli);
    installSources(b);

    const run_cli = b.addRunArtifact(cli);
    run_cli.addPassthruArgs();
    b.step("run", "Run kosm").dependOn(&run_cli.step);

    const build_helpers_module = b.createModule(.{
        .root_source_file = b.path("build/package.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run tests");
    // The config tests build against the installed sources, which proves every manifest's `.paths`.
    test_step.dependOn(b.getInstallStep());
    for ([_]*std.Build.Module{ kosm_module, interface_module, current_module, runner_module, build_helpers_module }) |module| {
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = module })).step);
    }
    // The command line's tests build configs against the installed sources, which Zig's cache
    // doesn't track, so a cached pass could hide a broken one.
    const cli_tests = b.addRunArtifact(b.addTest(.{ .root_module = cli_module }));
    cli_tests.has_side_effects = true;
    test_step.dependOn(&cli_tests.step);
}

/// What the command line knows about kosm as a package: what `kosm init` fetches and writes,
/// the fingerprint tests give a stub kosm, and whether tests may use the network.
fn packageOptions(b: *std.Build, network_tests: bool) *std.Build.Step.Options {
    const options = b.addOptions();
    options.addOption(bool, "network_tests", network_tests);
    options.addOption([]const u8, "repositories", repositories);
    options.addOption([]const []const u8, "official_packages", &official_packages);
    options.addOption([]const u8, "minimum_zig_version", @import("build.zig.zon").minimum_zig_version);
    options.addOption(u64, "fingerprint", @import("build.zig.zon").fingerprint);
    return options;
}

/// Installs kosm's sources in `<prefix>/share/kosm`, where the installed binary finds them and
/// builds every config with them. Only what a fetch of kosm would hold: the `.paths` of
/// kosm's manifest, so no `.zig-cache` comes along.
fn installSources(b: *std.Build) void {
    for (manifestPaths(b)) |path| installPath(b, path, b.fmt("share/kosm/{s}", .{path}));
}

/// Installs the file or directory `source`, relative to the repo, at `destination` under the prefix.
fn installPath(b: *std.Build, source: []const u8, destination: []const u8) void {
    const full_path = b.root.joinString(b.allocator, source) catch @panic("OOM");
    const stat = std.Io.Dir.cwd().statFile(b.graph.io, full_path, .{}) catch |err|
        std.debug.panic("cannot read {s}: {s}", .{ source, @errorName(err) });
    if (stat.kind == .directory) {
        b.installDirectory(.{ .source_dir = b.path(source), .install_dir = .prefix, .install_subdir = destination });
    } else {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path(source), .prefix, destination).step);
    }
}

/// The `.paths` of kosm's manifest, relative to the repo. Registers the manifest, so a changed
/// `.paths` reruns the cached configure phase.
fn manifestPaths(b: *std.Build) []const []const u8 {
    b.dependOnFileContents(b.path("build.zig.zon"));
    const path = b.root.joinString(b.allocator, "build.zig.zon") catch @panic("OOM");
    const source = std.Io.Dir.cwd().readFileAllocOptions(b.graph.io, path, b.allocator, .limited(1024 * 1024), .of(u8), 0) catch |err|
        std.debug.panic("cannot read {s}: {s}", .{ path, @errorName(err) });
    const Manifest = struct { paths: []const []const u8 };
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const manifest = std.zon.parse.fromSlice(Manifest, .{ .gpa = b.allocator, .arena = b.allocator, .source = source, .diagnostics = &diagnostics, .ignore_unknown_fields = true }) catch |err|
        std.debug.panic("cannot read .paths from {s}: {s}", .{ path, @errorName(err) });
    return manifest.paths;
}

/// Compiles the tree-sitter runtime into core and imports its C API as `tree_sitter_api`.
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
