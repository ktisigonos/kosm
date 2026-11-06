//! Keeps the manifests of local directory packages up to date (D62, D76): each `build.zig.zon`
//! depends on kosm and exactly the packages its directory imports, and lists every file it
//! holds. An apply refreshes the applied kosmos and every directory package it reaches.

const std = @import("std");
const builtin = @import("builtin");
const Context = @import("Context.zig");
const files = @import("files.zig");
const import_scanner = @import("import_scanner.zig");
const manifest = @import("manifest.zig");

pub const Error = Context.Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

/// `write` brings the files up to date; `report` (for `--diff`, D37) only prints what it would change.
pub const Mode = enum { write, report };

/// The one-line build every directory package has (D62), written once.
const build_file =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    @import("kosm").package(b);
    \\}
    \\
;
const build_name = "build.zig";
const manifest_name = "build.zig.zon";
const kosm_name = "kosm";
/// The directories holding local kosmoi, apps and adapters, as the config build reads them.
pub const local_directories = [_][]const u8{ "kosmoi", "apps", "adapters" };
/// Kosmos files and manifests are small; this only guards against reading something huge.
const max_file_size = 16 * 1024 * 1024;

/// Before kosmos `name` ("nord" or "nord.iced") is applied, brings up to date the build files
/// of every local directory package it reaches through imports, itself included when it is a
/// directory, in any of the local folders (D76, D87). With `.report` it only prints which files would change. Every
/// manifest is checked before any is written, so a failure writes nothing.
pub fn refreshApplied(context: Context, name: []const u8, mode: Mode) Error!void {
    const kosmos_name = name[0 .. std.mem.findScalar(u8, name, '.') orelse name.len];
    const start = try find(context, kosmos_name) orelse return;

    var reached: std.ArrayList(Local) = .empty;
    try reached.append(context.arena, start);
    var directories: std.ArrayList(Reached) = .empty;
    var index: usize = 0;
    while (index < reached.items.len) : (index += 1) {
        const local = reached.items[index];
        const imports = switch (local.kind) {
            .file => try fileImports(context, local.path),
            .directory => blk: {
                const contents = try listContents(context, local.path);
                try directories.append(context.arena, .{ .directory = local.path, .contents = contents });
                break :blk contents.imports;
            },
        };
        for (imports) |import_name| {
            if (isReached(reached.items, import_name)) continue;
            if (try find(context, import_name)) |found| try reached.append(context.arena, found);
        }
    }
    // The applied kosmos first, then the rest by path, so the output does not depend on walk order.
    const first_sorted: usize = if (start.kind == .directory) 1 else 0;
    std.mem.sort(Reached, directories.items[first_sorted..], {}, reachedLessThan);

    var changes: std.ArrayList(Change) = .empty;
    for (directories.items) |directory| try planPackage(context, directory, directories.items, &changes);
    for (changes.items) |change| try save(context, mode, change);
}

/// Writes the build files of directory package `directory` ("apps/my_bar"), relative to the
/// config: `build.zig` if missing, and `build.zig.zon` when it is missing or stale.
pub fn refresh(context: Context, directory: []const u8, mode: Mode) Error!void {
    var changes: std.ArrayList(Change) = .empty;
    const package: Reached = .{ .directory = directory, .contents = try listContents(context, directory) };
    try planPackage(context, package, &.{package}, &changes);
    for (changes.items) |change| try save(context, mode, change);
}

/// A local kosmos, app or adapter: a single file (`kosmoi/frost.zig`) or a directory package
/// (`apps/my_bar`).
const Local = struct {
    name: []const u8,
    /// Relative to the config.
    path: []const u8,
    kind: enum { file, directory },
};

/// A directory package reached from the applied kosmos, with what it holds.
const Reached = struct {
    directory: []const u8,
    contents: Contents,
};

/// A file to write, decided before anything is written.
const Change = struct {
    path: []const u8,
    bytes: []const u8,
    kind: enum { create, update },
};

/// The local kosmos, app or adapter `name`, or null when there is none (an installed package,
/// `std`, a relative file).
fn find(context: Context, name: []const u8) Error!?Local {
    for (local_directories) |directory| {
        if (try findIn(context, directory, name)) |found| return found;
    }
    return null;
}

/// `name` in local directory `directory` ("kosmoi"), as a file or a directory, or null.
fn findIn(context: Context, directory: []const u8, name: []const u8) Error!?Local {
    const file = try context.arena.print("{s}/{s}.zig", .{ directory, name });
    if (try kindOf(context, file) == .file) return .{ .name = name, .path = file, .kind = .file };
    const package = try std.Io.Dir.path.join(context.arena, &.{ directory, name });
    if (try kindOf(context, package) == .directory) return .{ .name = name, .path = package, .kind = .directory };
    return null;
}

fn isReached(reached: []const Local, name: []const u8) bool {
    for (reached) |local| {
        if (std.mem.eql(u8, local.name, name)) return true;
    }
    return false;
}

/// Every `@import` of single-file package `path`.
fn fileImports(context: Context, path: []const u8) Error![]const []const u8 {
    const source = try read(context, path) orelse return context.fail("cannot read {s}: it disappeared", .{path});
    var imports: std.ArrayList([]const u8) = .empty;
    try import_scanner.appendImports(context.arena, source, &imports);
    return imports.items;
}

/// Adds the build files `package` needs to `changes`, or nothing when they are up to date.
/// `refreshed` are the packages getting a manifest in the same run, `package` among them.
fn planPackage(context: Context, package: Reached, refreshed: []const Reached, changes: *std.ArrayList(Change)) Error!void {
    const directory = package.directory;
    const contents = package.contents;
    const package_name = std.Io.Dir.path.basename(directory);
    if (!std.zig.isValidId(package_name)) {
        return context.fail("{s}/ cannot be a package: its name must be a Zig identifier (D51)", .{directory});
    }

    const config_manifest = try read(context, manifest_name) orelse return context.fail("{s} has no {s}", .{ context.config, manifest_name });
    const dependencies = try packageDependencies(context, package_name, directory, config_manifest, contents.imports, refreshed);

    const build_path = try std.Io.Dir.path.join(context.arena, &.{ directory, build_name });
    const manifest_path = try std.Io.Dir.path.join(context.arena, &.{ directory, manifest_name });
    const create_build = try kindOf(context, build_path) == .missing;
    const existing = try read(context, manifest_path);
    const base = existing orelse try newManifest(context, package_name, config_manifest);
    var paths: std.ArrayList([]const u8) = .fromOwnedSlice(try context.arena.dupe([]const u8, contents.files));
    if (create_build) try paths.append(context.arena, build_name);
    if (existing == null) try paths.append(context.arena, manifest_name);
    const updated = render(context.arena, base, dependencies, paths.items) catch |err| return invalidManifest(context, err, manifest_path);

    if (create_build) try changes.append(context.arena, .{ .path = build_path, .bytes = build_file, .kind = .create });
    if (existing == null or !std.mem.eql(u8, existing.?, updated)) {
        try changes.append(context.arena, .{ .path = manifest_path, .bytes = updated, .kind = if (existing == null) .create else .update });
    }
}

/// `source` with `.dependencies` and `.paths` set; `paths` are sorted here.
fn render(arena: std.mem.Allocator, source: [:0]const u8, dependencies: []const manifest.Dependency, paths: [][]const u8) manifest.Error![]const u8 {
    std.mem.sort([]const u8, paths, {}, stringLessThan);
    var dependencies_text: std.Io.Writer.Allocating = .init(arena);
    writeDependencies(&dependencies_text.writer, dependencies) catch return error.OutOfMemory;
    var paths_text: std.Io.Writer.Allocating = .init(arena);
    writePaths(&paths_text.writer, paths) catch return error.OutOfMemory;
    const with_dependencies = try manifest.withField(arena, source, "dependencies", dependencies_text.written());
    return manifest.withField(arena, try arena.dupeSentinel(u8, with_dependencies, 0), "paths", paths_text.written());
}

fn writeDependencies(writer: *std.Io.Writer, dependencies: []const manifest.Dependency) std.Io.Writer.Error!void {
    try writer.writeAll(".{\n");
    for (dependencies) |dependency| {
        try writer.print("        .{f} = .{{\n", .{std.zig.fmtId(dependency.name)});
        if (dependency.url) |url| try writer.print("            .url = \"{f}\",\n", .{std.zig.fmtString(url)});
        if (dependency.hash) |hash| try writer.print("            .hash = \"{f}\",\n", .{std.zig.fmtString(hash)});
        if (dependency.path) |path| try writer.print("            .path = \"{f}\",\n", .{std.zig.fmtString(path)});
        if (dependency.lazy) |lazy| try writer.print("            .lazy = {},\n", .{lazy});
        try writer.writeAll("        },\n");
    }
    try writer.writeAll("    }");
}

fn writePaths(writer: *std.Io.Writer, paths: []const []const u8) std.Io.Writer.Error!void {
    try writer.writeAll(".{\n");
    for (paths) |path| try writer.print("        \"{f}\",\n", .{std.zig.fmtString(path)});
    try writer.writeAll("    }");
}

/// The fields kosm writes once (D62): name, a fingerprint made the way Zig makes one, version
/// and the config's own `minimum_zig_version`.
fn newManifest(context: Context, name: []const u8, config_manifest: [:0]const u8) Error![:0]const u8 {
    const configured = manifest.stringField(context.arena, config_manifest, "minimum_zig_version") catch |err|
        return invalidManifest(context, err, manifest_name);
    const minimum_zig_version = configured orelse
        try context.arena.print("{d}.{d}.{d}", .{ builtin.zig_version.major, builtin.zig_version.minor, builtin.zig_version.patch });
    return context.arena.dupeSentinel(u8, try context.arena.print(
        \\.{{
        \\    .name = .{s},
        \\    .version = "0.0.0",
        \\    .fingerprint = 0x{x}, // Changing this has security and trust implications.
        \\    .minimum_zig_version = "{f}",
        \\}}
        \\
    , .{ name, manifest.fingerprint(context.io, name), std.zig.fmtString(minimum_zig_version) }), 0);
}

/// What a directory kosmos holds: its files, relative and with `/`, and every name its Zig
/// files `@import`.
const Contents = struct {
    files: [][]const u8,
    imports: []const []const u8,
};

/// Walks `directory`, leaving out `zig-out/` and hidden entries (`.git`, `.zig-cache`), which
/// are never part of a published package.
fn listContents(context: Context, directory: []const u8) Error!Contents {
    const io = context.io;
    const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, directory });
    var dir = std.Io.Dir.cwd().openDir(io, full_path, .{ .iterate = true }) catch |err|
        return context.fail("cannot read {s}/: {s}", .{ directory, @errorName(err) });
    defer dir.close(io);
    var walker = try dir.walkSelectively(context.arena);
    defer walker.deinit();

    var found: std.ArrayList([]const u8) = .empty;
    var imports: std.ArrayList([]const u8) = .empty;
    while (walker.next(io) catch |err| return context.fail("cannot read {s}/: {s}", .{ directory, @errorName(err) })) |entry| {
        if (std.mem.startsWith(u8, entry.basename, ".")) continue;
        if (entry.depth() == 1 and std.mem.eql(u8, entry.basename, "zig-out")) continue;
        switch (entry.kind) {
            .directory => walker.enter(io, entry) catch |err| return context.fail("cannot read {s}/{s}/: {s}", .{ directory, entry.path, @errorName(err) }),
            .file => {
                const path = try context.arena.dupe(u8, entry.path);
                std.mem.replaceScalar(u8, path, std.Io.Dir.path.sep, '/');
                try found.append(context.arena, path);
                if (!std.mem.endsWith(u8, path, ".zig")) continue;
                const source = entry.dir.readFileAllocOptions(io, entry.basename, context.arena, .limited(max_file_size), .of(u8), 0) catch |err|
                    return context.fail("cannot read {s}/{s}: {s}", .{ directory, path, @errorName(err) });
                try import_scanner.appendImports(context.arena, source, &imports);
            },
            else => {},
        }
    }
    return .{ .files = found.items, .imports = imports.items };
}

/// kosm first, then every installed or local directory package in `imports`, sorted by name.
/// Each `.path` is made relative to `directory`. Names that are neither (`std`, `colors.zig`,
/// a typo the compiler has reported) are not dependencies.
fn packageDependencies(context: Context, package_name: []const u8, directory: []const u8, config_manifest: [:0]const u8, imports: []const []const u8, refreshed: []const Reached) Error![]const manifest.Dependency {
    const installed = manifest.dependencies(context.arena, config_manifest) catch |err|
        return invalidManifest(context, err, manifest_name);
    const kosm = for (installed) |dependency| {
        if (std.mem.eql(u8, dependency.name, kosm_name)) break dependency;
    } else return context.fail("{s} has no '{s}' dependency", .{ manifest_name, kosm_name });

    var result: std.ArrayList(manifest.Dependency) = .empty;
    for (imports) |name| {
        if (std.mem.eql(u8, name, package_name) or std.mem.eql(u8, name, kosm_name)) continue;
        if (for (result.items) |added| {
            if (std.mem.eql(u8, added.name, name)) break true;
        } else false) continue;
        const dependency = for (installed) |candidate| {
            if (std.mem.eql(u8, candidate.name, name)) break candidate;
        } else try localDependency(context, directory, name, refreshed) orelse continue;
        try result.append(context.arena, dependency);
    }
    std.mem.sort(manifest.Dependency, result.items, {}, dependencyLessThan);
    try result.insert(context.arena, 0, kosm);
    for (result.items) |*dependency| {
        if (dependency.path) |path| dependency.path = try rebase(context, directory, path);
    }
    return result.items;
}

/// The dependency on local directory package `name` (`apps/my_bar/`), with its path relative
/// to the config, or null when `name` is not local. A single file, or a directory that has no
/// manifest and gets none in this run, cannot be a dependency, so either is an error naming
/// the import (D62).
fn localDependency(context: Context, directory: []const u8, name: []const u8, refreshed: []const Reached) Error!?manifest.Dependency {
    for (local_directories) |local_directory| {
        const file = try context.arena.print("{s}/{s}.zig", .{ local_directory, name });
        if (try kindOf(context, file) == .file) {
            return context.fail("{s}/ imports '{s}', which is the single file {s}; a published package could not resolve it, so make it a directory package (D62)", .{ directory, name, file });
        }
        const package = try std.Io.Dir.path.join(context.arena, &.{ local_directory, name });
        if (try kindOf(context, package) != .directory) continue;
        const package_manifest = try std.Io.Dir.path.join(context.arena, &.{ package, manifest_name });
        if (try kindOf(context, package_manifest) != .file and !isRefreshed(refreshed, package)) {
            return context.fail("{s}/ imports '{s}', but {s}/ has no {s} yet, so it cannot be a dependency", .{ directory, name, package, manifest_name });
        }
        return .{ .name = name, .path = package };
    }
    return null;
}

/// `path`, relative to the config, made relative to `directory` inside it.
fn rebase(context: Context, directory: []const u8, path: []const u8) Error![]const u8 {
    const from = try std.Io.Dir.path.join(context.arena, &.{ context.config, directory });
    const to = try std.Io.Dir.path.resolveAlloc(context.arena, &.{ context.config, path });
    return std.Io.Dir.path.relativeAlloc(context.arena, context.config, null, from, to);
}

/// Writes `change` and says so, or with `.report` only says it would.
fn save(context: Context, mode: Mode, change: Change) Error!void {
    const verb = switch (change.kind) {
        .create => "create",
        .update => "update",
    };
    switch (mode) {
        .report => return context.stdout.print("would {s} {s}\n", .{ verb, change.path }),
        .write => {
            const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, change.path });
            files.replace(context.io, full_path, change.bytes) catch |err| return context.fail("cannot write {s}: {s}", .{ change.path, @errorName(err) });
            try context.stdout.print("{s}d {s}\n", .{ verb, change.path });
        },
    }
}

const Found = enum { missing, file, directory, other };

/// What `path` (relative to the config) is.
fn kindOf(context: Context, path: []const u8) Error!Found {
    const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, path });
    const stat = std.Io.Dir.cwd().statFile(context.io, full_path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return .missing,
        else => return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) }),
    };
    return switch (stat.kind) {
        .file => .file,
        .directory => .directory,
        else => .other,
    };
}

/// The contents of `path` (relative to the config), or null when it does not exist.
fn read(context: Context, path: []const u8) Error!?[:0]const u8 {
    const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, path });
    return std.Io.Dir.cwd().readFileAllocOptions(context.io, full_path, context.arena, .limited(max_file_size), .of(u8), 0) catch |err| switch (err) {
        error.FileNotFound => null,
        error.OutOfMemory => error.OutOfMemory,
        else => context.fail("cannot read {s}: {s}", .{ path, @errorName(err) }),
    };
}

fn invalidManifest(context: Context, err: manifest.Error, path: []const u8) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidManifest => context.fail("{s} is not a valid manifest; zig build says why", .{path}),
    };
}

fn stringLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn isRefreshed(refreshed: []const Reached, directory: []const u8) bool {
    for (refreshed) |package| {
        if (std.mem.eql(u8, package.directory, directory)) return true;
    }
    return false;
}

fn reachedLessThan(_: void, left: Reached, right: Reached) bool {
    return std.mem.lessThan(u8, left.directory, right.directory);
}

fn dependencyLessThan(_: void, left: manifest.Dependency, right: manifest.Dependency) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

const testing = std.testing;

/// A config project in a temp directory with directory kosmoi `nord` and `other`, local
/// directory app `bar` and single-file kosmos `base`.
const TestConfig = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,
    config: []const u8,

    const config_manifest =
        \\.{
        \\    .name = .test_config,
        \\    .version = "0.0.0",
        \\    .fingerprint = 0x435328528ec39a09,
        \\    .minimum_zig_version = "0.17.0",
        \\    .dependencies = .{
        \\        .kosm = .{ .path = "../kosm" },
        \\        .kosm_kitty = .{ .url = "git+https://example.com/kosm_kitty?ref=main#0123", .hash = "kosm_kitty-0.0.0-AAAA" },
        \\        .kosm_css = .{ .url = "file:///css.tar", .hash = "kosm_css-0.0.0-BBBB", .lazy = true },
        \\    },
        \\    .paths = .{""},
        \\}
        \\
    ;
    const other_manifest = ".{ .name = .other } // never touched\n";

    fn init(test_config: *TestConfig) !void {
        test_config.tmp = testing.tmpDir(.{});
        test_config.arena = .init(testing.allocator);
        const arena = test_config.arena.allocator();
        test_config.stdout = .init(arena);
        test_config.stderr = .init(arena);
        test_config.config = try test_config.tmp.dir.realPathFileAlloc(testing.io, ".", arena);
        const written = [_][2][]const u8{
            .{ "build.zig.zon", config_manifest },
            .{ "kosmoi/nord/root.zig", "const kosm = @import(\"kosm\");\nconst kitty = @import(\"kosm_kitty\");\nconst colors = @import(\"colors.zig\");\nconst std = @import(\"std\");\n" },
            .{ "kosmoi/nord/colors.zig", "const bar = @import(\"bar\");\nconst again = @import(\"kosm_kitty\");\nconst text = \"@import(\\\"kosm_css\\\")\";\n" },
            .{ "kosmoi/nord/templates/theme.lua", "return {}\n" },
            .{ "kosmoi/nord/.zig-cache/h/x", "" },
            .{ "kosmoi/nord/zig-out/bin/x", "" },
            .{ "kosmoi/other/build.zig.zon", other_manifest },
            .{ "kosmoi/other/root.zig", "const kitty = @import(\"kosm_kitty\");\n" },
            .{ "kosmoi/base.zig", "" },
            .{ "apps/bar/build.zig.zon", ".{ .name = .bar }\n" },
            .{ "apps/bar/root.zig", "" },
        };
        for (written) |file| try test_config.write(file[0], file[1]);
    }

    fn deinit(test_config: *TestConfig) void {
        test_config.arena.deinit();
        test_config.tmp.cleanup();
    }

    fn context(test_config: *TestConfig) Context {
        return .{ .io = testing.io, .arena = test_config.arena.allocator(), .config = test_config.config, .stdout = &test_config.stdout.writer, .stderr = &test_config.stderr.writer };
    }

    fn read(test_config: *TestConfig, path: []const u8) !?[]const u8 {
        return test_config.tmp.dir.readFileAlloc(testing.io, path, test_config.arena.allocator(), .limited(max_file_size)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => |other| other,
        };
    }

    fn write(test_config: *TestConfig, path: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(path)) |parent| try test_config.tmp.dir.createDirPath(testing.io, parent);
        try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }
};

/// What refresh writes for nord, after the fingerprint line.
const expected_nord_rest =
    \\    .minimum_zig_version = "0.17.0",
    \\    .dependencies = .{
    \\        .kosm = .{
    \\            .path = "../../../kosm",
    \\        },
    \\        .bar = .{
    \\            .path = "../../apps/bar",
    \\        },
    \\        .kosm_kitty = .{
    \\            .url = "git+https://example.com/kosm_kitty?ref=main#0123",
    \\            .hash = "kosm_kitty-0.0.0-AAAA",
    \\        },
    \\    },
    \\    .paths = .{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "colors.zig",
    \\        "root.zig",
    \\        "templates/theme.lua",
    \\    },
    \\}
    \\
;

test "applying a directory kosmos writes its build files, depending on exactly what it imports" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try refreshApplied(test_config.context(), "nord.iced", .write);
    try testing.expectEqualStrings("created kosmoi/nord/build.zig\ncreated kosmoi/nord/build.zig.zon\ncreated apps/bar/build.zig\nupdated apps/bar/build.zig.zon\n", test_config.stdout.written());
    try testing.expectEqualStrings(build_file, (try test_config.read("kosmoi/nord/build.zig")).?);
    const written = (try test_config.read("kosmoi/nord/build.zig.zon")).?;
    try testing.expect(std.mem.startsWith(u8, written, ".{\n    .name = .nord,\n    .version = \"0.0.0\",\n    .fingerprint = 0x"));
    try testing.expect(std.mem.endsWith(u8, written, expected_nord_rest));
    const fingerprint_start = std.mem.find(u8, written, "0x").? + 2;
    const written_fingerprint = try std.fmt.parseInt(u64, written[fingerprint_start..][0..16], 16);
    try testing.expectEqual(std.hash.Crc32.hash("nord"), written_fingerprint >> 32);
    try testing.expectEqualStrings(TestConfig.other_manifest, (try test_config.read("kosmoi/other/build.zig.zon")).?);
    try testing.expectEqual(null, try test_config.read("kosmoi/other/build.zig"));
}

test "a manifest is rewritten only when its dependencies or files change, keeping every other byte" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.write("kosmoi/nord/build.zig.zon",
        \\// nord, by hand
        \\.{
        \\    .name = .nord,
        \\    .version = "1.2.3",
        \\    .fingerprint = 0x1, // mine
        \\    .paths = .{""},
        \\}
        \\
    );
    try test_config.write("kosmoi/nord/build.zig", "// my own build\n");

    try refreshApplied(test_config.context(), "nord", .write);
    try testing.expectEqualStrings("updated kosmoi/nord/build.zig.zon\ncreated apps/bar/build.zig\nupdated apps/bar/build.zig.zon\n", test_config.stdout.written());
    const first = (try test_config.read("kosmoi/nord/build.zig.zon")).?;
    try testing.expect(std.mem.startsWith(u8, first, "// nord, by hand\n.{\n    .name = .nord,\n    .version = \"1.2.3\",\n    .fingerprint = 0x1, // mine\n    .paths = .{\n        \"build.zig\",\n"));
    try testing.expect(std.mem.endsWith(u8, first, "    },\n    .dependencies = .{\n        .kosm = .{\n            .path = \"../../../kosm\",\n        },\n" ++
        "        .bar = .{\n            .path = \"../../apps/bar\",\n        },\n        .kosm_kitty = .{\n" ++
        "            .url = \"git+https://example.com/kosm_kitty?ref=main#0123\",\n            .hash = \"kosm_kitty-0.0.0-AAAA\",\n        },\n    },\n}\n"));
    try testing.expectEqualStrings("// my own build\n", (try test_config.read("kosmoi/nord/build.zig")).?);

    test_config.stdout.clearRetainingCapacity();
    try refreshApplied(test_config.context(), "nord", .write);
    try testing.expectEqualStrings("", test_config.stdout.written());
    try testing.expectEqualStrings(first, (try test_config.read("kosmoi/nord/build.zig.zon")).?);

    try test_config.write("kosmoi/nord/colors.zig", "const css = @import(\"kosm_css\");\n");
    try refreshApplied(test_config.context(), "nord", .write);
    const second = (try test_config.read("kosmoi/nord/build.zig.zon")).?;
    try testing.expect(std.mem.find(u8, second, ".kosm_kitty") != null);
    try testing.expect(std.mem.find(u8, second, ".bar") == null);
    try testing.expect(std.mem.find(u8, second, "            .hash = \"kosm_css-0.0.0-BBBB\",\n            .lazy = true,\n") != null);
}

test "with --diff a manifest refresh only says what it would write" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try refreshApplied(test_config.context(), "nord", .report);
    try testing.expectEqualStrings("would create kosmoi/nord/build.zig\nwould create kosmoi/nord/build.zig.zon\nwould create apps/bar/build.zig\nwould update apps/bar/build.zig.zon\n", test_config.stdout.written());
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig"));
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig.zon"));

    try refreshApplied(test_config.context(), "nord", .write);
    try test_config.write("kosmoi/nord/extra.txt", "");
    test_config.stdout.clearRetainingCapacity();
    const before = (try test_config.read("kosmoi/nord/build.zig.zon")).?;
    try refreshApplied(test_config.context(), "nord", .report);
    try testing.expectEqualStrings("would update kosmoi/nord/build.zig.zon\n", test_config.stdout.written());
    try testing.expectEqualStrings(before, (try test_config.read("kosmoi/nord/build.zig.zon")).?);
}

test "importing a single-file local package is an error and writes nothing" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try test_config.write("kosmoi/nord/colors.zig", "const base = @import(\"base\");\n");
    try testing.expectError(error.Failed, refreshApplied(test_config.context(), "nord", .write));
    try testing.expectEqualStrings("error: kosmoi/nord/ imports 'base', which is the single file kosmoi/base.zig; a published package could not resolve it, so make it a directory package (D62)\n", test_config.stderr.written());

    try test_config.write("kosmoi/nord/colors.zig", "const bar = @import(\"bar\");\n");
    try test_config.write("apps/bar/root.zig", "const base = @import(\"base\");\n");
    try testing.expectError(error.Failed, refreshApplied(test_config.context(), "nord", .write));
    try testing.expect(std.mem.endsWith(u8, test_config.stderr.written(), "error: apps/bar/ imports 'base', which is the single file kosmoi/base.zig; a published package could not resolve it, so make it a directory package (D62)\n"));
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig"));
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig.zon"));
    try testing.expectEqualStrings("", test_config.stdout.written());
}

test "an apply refreshes every directory package it reaches, through single files and import cycles" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.write("kosmoi/frost.zig", "const kitty = @import(\"kosm_kitty\");\nconst bar = @import(\"bar\");\n");
    try test_config.write("apps/bar/root.zig", "const lang = @import(\"lang\");\n");
    try test_config.write("adapters/lang/root.zig", "const kosm = @import(\"kosm\");\nconst bar = @import(\"bar\");\n");

    try refreshApplied(test_config.context(), "frost", .write);
    try testing.expectEqualStrings(
        \\created adapters/lang/build.zig
        \\created adapters/lang/build.zig.zon
        \\created apps/bar/build.zig
        \\updated apps/bar/build.zig.zon
        \\
    , test_config.stdout.written());
    const bar = (try test_config.read("apps/bar/build.zig.zon")).?;
    try testing.expect(std.mem.find(u8, bar, "        .lang = .{\n            .path = \"../../adapters/lang\",\n        },\n") != null);
    const lang = (try test_config.read("adapters/lang/build.zig.zon")).?;
    try testing.expect(std.mem.find(u8, lang, "        .bar = .{\n            .path = \"../../apps/bar\",\n        },\n") != null);
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig"));
    try testing.expectEqualStrings(TestConfig.other_manifest, (try test_config.read("kosmoi/other/build.zig.zon")).?);

    test_config.stdout.clearRetainingCapacity();
    try refreshApplied(test_config.context(), "frost", .write);
    try testing.expectEqualStrings("", test_config.stdout.written());
}

test "single-file and installed kosmoi have no manifest to refresh" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try refreshApplied(test_config.context(), "base.iced", .write);
    try refreshApplied(test_config.context(), "kosm_kitty", .write);
    try testing.expectEqualStrings("", test_config.stdout.written());
}

test "applying a kosmos that lives in apps/ refreshes its own build files (D87)" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try refreshApplied(test_config.context(), "bar.dark", .write);
    try testing.expectEqualStrings("created apps/bar/build.zig\nupdated apps/bar/build.zig.zon\n", test_config.stdout.written());
}
