//! The build of a config project (section 9): every installed package and every local kosmos,
//! app and adapter becomes a module importable by name (D43, D50, D62), and `-Dkosmos=frost.iced`
//! builds `zig-out/bin/kosmos`, the runner for that one kosmos (D45). `-Dinspect=kosm_kitty` builds
//! `zig-out/bin/inspect`, which reports what that installed package provides (D46).

const std = @import("std");

/// The directories holding local kosmoi, apps and adapters, in the config's root.
const local_directories = [_][]const u8{ "kosmoi", "apps", "adapters" };

/// Wires up a config project. `manifest` is the config's `@import("build.zig.zon")`; one of its
/// dependencies must be `kosm`. Problems (a name used twice, an unknown kosmos) fail the build.
pub fn addConfigProject(b: *std.Build, comptime manifest: anytype) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const kosmos_name = b.option([]const u8, "kosmos", "The kosmos to build: frost, or a variant like frost.iced");
    const inspected_name = b.option([]const u8, "inspect", "The installed package to report on, for kosm add and kosm update");

    var names: Names = .{ .b = b };
    inline for (@typeInfo(@TypeOf(manifest.dependencies)).@"struct".field_names) |name| {
        const dependency = b.dependency(name, .{ .target = target, .optimize = optimize });
        const module = dependency.builder.modules.get(name) orelse
            return fail(b, "package '{s}' has no module named '{s}'; its manifest name and module name must match (D51)", .{ name, name });
        if (!names.add(.{ .name = name, .module = module, .origin = b.fmt("package '{s}'", .{name}), .kind = .package })) return;
    }
    const kosm_dependency = for (names.modules.items) |entry| {
        if (std.mem.eql(u8, entry.name, "kosm")) break b.dependency("kosm", .{ .target = target, .optimize = optimize });
    } else return fail(b, "build.zig.zon has no 'kosm' dependency", .{});
    unifyPackages(b, names.modules.items);

    b.dependOnDirectoryContents(b.path("."));
    for (local_directories) |directory| {
        const found = listLocal(b, directory) catch |err| return fail(b, "cannot read {s}/: {s}", .{ directory, @errorName(err) });
        for (found) |local| {
            if (local.missing_root) return fail(b, "{s} is a directory package but has no root.zig (D62)", .{local.origin});
            const module = b.createModule(.{ .root_source_file = b.path(local.root), .target = target, .optimize = optimize });
            const kind: Kind = if (std.mem.eql(u8, directory, "kosmoi")) .kosmos else if (std.mem.eql(u8, directory, "adapters")) .adapter else .app;
            if (!names.add(.{ .name = local.name, .module = module, .origin = local.origin, .kind = kind })) return;
        }
    }
    // Every local module sees every package and every other local module by name (D50).
    for (names.modules.items) |entry| {
        if (entry.kind == .package) continue;
        for (names.modules.items) |other| {
            if (other.module != entry.module) entry.module.addImport(other.name, other.module);
        }
    }

    if (inspected_name) |name| addInspector(b, target, optimize, kosm_dependency, names.modules.items, name);
    const name = kosmos_name orelse return;
    addRunner(b, target, optimize, kosm_dependency, names.modules.items, name);
}

const Kind = enum { package, kosmos, app, adapter };

const Entry = struct {
    name: []const u8,
    module: *std.Build.Module,
    /// For messages: "package 'kosm_kitty'" or "kosmoi/frost.zig".
    origin: []const u8,
    kind: Kind,
};

/// Every module name in the config, refusing a name used twice (D50).
const Names = struct {
    b: *std.Build,
    modules: std.ArrayList(Entry) = .empty,

    /// Adds `entry`, or fails the build and returns false when its name is taken.
    fn add(names: *Names, entry: Entry) bool {
        for (names.modules.items) |existing| {
            if (std.mem.eql(u8, existing.name, entry.name)) {
                fail(names.b, "'{s}' names both {s} and {s}; kosmoi, apps, adapters and packages need unique names (D50)", .{ entry.name, existing.origin, entry.origin });
                return false;
            }
        }
        names.modules.append(names.b.allocator, entry) catch @panic("OOM");
        return true;
    }
};

/// Each package pins its own copies of kosm and other packages, and two copies of kosm are two
/// different `Theme` types. Re-point every import of a package the config has to the config's
/// copy, through the whole module graph (D52).
fn unifyPackages(b: *std.Build, packages: []const Entry) void {
    var visited: std.AutoArrayHashMapUnmanaged(*std.Build.Module, void) = .empty;
    var pending: std.ArrayList(*std.Build.Module) = .empty;
    for (packages) |package| pending.append(b.allocator, package.module) catch @panic("OOM");
    while (pending.pop()) |module| {
        const seen = visited.getOrPut(b.allocator, module) catch @panic("OOM");
        if (seen.found_existing) continue;
        for (module.import_table.keys(), module.import_table.values()) |import_name, imported| {
            pending.append(b.allocator, imported) catch @panic("OOM");
            for (packages) |package| {
                if (std.mem.eql(u8, package.name, import_name)) module.addImport(import_name, package.module);
            }
        }
    }
}

const Local = struct {
    name: []const u8,
    /// The module root, relative to the config root.
    root: []const u8,
    /// For messages: "kosmoi/frost.zig" or "kosmoi/nord/".
    origin: []const u8,
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
            try found.append(b.allocator, .{ .name = b.dupe(entry.name[0 .. entry.name.len - ".zig".len]), .root = path, .origin = path, .missing_root = false });
        } else if (entry.kind == .directory) {
            const package_path = b.fmt("{s}/{s}", .{ directory, entry.name });
            b.dependOnDirectoryContents(b.path(package_path));
            const has_root = if (dir.statFile(io, b.fmt("{s}/root.zig", .{entry.name}), .{})) |_| true else |_| false;
            try found.append(b.allocator, .{
                .name = b.dupe(entry.name),
                .root = b.fmt("{s}/root.zig", .{package_path}),
                .origin = b.fmt("{s}/", .{package_path}),
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
    const file_name = name[0 .. dot orelse name.len];
    const function = if (dot) |index| name[index + 1 ..] else "kosmos";
    const kosmos = for (entries) |entry| {
        if (canHoldKosmoi(entry) and std.mem.eql(u8, entry.name, file_name)) break entry;
    } else return fail(b, "there is no kosmos '{s}' (no kosmoi/{s}.zig, kosmoi/{s}/ or installed package '{s}'); in kosmoi/: {s}; installed packages: {s}", .{
        name, file_name, file_name, file_name, nameList(b, entries, .kosmos), nameList(b, entries, .package),
    });

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
        const has_adapters = entry.kind == .adapter or (entry.kind == .package and !std.mem.eql(u8, entry.name, "kosm"));
        if (has_adapters) writer.print("            @import(\"{f}\"),\n", .{std.zig.fmtString(entry.name)}) catch @panic("OOM");
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

/// Local kosmoi, and installed packages other than kosm itself, which may export kosmoi (D62).
fn canHoldKosmoi(entry: Entry) bool {
    return entry.kind == .kosmos or (entry.kind == .package and !std.mem.eql(u8, entry.name, "kosm"));
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
