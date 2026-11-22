//! The build of a config project: every installed package and every local kosmos, app and
//! adapter becomes a module importable by name, and `-Dkosmos=frost.iced` builds
//! `zig-out/bin/kosmos`, the runner for that one kosmos. `-Dinspect=kosm_kitty` (repeatable) builds
//! `zig-out/bin/inspect`, which reports what each named installed package provides. `-Dlist` builds
//! `zig-out/bin/list`, which lists every kosmos and installed package. `-Dprebuild=frost`
//! (repeatable) compiles the runner of each named kosmos without installing it, so a later
//! `-Dkosmos=` of it is a cache hit, and installs `zig-out/prebuilt/<name>`, an empty file,
//! for each one that compiled. `-Dscripts` builds `zig-out/bin/scripts`, the one runner every
//! script kosmos (`kosmoi/<name>.<extension>`, read by a frontend) shares, holding every kosmos,
//! app and frontend of the config, and installs each frontend's completion files in
//! `zig-out/completions/` and editor files in `zig-out/editor/`. `check` compiles every local
//! one, so editors see the config's imports. An app, adapter or modifier written through a frontend
//! (`apps/<name>.<extension>`, `apps/<name>/root.<extension>`, and the same in `adapters/`,
//! `frontends/` and `colors/`) is the module kosm generates from what its script declares, in
//! `.zig-cache/kosm/modules/`. Each executable a build makes is recorded in `zig-out/built/`, naming
//! its cache folder, so kosm can delete the folders of executables a newer build replaced.

const std = @import("std");
const import_scanner = @import("../src/cli/import_scanner.zig");
const unify = @import("unify.zig").unify;
const app_generator = @import("app_generator.zig");

/// The directories holding local kosmoi, apps, adapters, frontends and modifiers, in the config's root.
const local_directories = [_][]const u8{ "kosmoi", "apps", "adapters", "frontends", "colors" };
/// Local Zig files are small; this only guards against reading something huge.
const max_file_size = 16 * 1024 * 1024;
/// Where the modules of apps and adapters written through a frontend are generated, in the
/// config's root. A fixed path, written only when a module changes, so an unchanged one compiles
/// nothing.
const generated_folder = ".zig-cache/kosm/modules";

/// Wires up a config project. `manifest` is the config's `@import("build.zig.zon")`; one of its
/// dependencies must be `kosm`. Problems (a name used twice, an unknown kosmos) fail the build.
pub fn addConfigProject(b: *std.Build, comptime manifest: anytype) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const kosmos_name = b.option([]const u8, "kosmos", "The kosmos to build: frost, or a variant like frost.iced");
    const inspected_names = b.option([]const []const u8, "inspect", "An installed package to report on, for kosm add and kosm update; repeat it for several");
    const list = b.option(bool, "list", "Build the listing of every kosmos and package, for kosm list") orelse false;
    const prebuilt_names = b.option([]const []const u8, "prebuild", "A kosmos whose runner to compile without installing it, for kosm build; repeat it for several");
    const scripts = b.option(bool, "scripts", "Build the runner every script kosmos shares, for kosm apply and kosm build") orelse false;

    b.dependOnDirectoryContents(b.path("."));
    var locals: [local_directories.len][]const Local = undefined;
    for (local_directories, &locals) |directory, *found| {
        found.* = listLocal(b, directory) catch |err| return fail(b, "cannot read {s}/: {s}", .{ directory, @errorName(err) });
    }
    const has_scripts = found: for (locals) |found| {
        for (found) |local| {
            if (local.script != null) break :found true;
        }
    } else false;

    var names: Names = .{ .b = b };
    inline for (@typeInfo(@TypeOf(manifest.dependencies)).@"struct".field_names) |name| {
        var dependency = b.dependency(name, .{ .target = target, .optimize = optimize });
        // Only the script runner and apps and adapters written through a frontend ask for
        // frontends, so no other build fetches their interpreters.
        if ((scripts or has_scripts) and dependency.builder.available_options_map.contains("frontend")) {
            dependency = b.dependency(name, .{ .target = target, .optimize = optimize, .frontend = true });
        }
        const module = dependency.builder.modules.get(name) orelse
            return fail(b, "package '{s}' has no module named '{s}'; its manifest name and module name must match", .{ name, name });
        if (!names.add(.{ .name = name, .module = module, .origin = b.fmt("package '{s}'", .{name}), .kind = .package })) return;
        const frontend_name = name ++ "_frontend";
        if (dependency.builder.modules.get(frontend_name)) |frontend| {
            if (!names.add(.{ .name = frontend_name, .module = frontend, .origin = b.fmt("package '{s}'", .{name}), .kind = .frontend })) return;
        }
    }
    const kosm_dependency = for (names.modules.items) |entry| {
        if (std.mem.eql(u8, entry.name, "kosm")) break b.dependency("kosm", .{ .target = target, .optimize = optimize });
    } else return fail(b, "build.zig.zon has no 'kosm' dependency", .{});
    if (!unifyPackages(b, names.modules.items)) return;
    if (!addReachedScriptPackages(b, &names)) return;

    for (local_directories, locals) |directory, found| {
        for (found) |local| {
            if (local.missing_root) return fail(b, "{s} is a directory package but has no root.zig", .{local.origin});
            if (local.both_roots) return fail(b, "{s} holds a root.zig and a root script; an app has one root, so remove one", .{local.origin});
            const module = b.createModule(.{ .root_source_file = b.path(local.root), .target = target, .optimize = optimize });
            const kind: Kind = if (std.mem.eql(u8, directory, "kosmoi")) .kosmos else if (std.mem.eql(u8, directory, "adapters")) .adapter else if (std.mem.eql(u8, directory, "frontends")) .local_frontend else if (std.mem.eql(u8, directory, "colors")) .color else .app;
            if (!names.add(.{ .name = local.name, .module = module, .origin = local.origin, .kind = kind, .local = local })) return;
        }
    }
    // Every local module sees every package and every other local module by name.
    for (names.modules.items) |entry| {
        if (entry.kind == .package or entry.kind == .frontend or entry.kind == .reached) continue;
        for (names.modules.items) |other| {
            if (other.kind == .frontend or other.kind == .reached) continue;
            if (other.module != entry.module) entry.module.addImport(other.name, other.module);
        }
    }

    if (has_scripts) addAppGenerator(b, target, optimize, kosm_dependency, names.modules.items);
    if (!checkScriptNames(b, names.modules.items)) return;
    addEditorCheck(b, names.modules.items);
    if (inspected_names) |inspected| addInspector(b, target, optimize, kosm_dependency, names.modules.items, inspected);
    if (list) addLister(b, target, optimize, kosm_dependency, names.modules.items);
    if (prebuilt_names) |prebuilt| addPrebuilt(b, target, optimize, kosm_dependency, names.modules.items, prebuilt);
    if (scripts) addScriptRunner(b, target, optimize, kosm_dependency, names.modules.items);
    const name = kosmos_name orelse return;
    const runner = addRunner(b, target, optimize, kosm_dependency, names.modules.items, name) orelse return;
    b.installArtifact(runner);
    recordBuilt(b, runner, b.fmt("kosmos/{s}", .{name}));
}

/// Installs `zig-out/built/<record>`, which names the cache folder `executable` was built in, so
/// kosm can delete the folders of the executables a newer build replaced. It is Zig source
/// (`pub const path: []const u8 = "...";`), as the build writes it.
fn recordBuilt(b: *std.Build, executable: *std.Build.Step.Compile, record: []const u8) void {
    const options = b.addOptions();
    options.addOptionPathUntracked("path", executable.getEmittedBin());
    // Untracked paths add no dependency of their own.
    options.step.dependOn(&executable.step);
    b.getInstallStep().dependOn(&b.addInstallFile(options.getOutput(), b.fmt("built/{s}", .{record})).step);
}

/// Compiles the runner of each kosmos in `names`, as `-Dkosmos=` would but without installing
/// it, and marks each that compiled with `zig-out/prebuilt/<name>`. Zig builds the others after
/// one fails, and each step is named after its kosmos, so its errors say which one it is.
fn addPrebuilt(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry, names: []const []const u8) void {
    const markers = b.addWriteFiles();
    for (names) |name| {
        const runner = addRunner(b, target, optimize, kosm_dependency, entries, name) orelse continue;
        runner.step.name = b.fmt("compile kosmos {s}", .{name});
        // Without a user of the binary Zig compiles with -fno-emit-bin, which a later
        // -Dkosmos= build would not find in the cache.
        _ = runner.getEmittedBin();
        const marker = b.addInstallFile(markers.add(name, ""), b.fmt("prebuilt/{s}", .{name}));
        marker.step.dependOn(&runner.step);
        b.getInstallStep().dependOn(&marker.step);
        recordBuilt(b, runner, b.fmt("kosmos/{s}", .{name}));
    }
}

/// A `check` step compiling every local kosmos, app and adapter, which `zig build` and kosm never
/// run. Editors read the module graph from the build's steps, so it is what gives ZLS every
/// import of the config.
fn addEditorCheck(b: *std.Build, entries: []const Entry) void {
    const check = b.step("check", "Compile every local kosmos, app and adapter; editors read their imports from it");
    for (entries) |entry| {
        if (entry.kind == .package or entry.kind == .reached) continue;
        const object = b.addObject(.{ .name = entry.name, .root_module = entry.module });
        dependOnGenerated(object, entries);
        check.dependOn(&object.step);
    }
}

const Kind = enum {
    package,
    /// A package the config does not list, reached through one it does, whose root is a script:
    /// the runner of scripts needs its folder to read the script.
    reached,
    /// A package's frontend module (`kosm_lua_frontend`), present only in script runner builds.
    frontend,
    kosmos,
    app,
    adapter,
    /// A frontend in `frontends/`, Zig or a script.
    local_frontend,
    /// A module in `colors/`: a modifier written through a frontend, or Zig.
    color,
};

const Entry = struct {
    name: []const u8,
    module: *std.Build.Module,
    /// For messages: "package 'kosm_kitty'" or "kosmoi/frost.zig".
    origin: []const u8,
    kind: Kind,
    /// Where a local kosmos, app or adapter lives; null for a package.
    local: ?Local = null,
    /// What writes the module of an app written through a frontend; null for any other.
    generated: ?*std.Build.Step = null,
};

/// Makes `compile`, which imports `entries`, wait for the modules generated for apps written
/// through a frontend, which it may compile.
fn dependOnGenerated(compile: *std.Build.Step.Compile, entries: []const Entry) void {
    for (entries) |entry| {
        if (entry.generated) |step| compile.step.dependOn(step);
    }
}

/// Builds the generator of the modules of apps and adapters written through a frontend, from
/// every frontend the config holds, and runs it on each such script; every compile importing
/// them waits for it.
/// The run is cached on the scripts, and rewrites only the modules whose contents change.
fn addAppGenerator(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []Entry) void {
    var frontends: std.ArrayList(app_generator.FrontendModule) = .empty;
    for (entries) |entry| {
        if (!givesFrontends(entry)) continue;
        const package = if (entry.kind == .frontend) entry.name[0 .. entry.name.len - "_frontend".len] else entry.name;
        frontends.append(b.allocator, .{ .package = package, .name = entry.name, .module = entry.module }) catch @panic("OOM");
    }
    const generator = app_generator.addGenerator(b, target, optimize, kosm_dependency.module("kosm_runner"), frontends.items);
    recordBuilt(b, generator, "kosm-apps");

    const run = b.addRunArtifact(generator);
    run.addArg(b.root.joinString(b.allocator, generated_folder) catch @panic("OOM"));
    var modules: std.ArrayList(u8) = .empty;
    for (entries) |entry| {
        if (entry.kind == .frontend or entry.kind == .reached) continue;
        if (modules.items.len != 0) modules.append(b.allocator, ',') catch @panic("OOM");
        modules.appendSlice(b.allocator, entry.name) catch @panic("OOM");
    }
    run.addArg(modules.items);
    for (entries) |entry| {
        const script = (entry.local orelse continue).script orelse continue;
        run.addFileArg2(b.path(script), .{ .prefix = b.fmt("{s}={s}=", .{ entry.name, script }), .make_absolute = true });
    }
    // Captured, so the run has an output and is cached on its inputs, the scripts.
    _ = run.captureStdOut(.{});
    for (entries) |*entry| {
        if ((entry.local orelse continue).script != null) entry.generated = &run.step;
    }
}

/// The name `~~kosmos/` takes in paths, which no module may have.
const reserved_name = "kosmos";

/// Every module name in the config, refusing a name used twice or the reserved one.
const Names = struct {
    b: *std.Build,
    modules: std.ArrayList(Entry) = .empty,

    /// Adds `entry`, or fails the build and returns false when its name is taken.
    fn add(names: *Names, entry: Entry) bool {
        if (std.mem.eql(u8, entry.name, reserved_name)) {
            fail(names.b, "{s} is named '{s}', which paths take for the applied kosmos' folder (~~{s}/); rename it", .{ entry.origin, reserved_name, reserved_name });
            return false;
        }
        for (names.modules.items) |existing| {
            if (std.mem.eql(u8, existing.name, entry.name)) {
                fail(names.b, "'{s}' names both {s} and {s}; kosmoi, apps, adapters and packages need unique names", .{ entry.name, existing.origin, entry.origin });
                return false;
            }
        }
        names.modules.append(names.b.allocator, entry) catch @panic("OOM");
        return true;
    }

    /// The entry named `name`, or null.
    fn find(names: *const Names, name: []const u8) ?Entry {
        for (names.modules.items) |existing| {
            if (std.mem.eql(u8, existing.name, name)) return existing;
        }
        return null;
    }
};

/// Adds every package whose root is a script that the config's packages reach without the config
/// listing it, so the runner of scripts finds its script and hands scripts its types. Fails the
/// build and returns false when one shares a name with the config's modules.
fn addReachedScriptPackages(b: *std.Build, names: *Names) bool {
    var visited: std.AutoHashMapUnmanaged(*std.Build.Module, void) = .empty;
    var pending: std.ArrayList(*std.Build.Module) = .empty;
    for (names.modules.items) |entry| {
        if (entry.kind == .package) pending.append(b.allocator, entry.module) catch @panic("OOM");
    }
    while (pending.pop()) |module| {
        if ((visited.getOrPut(b.allocator, module) catch @panic("OOM")).found_existing) continue;
        for (module.import_table.keys(), module.import_table.values()) |name, imported| {
            pending.append(b.allocator, imported) catch @panic("OOM");
            if (names.find(name) != null or !isScriptPackage(b, name, imported)) continue;
            if (!names.add(.{ .name = name, .module = imported, .origin = b.fmt("package '{s}'", .{name}), .kind = .reached })) return false;
        }
    }
    return true;
}

/// Whether `module` is the module of package `name` whose root is a script: the one its own
/// build exposes under that name, from a folder holding a root script and no `root.zig`.
fn isScriptPackage(b: *std.Build, name: []const u8, module: *std.Build.Module) bool {
    const owner = module.owner;
    if (owner.modules.get(name) != module) return false;
    const io = b.graph.io;
    var dir = std.Io.Dir.cwd().openDir(io, owner.root.joinString(b.allocator, "") catch @panic("OOM"), .{ .iterate = true }) catch return false;
    defer dir.close(io);
    if (dir.access(io, "root.zig", .{})) |_| return false else |_| {}
    return (app_generator.scriptRootIn(b, dir) catch return false) != null;
}

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
    /// A directory holding both a root.zig and a root script.
    both_roots: bool = false,
    /// The script of an app or adapter written through a frontend, relative to the config root; its
    /// `root` is then the module kosm generates from it.
    script: ?[]const u8 = null,
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
    // Apps, adapters and frontends may be scripts; a kosmos script is read by the runner, not built.
    const holds_scripts = !std.mem.eql(u8, directory, "kosmoi");
    while (try iterator.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const path = b.fmt("{s}/{s}", .{ directory, entry.name });
            try found.append(b.allocator, .{ .name = b.dupe(entry.name[0 .. entry.name.len - ".zig".len]), .root = path, .origin = path, .is_directory = false, .missing_root = false });
        } else if (holds_scripts and (entry.kind == .file or entry.kind == .sym_link) and isScriptFile(entry.name)) {
            const path = b.fmt("{s}/{s}", .{ directory, entry.name });
            const name = b.dupe(scriptStem(entry.name));
            try found.append(b.allocator, .{ .name = name, .root = generatedRoot(b, name), .origin = path, .is_directory = false, .missing_root = false, .script = path });
        } else if (entry.kind == .directory) {
            const package_path = b.fmt("{s}/{s}", .{ directory, entry.name });
            b.dependOnDirectoryContents(b.path(package_path));
            const has_root = if (dir.statFile(io, b.fmt("{s}/root.zig", .{entry.name}), .{})) |_| true else |_| false;
            const script_root_file = try scriptRootFile(b, dir, entry.name);
            // A kosmos folder whose root is a script holds no Zig module unless it has a root.zig.
            if (!has_root and std.mem.eql(u8, directory, "kosmoi") and script_root_file != null) continue;
            if (holds_scripts and script_root_file != null) {
                const name = b.dupe(entry.name);
                try found.append(b.allocator, .{
                    .name = name,
                    .root = generatedRoot(b, name),
                    .origin = b.fmt("{s}/", .{package_path}),
                    .is_directory = true,
                    .missing_root = false,
                    .both_roots = has_root,
                    .script = b.fmt("{s}/{s}", .{ package_path, script_root_file.? }),
                });
                continue;
            }
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

/// The file name of the script in the folder `name` of `dir` giving its kosmos or app: `root`
/// with an extension other than Zig's and its manifests'; null for none.
fn scriptRootFile(b: *std.Build, dir: std.Io.Dir, name: []const u8) !?[]const u8 {
    var folder = try dir.openDir(b.graph.io, name, .{ .iterate = true });
    defer folder.close(b.graph.io);
    return app_generator.scriptRootIn(b, folder);
}

/// Whether the generator looks for frontends in `entry`: a package's frontend module, or a Zig
/// module in adapters/ or frontends/. A script there is a module the generator writes, so never
/// one of them.
fn givesFrontends(entry: Entry) bool {
    if (entry.kind == .frontend) return true;
    if (entry.kind != .adapter and entry.kind != .local_frontend) return false;
    return (entry.local orelse return true).script == null;
}

/// The generated module of the app or adapter `name` written through a frontend, relative to the
/// config root.
fn generatedRoot(b: *std.Build, name: []const u8) []const u8 {
    return b.fmt("{s}/{s}.zig", .{ generated_folder, name });
}

const script_root = app_generator.script_root;
const isScriptFile = app_generator.isScriptFile;
const scriptStem = app_generator.scriptStem;

fn localLessThan(_: void, left: Local, right: Local) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// Generates the runner's main for kosmos `name` ("frost" or "frost.iced") and returns the
/// executable `kosmos` compiling it. Fails the build and returns null when `name` names no
/// kosmos file or its imports can't be read.
fn addRunner(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry, name: []const u8) ?*std.Build.Step.Compile {
    const dot = std.mem.findScalar(u8, name, '.');
    const function = if (dot) |index| name[index + 1 ..] else "kosmos";
    const kosmos = kosmosFile(b, entries, name) orelse return null;
    const folder = moduleFolder(b, kosmos) orelse return null;
    const reached = reachedLocals(b, entries, kosmos) catch |err| {
        fail(b, "cannot read the imports of {s}: {s}", .{ kosmos.origin, @errorName(err) });
        return null;
    };

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
        \\        .config = "{f}",
        \\        .folder = "{f}",
        \\        .file = @import("{f}"),
        \\        .function = "{f}",
        \\        .folders = &.{{
        \\
    , .{
        std.zig.fmtString(name),
        std.zig.fmtString(kosmos.origin),
        std.zig.fmtString(b.root.joinString(b.allocator, "") catch @panic("OOM")),
        std.zig.fmtString(folder),
        std.zig.fmtString(kosmos.name),
        std.zig.fmtString(function),
    }) catch @panic("OOM");
    if (!writeFolders(b, writer, entries)) return null;
    writer.writeAll(
        \\        },
        \\        .adapter_sources = &.{
        \\
    ) catch @panic("OOM");
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
    const runner = b.addExecutable(.{ .name = "kosmos", .root_module = root_module });
    dependOnGenerated(runner, entries);
    return runner;
}

/// Writes one `Places.Folder` line per entry; fails the build and returns false when a
/// module's folder is unknown.
fn writeFolders(b: *std.Build, writer: *std.Io.Writer, entries: []const Entry) bool {
    for (entries) |entry| {
        const entry_folder = moduleFolder(b, entry) orelse return false;
        writer.print("            .{{ .name = \"{f}\", .path = \"{f}\" }},\n", .{ std.zig.fmtString(entry.name), std.zig.fmtString(entry_folder) }) catch @panic("OOM");
    }
    return true;
}

/// Generates the main of the runner every script kosmos shares and installs it as `scripts`:
/// it holds every kosmos, every app a kosmos without a base may choose, and every adapter and
/// frontend, so a script may build on any of them.
fn addScriptRunner(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry) void {
    var source: std.Io.Writer.Allocating = .init(b.allocator);
    const writer = &source.writer;
    writer.print(
        \\const std = @import("std");
        \\const runner = @import("kosm_runner");
        \\
        \\pub fn main(init: std.process.Init) !u8 {{
        \\    return runner.runScript(init, .{{
        \\        .config = "{f}",
        \\        .folders = &.{{
        \\
    , .{std.zig.fmtString(b.root.joinString(b.allocator, "") catch @panic("OOM"))}) catch @panic("OOM");
    if (!writeFolders(b, writer, entries)) return;
    writer.writeAll(
        \\        },
        \\        .kosmoi = &.{
        \\
    ) catch @panic("OOM");
    for (entries) |entry| {
        if (!canHoldKosmoi(entry)) continue;
        const folder = moduleFolder(b, entry) orelse return;
        const origin = if (entry.kind == .package) b.fmt("package {s}", .{entry.name}) else entry.origin;
        writer.print("            .{{ .name = \"{f}\", .origin = \"{f}\", .folder = \"{f}\", .module = @import(\"{f}\") }},\n", .{
            std.zig.fmtString(entry.name), std.zig.fmtString(origin), std.zig.fmtString(folder), std.zig.fmtString(entry.name),
        }) catch @panic("OOM");
    }
    writer.writeAll(
        \\        },
        \\        .apps = &.{
        \\
    ) catch @panic("OOM");
    for (entries) |entry| {
        if (!canHoldKosmoi(entry) or (entry.kind != .package and entry.kind != .app)) continue;
        writer.print("            .{{ .package = \"{f}\", .module = @import(\"{f}\") }},\n", .{ std.zig.fmtString(entry.name), std.zig.fmtString(entry.name) }) catch @panic("OOM");
    }
    writer.writeAll(
        \\        },
        \\        .adapter_sources = &.{
        \\
    ) catch @panic("OOM");
    for (entries) |entry| {
        if (!canHoldKosmoi(entry) and entry.kind != .frontend) continue;
        const package = if (entry.kind == .frontend) entry.name[0 .. entry.name.len - "_frontend".len] else entry.name;
        writer.print("            .{{ .package = \"{f}\", .module = @import(\"{f}\") }},\n", .{ std.zig.fmtString(package), std.zig.fmtString(entry.name) }) catch @panic("OOM");
    }
    writer.writeAll(
        \\        },
        \\        .reached = &.{
        \\
    ) catch @panic("OOM");
    for (entries) |entry| {
        if (entry.kind == .reached) writer.print("            @import(\"{f}\"),\n", .{std.zig.fmtString(entry.name)}) catch @panic("OOM");
    }
    writer.writeAll(
        \\        },
        \\    });
        \\}
        \\
    ) catch @panic("OOM");

    const files = b.addWriteFiles();
    const root_module = b.createModule(.{ .root_source_file = files.add("main.zig", source.written()), .target = target, .optimize = optimize });
    root_module.addImport("kosm_runner", kosm_dependency.module("kosm_runner"));
    for (entries) |entry| root_module.addImport(entry.name, entry.module);
    const runner = b.addExecutable(.{ .name = "scripts", .root_module = root_module });
    dependOnGenerated(runner, entries);
    b.installArtifact(runner);
    recordBuilt(b, runner, "scripts");
    addScriptCompletions(b, runner, entries);
}

/// Runs the script runner to write each frontend's completion files into
/// `zig-out/completions/<frontend>/` and its editor files into `zig-out/editor/`, handing it
/// the root file of every module, whose sources hold the doc comments.
fn addScriptCompletions(b: *std.Build, runner: *std.Build.Step.Compile, entries: []const Entry) void {
    const run = b.addRunArtifact(runner);
    // Docs are read from the sources, and an edit of a doc comment alone leaves the runner as it was.
    run.has_side_effects = true;
    run.addArg("--write-completions");
    const completions = run.addOutputDirectoryArg2("completions", .{});
    const editor = run.addOutputDirectoryArg2("editor", .{});
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (entries) |entry| addModuleRoots(b, run, entry.name, entry.module, &seen);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{ .source_dir = completions, .install_dir = .prefix, .install_subdir = "completions" }).step);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{ .source_dir = editor, .install_dir = .prefix, .install_subdir = "editor" }).step);
}

/// Passes `<name>=<root file>` for `module` and every module it imports, each name once.
fn addModuleRoots(b: *std.Build, run: *std.Build.Step.Run, name: []const u8, module: *std.Build.Module, seen: *std.StringHashMapUnmanaged(void)) void {
    if (seen.contains(name)) return;
    seen.put(b.allocator, name, {}) catch @panic("OOM");
    if (module.root_source_file) |root| run.addFileArg2(root, .{ .prefix = b.fmt("{s}=", .{name}), .make_absolute = true });
    for (module.import_table.keys(), module.import_table.values()) |imported_name, imported| addModuleRoots(b, run, imported_name, imported, seen);
}

/// A script kosmos in `kosmoi/` or a kosmos folder in it: a file with an extension other than
/// Zig's and its manifests'.
const ScriptFile = struct {
    /// Its name, the file name before the first dot ("minimal"), after its kosmos' name in a
    /// kosmos folder ("personal.nord").
    name: []const u8,
    /// "kosmoi/minimal.lua", "kosmoi/personal/nord.lua".
    origin: []const u8,
};

/// Every script kosmos in `kosmoi/` and its kosmos folders, sorted by name; null after failing
/// the build.
fn scriptFiles(b: *std.Build) ?[]const ScriptFile {
    const io = b.graph.io;
    const full_path = b.root.joinString(b.allocator, "kosmoi") catch @panic("OOM");
    var dir = std.Io.Dir.cwd().openDir(io, full_path, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);
    var found: std.ArrayList(ScriptFile) = .empty;
    if (!appendScripts(b, dir, "kosmoi", "", &found)) return null;
    var iterator = dir.iterate();
    while (iterator.next(io) catch |err| {
        fail(b, "cannot read kosmoi/: {s}", .{@errorName(err)});
        return null;
    }) |entry| {
        if (entry.kind != .directory or std.mem.startsWith(u8, entry.name, ".")) continue;
        var folder = dir.openDir(io, entry.name, .{ .iterate = true }) catch |err| {
            fail(b, "cannot read kosmoi/{s}/: {s}", .{ entry.name, @errorName(err) });
            return null;
        };
        defer folder.close(io);
        if (!appendScripts(b, folder, b.fmt("kosmoi/{s}", .{entry.name}), b.fmt("{s}.", .{entry.name}), &found)) return null;
    }
    std.mem.sort(ScriptFile, found.items, {}, scriptLessThan);
    return found.items;
}

/// Appends every script in `dir`, the config's folder `shown`, each named after `prefix` and its
/// file name before the first dot; returns false after failing the build.
fn appendScripts(b: *std.Build, dir: std.Io.Dir, shown: []const u8, prefix: []const u8, found: *std.ArrayList(ScriptFile)) bool {
    var iterator = dir.iterate();
    while (iterator.next(b.graph.io) catch |err| {
        fail(b, "cannot read {s}/: {s}", .{ shown, @errorName(err) });
        return false;
    }) |file| {
        if (file.kind != .file and file.kind != .sym_link) continue;
        if (!isScriptFile(file.name)) continue;
        const stem = scriptStem(file.name);
        // A folder's root script gives the kosmos named after the folder.
        const name = if (prefix.len != 0 and std.mem.eql(u8, stem, script_root)) b.dupe(prefix[0 .. prefix.len - 1]) else b.fmt("{s}{s}", .{ prefix, stem });
        found.append(b.allocator, .{ .name = name, .origin = b.fmt("{s}/{s}", .{ shown, file.name }) }) catch @panic("OOM");
    }
    return true;
}

fn scriptLessThan(_: void, left: ScriptFile, right: ScriptFile) bool {
    return std.mem.order(u8, left.name, right.name) == .lt;
}

/// Fails the build and returns false when a script kosmos in `kosmoi/` shares its name with a
/// module, which `kosm apply` could not tell apart. A folder's root script shares it with the
/// folder's own module, whose variants the runner tells apart from the script's.
fn checkScriptNames(b: *std.Build, entries: []const Entry) bool {
    const found = scriptFiles(b) orelse return false;
    for (found) |script| {
        for (entries) |entry| {
            const own_folder = entry.kind == .kosmos and std.mem.startsWith(u8, script.origin, entry.origin) and
                std.mem.eql(u8, scriptStem(std.Io.Dir.path.basename(script.origin)), script_root);
            if (std.mem.eql(u8, entry.name, script.name) and !own_folder) {
                fail(b, "'{s}' names both the script {s} and {s}; kosmoi, apps, adapters and packages need unique names", .{ script.name, script.origin, entry.origin });
                return false;
            }
        }
    }
    return true;
}

/// The absolute folder of a package, or of a local module's root file: what `~~<name>/` stands
/// for, and for a kosmos where its relative paths start. Fails the build and returns null when the root is no file of
/// the config or a package.
fn moduleFolder(b: *std.Build, entry: Entry) ?[]const u8 {
    // An app written through a frontend lives where its script is, not where its module is.
    if (entry.local) |local| if (local.script) |script| {
        const config_root = b.root.joinString(b.allocator, "") catch @panic("OOM");
        return std.Io.Dir.path.resolveAlloc(b.allocator, &.{ config_root, std.Io.Dir.path.dirname(script) orelse "." }) catch @panic("OOM");
    };
    // A package's folder is its own root, where its manifest and files sit, wherever its
    // module's root file is (a package written in a script has its module generated).
    const config_root = b.root.joinString(b.allocator, "") catch @panic("OOM");
    // A `.path` dependency's root is relative to the config's.
    if (entry.kind == .package or entry.kind == .reached) return std.Io.Dir.path.resolveAlloc(b.allocator, &.{ config_root, entry.module.owner.root.joinString(b.allocator, "") catch @panic("OOM") }) catch @panic("OOM");
    const root = entry.module.root_source_file orelse {
        fail(b, "{s}: the module has no root file, so its folder is unknown", .{entry.origin});
        return null;
    };
    const sub_path = switch (root) {
        .src_path => |source| source.sub_path,
        .dependency => |dependency| dependency.sub_path,
        else => "",
    };
    const file = switch (root) {
        .src_path => |source| source.owner.root.joinString(b.allocator, sub_path),
        .dependency => |dependency| dependency.dependency.builder.root.joinString(b.allocator, sub_path),
        else => {
            fail(b, "{s}: the module's root is not a file of the config or a package, so its folder is unknown", .{entry.origin});
            return null;
        },
    } catch @panic("OOM");
    const folder = std.Io.Dir.path.dirname(file) orelse file;
    return std.Io.Dir.path.resolveAlloc(b.allocator, &.{ config_root, folder }) catch @panic("OOM");
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

/// Generates a main reporting what each installed package in `inspected` provides, in order,
/// and installs it as `inspect`. One build checks them all, since each `zig build` costs a
/// configure of the whole dependency tree.
fn addInspector(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, kosm_dependency: *std.Build.Dependency, entries: []const Entry, inspected: []const []const u8) void {
    var source: std.Io.Writer.Allocating = .init(b.allocator);
    const writer = &source.writer;
    writer.writeAll(
        \\pub fn main(init: @import("std").process.Init) !u8 {
        \\    return @import("kosm_runner").inspect(init, .{
        \\
    ) catch @panic("OOM");
    // A tuple, not a struct of declarations, so no package name can clash with another name.
    const packages = b.allocator.alloc(Entry, inspected.len) catch @panic("OOM");
    for (inspected, packages, 0..) |name, *package, index| {
        package.* = findPackage(entries, name) orelse return fail(b, "there is no installed package '{s}' in build.zig.zon", .{name});
        for (inspected[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier, name)) return fail(b, "package '{s}' is inspected twice", .{name});
        }
        writer.print("        .{{ \"{f}\", @import(\"{f}\") }},\n", .{ std.zig.fmtString(name), std.zig.fmtString(name) }) catch @panic("OOM");
    }
    writer.writeAll(
        \\    });
        \\}
        \\
    ) catch @panic("OOM");
    const files = b.addWriteFiles();
    const root_module = b.createModule(.{ .root_source_file = files.add("main.zig", source.written()), .target = target, .optimize = optimize });
    root_module.addImport("kosm_runner", kosm_dependency.module("kosm_runner"));
    for (packages) |package| root_module.addImport(package.name, package.module);
    const inspector = b.addExecutable(.{ .name = "inspect", .root_module = root_module });
    dependOnGenerated(inspector, entries);
    b.installArtifact(inspector);
    recordBuilt(b, inspector, "inspect");
}

fn findPackage(entries: []const Entry, name: []const u8) ?Entry {
    for (entries) |entry| {
        if (entry.kind == .package and std.mem.eql(u8, entry.name, name)) return entry;
    }
    return null;
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
        \\    }, &.{
        \\
    ) catch @panic("OOM");
    for (scriptFiles(b) orelse return) |script| {
        writer.print("        .{{ .name = \"{f}\", .origin = \"{f}\" }},\n", .{ std.zig.fmtString(script.name), std.zig.fmtString(script.origin) }) catch @panic("OOM");
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
    const list_executable = b.addExecutable(.{ .name = "list", .root_module = root_module });
    dependOnGenerated(list_executable, entries);
    b.installArtifact(list_executable);
    recordBuilt(b, list_executable, "list");
}

/// Every local kosmos, app and adapter, and every installed package but kosm itself: each may
/// declare kosmoi wherever it lives. A frontend module declares only its frontend.
fn canHoldKosmoi(entry: Entry) bool {
    return entry.kind != .frontend and entry.kind != .reached and !std.mem.eql(u8, entry.name, "kosm");
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
    // A script holds no Zig, and its generated module imports only packages.
    if (local.script != null) return imports.items;
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
