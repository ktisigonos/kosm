//! The build of a config project: every installed package and every local kosmos, app and
//! adapter becomes a module importable by name, and `-Dkosmos=frost.iced` builds
//! `zig-out/bin/kosmos`, the runner for that one kosmos. `-Dinspect=kosm_kitty` builds
//! `zig-out/bin/inspect`, which reports what that installed package provides. `-Dlist` builds
//! `zig-out/bin/list`, which lists every kosmos and installed package. `-Dcolors=frost` builds
//! `zig-out/bin/colors`, which prints the palettes that kosmos' file declares. `check` compiles
//! every local one, so editors see the config's imports.

const std = @import("std");
const import_scanner = @import("../src/cli/import_scanner.zig");
const unify = @import("unify.zig").unify;

/// The directories holding local kosmoi, apps and adapters, in the config's root.
const local_directories = [_][]const u8{ "kosmoi", "apps", "adapters" };
/// Local Zig files are small; this only guards against reading something huge.
const max_file_size = 16 * 1024 * 1024;

/// Wires up a config project. `manifest` is the config's `@import("build.zig.zon")`; one of its
/// dependencies must be `kosm`. Problems (a name used twice, an unknown kosmos) fail the build.
pub fn addConfigProject(b: *std.Build, comptime manifest: anytype) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const kosmos_name = b.option([]const u8, "kosmos", "The kosmos to build: frost, or a variant like frost.iced");
    const inspected_name = b.option([]const u8, "inspect", "The installed package to report on, for kosm add and kosm update");
    const list = b.option(bool, "list", "Build the listing of every kosmos and package, for kosm list") orelse false;
    const colors_name = b.option([]const u8, "colors", "The kosmos whose palettes to print, for kosm colors");

    var names: Names = .{ .b = b };
    inline for (@typeInfo(@TypeOf(manifest.dependencies)).@"struct".field_names) |name| {
        const dependency = b.dependency(name, .{ .target = target, .optimize = optimize });
        const module = dependency.builder.modules.get(name) orelse
            return fail(b, "package '{s}' has no module named '{s}'; its manifest name and module name must match", .{ name, name });
        if (!names.add(.{ .name = name, .module = module, .origin = b.fmt("package '{s}'", .{name}), .kind = .package })) return;
    }
    const kosm_dependency = for (names.modules.items) |entry| {
        if (std.mem.eql(u8, entry.name, "kosm")) break b.dependency("kosm", .{ .target = target, .optimize = optimize });
    } else return fail(b, "build.zig.zon has no 'kosm' dependency", .{});
    if (!unifyPackages(b, names.modules.items)) return;

    b.dependOnDirectoryContents(b.path("."));
    for (local_directories) |directory| {
        const found = listLocal(b, directory) catch |err| return fail(b, "cannot read {s}/: {s}", .{ directory, @errorName(err) });
        for (found) |local| {
            if (local.missing_root) return fail(b, "{s} is a directory package but has no root.zig", .{local.origin});
            const module = b.createModule(.{ .root_source_file = b.path(local.root), .target = target, .optimize = optimize });
            const kind: Kind = if (std.mem.eql(u8, directory, "kosmoi")) .kosmos else if (std.mem.eql(u8, directory, "adapters")) .adapter else .app;
            if (!names.add(.{ .name = local.name, .module = module, .origin = local.origin, .kind = kind, .local = local })) return;
        }
    }
    // Every local module sees every package and every other local module by name.
    for (names.modules.items) |entry| {
        if (entry.kind == .package) continue;
        for (names.modules.items) |other| {
            if (other.module != entry.module) entry.module.addImport(other.name, other.module);
        }
    }

    addEditorCheck(b, names.modules.items);
    if (inspected_name) |name| addInspector(b, target, optimize, kosm_dependency, names.modules.items, name);
    if (list) addLister(b, target, optimize, kosm_dependency, names.modules.items);
    if (colors_name) |name| addColors(b, target, optimize, kosm_dependency, names.modules.items, name);
    const name = kosmos_name orelse return;
    addRunner(b, target, optimize, kosm_dependency, names.modules.items, name);
}

/// A `check` step compiling every local kosmos, app and adapter, which `zig build` and kosm never
/// run. Editors read the module graph from the build's steps, so it is what gives ZLS every
/// import of the config.
fn addEditorCheck(b: *std.Build, entries: []const Entry) void {
    const check = b.step("check", "Compile every local kosmos, app and adapter; editors read their imports from it");
    for (entries) |entry| {
        if (entry.kind == .package) continue;
        check.dependOn(&b.addObject(.{ .name = entry.name, .root_module = entry.module }).step);
    }
}

const Kind = enum { package, kosmos, app, adapter };

const Entry = struct {
    name: []const u8,
    module: *std.Build.Module,
    /// For messages: "package 'kosm_kitty'" or "kosmoi/frost.zig".
    origin: []const u8,
    kind: Kind,
    /// Where a local kosmos, app or adapter lives; null for a package.
    local: ?Local = null,
};

/// Every module name in the config, refusing a name used twice.
const Names = struct {
    b: *std.Build,
    modules: std.ArrayList(Entry) = .empty,

    /// Adds `entry`, or fails the build and returns false when its name is taken.
    fn add(names: *Names, entry: Entry) bool {
        for (names.modules.items) |existing| {
            if (std.mem.eql(u8, existing.name, entry.name)) {
                fail(names.b, "'{s}' names both {s} and {s}; kosmoi, apps, adapters and packages need unique names", .{ entry.name, existing.origin, entry.origin });
                return false;
            }
        }
        names.modules.append(names.b.allocator, entry) catch @panic("OOM");
        return true;
    }
};

/// Makes every package use the config's copy of each package the config lists. Packages pinning
/// different copies of a package it does not list fail the build, returning false.
fn unifyPackages(b: *std.Build, packages: []const Entry) bool {
    const listed = b.allocator.alloc(std.Build.Module.Import, packages.len) catch @panic("OOM");
    for (packages, listed) |package, *own| own.* = .{ .name = package.name, .module = package.module };
    const conflict = unify(b, listed) orelse return true;
    fail(b, "packages '{s}' and '{s}' pin different copies of package '{s}'; add '{s}' to this config with kosm add, and both use that one", .{ conflict.first_importer, conflict.second_importer, conflict.package, conflict.package });
    return false;
}

const Local = struct {
    name: []const u8,
    /// The module root, relative to the config root.
    root: []const u8,
    /// For messages: "kosmoi/frost.zig" or "kosmoi/nord/".
    origin: []const u8,
    /// A directory package, rather than a single file.
    is_directory: bool,
    /// A directory without a root.zig.
    missing_root: bool,
};

/// The single-file and directory packages in `directory`, sorted by name; a missing directory
/// has none. Registers what it reads, so adding a file reruns the configure phase.
fn listLocal(b: *std.Build, directory: []const u8) ![]const Local {
    const io = b.graph.io;
    const full_path = b.root.joinString(b.allocator, directory) catch @panic("OOM");
    var dir = std.Io.Dir.cwd().openDir(io, full_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer dir.close(io);
    b.dependOnDirectoryContents(b.path(directory));

    var found: std.ArrayList(Local) = .empty;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const path = b.fmt("{s}/{s}", .{ directory, entry.name });
            try found.append(b.allocator, .{ .name = b.dupe(entry.name[0 .. entry.name.len - ".zig".len]), .root = path, .origin = path, .is_directory = false, .missing_root = false });
        } else if (entry.kind == .directory) {
            const package_path = b.fmt("{s}/{s}", .{ directory, entry.name });
            b.dependOnDirectoryContents(b.path(package_path));
            const has_root = if (dir.statFile(io, b.fmt("{s}/root.zig", .{entry.name}), .{})) |_| true else |_| false;
            try found.append(b.allocator, .{
                .name = b.dupe(entry.name),
                .root = b.fmt("{s}/root.zig", .{package_path}),
                .origin = b.fmt("{s}/", .{package_path}),
                .is_directory = true,
                .missing_root = !has_root,
            });
        }
    }
    std.mem.sort(Local, found.items, {}, localLessThan);
    return found.items;
}

fn localLessThan(_: void, left: Local, right: Local) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// Generates the runner's main for kosmos `name` ("frost" or "frost.iced") and installs it
/// as `kosmos`.
fn addRunner(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry, name: []const u8) void {
    const dot = std.mem.findScalar(u8, name, '.');
    const function = if (dot) |index| name[index + 1 ..] else "kosmos";
    const kosmos = kosmosFile(b, entries, name) orelse return;
    const reached = reachedLocals(b, entries, kosmos) catch |err| return fail(b, "cannot read the imports of {s}: {s}", .{ kosmos.origin, @errorName(err) });

    var source: std.Io.Writer.Allocating = .init(b.allocator);
    const writer = &source.writer;
    writer.print(
        \\const std = @import("std");
        \\const runner = @import("kosm_runner");
        \\
        \\pub fn main(init: std.process.Init) !u8 {{
        \\    return runner.run(init, .{{
        \\        .name = "{f}",
        \\        .path = "{f}",
        \\        .file = @import("{f}"),
        \\        .function = "{f}",
        \\        .adapter_sources = &.{{
        \\
    , .{ std.zig.fmtString(name), std.zig.fmtString(kosmos.origin), std.zig.fmtString(kosmos.name), std.zig.fmtString(function) }) catch @panic("OOM");
    for (entries) |entry| {
        if (providesAdapters(entry, reached)) writer.print("            .{{ .package = \"{f}\", .module = @import(\"{f}\") }},\n", .{ std.zig.fmtString(entry.name), std.zig.fmtString(entry.name) }) catch @panic("OOM");
    }
    writer.writeAll(
        \\        },
        \\    });
        \\}
        \\
    ) catch @panic("OOM");

    const files = b.addWriteFiles();
    const main = files.add("main.zig", source.written());
    const root_module = b.createModule(.{ .root_source_file = main, .target = target, .optimize = optimize });
    root_module.addImport("kosm_runner", kosm_dependency.module("kosm_runner"));
    for (entries) |entry| root_module.addImport(entry.name, entry.module);
    b.installArtifact(b.addExecutable(.{ .name = "kosmos", .root_module = root_module }));
}

/// The local kosmos, app or adapter, or the installed package, holding kosmos `name` ("frost" or
/// "frost.iced"). Fails the build and returns null when there is none.
fn kosmosFile(b: *std.Build, entries: []const Entry, name: []const u8) ?Entry {
    const file_name = name[0 .. std.mem.findScalar(u8, name, '.') orelse name.len];
    for (entries) |entry| {
        if (canHoldKosmoi(entry) and std.mem.eql(u8, entry.name, file_name)) return entry;
    }
    fail(b, "there is no kosmos '{s}' (no local kosmos, app or adapter '{s}' and no installed package '{s}'); in kosmoi/: {s}; in apps/: {s}; in adapters/: {s}; installed packages: {s}", .{
        name, file_name, file_name, nameList(b, entries, .kosmos), nameList(b, entries, .app), nameList(b, entries, .adapter), nameList(b, entries, .package),
    });
    return null;
}

/// Generates a main printing the palettes the file of kosmos `name` declares and installs it
/// as `colors`.
fn addColors(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry, name: []const u8) void {
    const kosmos = kosmosFile(b, entries, name) orelse return;
    const source = b.fmt(
        \\const std = @import("std");
        \\const runner = @import("kosm_runner");
        \\
        \\pub fn main(init: std.process.Init) !u8 {{
        \\    return runner.colors(init, "{f}", @import("{f}"));
        \\}}
        \\
    , .{ std.zig.fmtString(kosmos.name), std.zig.fmtString(kosmos.name) });
    const files = b.addWriteFiles();
    const root_module = b.createModule(.{ .root_source_file = files.add("main.zig", source), .target = target, .optimize = optimize });
    root_module.addImport("kosm_runner", kosm_dependency.module("kosm_runner"));
    for (entries) |entry| root_module.addImport(entry.name, entry.module);
    b.installArtifact(b.addExecutable(.{ .name = "colors", .root_module = root_module }));
}

/// Generates a main reporting what installed package `name` provides and installs it as `inspect`.
fn addInspector(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry, name: []const u8) void {
    const package = for (entries) |entry| {
        if (entry.kind == .package and std.mem.eql(u8, entry.name, name)) break entry;
    } else return fail(b, "there is no installed package '{s}' in build.zig.zon", .{name});

    const source = b.fmt(
        \\const std = @import("std");
        \\const runner = @import("kosm_runner");
        \\
        \\pub fn main(init: std.process.Init) !u8 {{
        \\    return runner.inspect(init, "{f}", @import("{f}"));
        \\}}
        \\
    , .{ std.zig.fmtString(name), std.zig.fmtString(name) });
    const files = b.addWriteFiles();
    const root_module = b.createModule(.{ .root_source_file = files.add("main.zig", source), .target = target, .optimize = optimize });
    root_module.addImport("kosm_runner", kosm_dependency.module("kosm_runner"));
    root_module.addImport(package.name, package.module);
    b.installArtifact(b.addExecutable(.{ .name = "inspect", .root_module = root_module }));
}

/// Generates a main listing every kosmos and installed package and installs it as `list`.
fn addLister(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry) void {
    var source: std.Io.Writer.Allocating = .init(b.allocator);
    const writer = &source.writer;
    writer.writeAll(
        \\const std = @import("std");
        \\const runner = @import("kosm_runner");
        \\
        \\pub fn main(init: std.process.Init) !u8 {
        \\    return runner.list(init, &.{
        \\
    ) catch @panic("OOM");
    for (entries) |entry| {
        if (!canHoldKosmoi(entry)) continue;
        const origin = if (entry.kind == .package) b.fmt("package {s}", .{entry.name}) else entry.origin;
        writer.print("        .{{ .name = \"{f}\", .origin = \"{f}\", .kind = .{s}, .module = @import(\"{f}\") }},\n", .{
            std.zig.fmtString(entry.name), std.zig.fmtString(origin), if (entry.kind == .package) "package" else "local", std.zig.fmtString(entry.name),
        }) catch @panic("OOM");
    }
    writer.writeAll(
        \\    });
        \\}
        \\
    ) catch @panic("OOM");

    const files = b.addWriteFiles();
    const root_module = b.createModule(.{ .root_source_file = files.add("main.zig", source.written()), .target = target, .optimize = optimize });
    root_module.addImport("kosm_runner", kosm_dependency.module("kosm_runner"));
    for (entries) |entry| root_module.addImport(entry.name, entry.module);
    b.installArtifact(b.addExecutable(.{ .name = "list", .root_module = root_module }));
}

/// Every local kosmos, app and adapter, and every installed package but kosm itself: each may
/// declare kosmoi wherever it lives.
fn canHoldKosmoi(entry: Entry) bool {
    return !std.mem.eql(u8, entry.name, "kosm");
}

/// Whether the runner collects the adapters `entry` declares: every installed package but kosm,
/// everything in adapters/, and every local the applied kosmos reaches. Leaving out the
/// rest keeps a broken kosmos the applied one never imports from blocking it.
fn providesAdapters(entry: Entry, reached: []const Entry) bool {
    if (std.mem.eql(u8, entry.name, "kosm")) return false;
    if (entry.kind == .package or entry.kind == .adapter) return true;
    for (reached) |local| {
        if (std.mem.eql(u8, local.name, entry.name)) return true;
    }
    return false;
}

/// The locals `start` reaches through `@import`, itself first, transitively: the walk that keeps
/// manifests up to date. An installed package reaches none, since it cannot import locals.
fn reachedLocals(b: *std.Build, entries: []const Entry, start: Entry) ![]const Entry {
    if (start.local == null) return &.{};
    var reached: std.ArrayList(Entry) = .empty;
    try reached.append(b.allocator, start);
    var index: usize = 0;
    while (index < reached.items.len) : (index += 1) {
        for (try localImports(b, reached.items[index].local.?)) |import_name| {
            const found = for (entries) |entry| {
                if (entry.local != null and std.mem.eql(u8, entry.name, import_name)) break entry;
            } else continue;
            for (reached.items) |already| {
                if (std.mem.eql(u8, already.name, found.name)) break;
            } else try reached.append(b.allocator, found);
        }
    }
    return reached.items;
}

/// Every `@import` in the Zig files of `local`; a directory package leaves out `zig-out/`,
/// `zig-pkg/` and hidden entries, like its manifest.
fn localImports(b: *std.Build, local: Local) ![]const []const u8 {
    const io = b.graph.io;
    var imports: std.ArrayList([]const u8) = .empty;
    if (!local.is_directory) {
        const source = try std.Io.Dir.cwd().readFileAllocOptions(io, try b.root.joinString(b.allocator, local.root), b.allocator, .limited(max_file_size), .of(u8), 0);
        try import_scanner.appendImports(b.allocator, source, &imports);
        return imports.items;
    }
    const directory = local.origin[0 .. local.origin.len - "/".len];
    var dir = try std.Io.Dir.cwd().openDir(io, try b.root.joinString(b.allocator, directory), .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walkSelectively(b.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.basename, ".")) continue;
        if (entry.depth() == 1 and (std.mem.eql(u8, entry.basename, "zig-out") or std.mem.eql(u8, entry.basename, "zig-pkg"))) continue;
        switch (entry.kind) {
            .directory => try walker.enter(io, entry),
            .file => if (std.mem.endsWith(u8, entry.basename, ".zig")) {
                const source = try entry.dir.readFileAllocOptions(io, entry.basename, b.allocator, .limited(max_file_size), .of(u8), 0);
                try import_scanner.appendImports(b.allocator, source, &imports);
            },
            else => {},
        }
    }
    return imports.items;
}

/// The names of every entry of `kind` but kosm itself, comma-separated, or "none".
fn nameList(b: *std.Build, entries: []const Entry, kind: Kind) []const u8 {
    var list: std.ArrayList(u8) = .empty;
    for (entries) |entry| {
        if (entry.kind != kind or std.mem.eql(u8, entry.name, "kosm")) continue;
        if (list.items.len != 0) list.appendSlice(b.allocator, ", ") catch @panic("OOM");
        list.appendSlice(b.allocator, entry.name) catch @panic("OOM");
    }
    return if (list.items.len == 0) "none" else list.items;
}

fn fail(b: *std.Build, comptime format: []const u8, arguments: anytype) void {
    b.getInstallStep().dependOn(&b.addFail(b.fmt(format, arguments)).step);
}
