//! The generator of the Zig modules of apps, adapters and frontends written through a frontend,
//! shared by a config's build (its `apps/`, `adapters/` and `frontends/`) and a package's build
//! (a package whose root is a script).

const std = @import("std");

/// A module giving frontends, which the generator reads scripts with.
pub const FrontendModule = struct {
    /// The package it comes from, for messages: "kosm_lua".
    package: []const u8,
    /// The name the generator imports it by: "kosm_lua_frontend".
    name: []const u8,
    module: *std.Build.Module,
};

/// The executable writing the module of each script it is given, reading them with `frontends`.
/// Its arguments are the output folder, every module name a field's type may start with
/// (comma separated), and `<module name>=<path for messages>=<absolute path>` per script.
pub fn addGenerator(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, runner: *std.Build.Module, frontends: []const FrontendModule) *std.Build.Step.Compile {
    var source: std.Io.Writer.Allocating = .init(b.allocator);
    const writer = &source.writer;
    writer.writeAll(
        \\const std = @import("std");
        \\const runner = @import("kosm_runner");
        \\
        \\pub fn main(init: std.process.Init) !u8 {
        \\    return runner.generateApps(init, &.{
        \\
    ) catch @panic("OOM");
    for (frontends) |frontend| {
        writer.print("        .{{ .package = \"{f}\", .module = @import(\"{f}\") }},\n", .{ std.zig.fmtString(frontend.package), std.zig.fmtString(frontend.name) }) catch @panic("OOM");
    }
    writer.writeAll(
        \\    });
        \\}
        \\
    ) catch @panic("OOM");
    const files = b.addWriteFiles();
    const root_module = b.createModule(.{ .root_source_file = files.add("main.zig", source.written()), .target = target, .optimize = optimize });
    root_module.addImport("kosm_runner", runner);
    for (frontends) |frontend| root_module.addImport(frontend.name, frontend.module);
    return b.addExecutable(.{ .name = "kosm-apps", .root_module = root_module });
}

/// The file name a script giving its folder's kosmos, app or package has before its extension.
pub const script_root = "root";

/// Whether `file_name` is a script: not hidden, with an extension other than Zig's and its
/// manifests'.
pub fn isScriptFile(file_name: []const u8) bool {
    if (std.mem.startsWith(u8, file_name, ".") or std.mem.endsWith(u8, file_name, ".zig") or std.mem.endsWith(u8, file_name, ".zon")) return false;
    return std.mem.findScalar(u8, file_name, '.') != null;
}

/// A script's file name before its first dot: "nord" of "nord.lua".
pub fn scriptStem(file_name: []const u8) []const u8 {
    return file_name[0 .. std.mem.findScalar(u8, file_name, '.') orelse file_name.len];
}

/// The file name of the script in `dir` giving its kosmos, app or package (`root` with an
/// extension other than Zig's and its manifests'), allocated with `b`; null for none.
pub fn scriptRootIn(b: *std.Build, dir: std.Io.Dir) !?[]const u8 {
    const io = b.graph.io;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |file| {
        if (file.kind != .file and file.kind != .sym_link) continue;
        if (isScriptFile(file.name) and std.mem.eql(u8, scriptStem(file.name), script_root)) return b.dupe(file.name);
    }
    return null;
}
