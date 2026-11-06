//! Keeps a directory kosmos' own manifest up to date when kosm applies it (D62): its
//! `build.zig.zon` depends on kosm and exactly the packages the kosmos imports, and lists every
//! file it holds. Nothing else is touched, including other directory packages' manifests.

const std = @import("std");
const builtin = @import("builtin");
const Context = @import("Context.zig");
const files = @import("files.zig");
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
const local_directories = [_][]const u8{ "kosmoi", "apps", "adapters" };
/// Kosmos files and manifests are small; this only guards against reading something huge.
const max_file_size = 16 * 1024 * 1024;

/// When kosmos `name` ("nord" or "nord.iced") is a directory kosmos (`kosmoi/nord/`), writes
/// its `build.zig` if missing and brings its `build.zig.zon` up to date, or with `.report`
/// only prints which of them would change. A single-file or installed kosmos has no manifest.
pub fn refresh(context: Context, name: []const u8, mode: Mode) Error!void {
    const package_name = name[0 .. std.mem.findScalar(u8, name, '.') orelse name.len];
    const directory = try std.Io.Dir.path.join(context.arena, &.{ "kosmoi", package_name });
    if (try find(context, directory) != .directory) return;
    if (!std.zig.isValidId(package_name)) {
        return context.fail("{s}/ cannot be a package: its name must be a Zig identifier (D51)", .{directory});
    }

    const config_manifest = try read(context, manifest_name) orelse return context.fail("{s} has no {s}", .{ context.config, manifest_name });
    const contents = try listContents(context, directory);
    const dependencies = try packageDependencies(context, package_name, directory, config_manifest, contents.imports);

    const build_path = try std.Io.Dir.path.join(context.arena, &.{ directory, build_name });
    const manifest_path = try std.Io.Dir.path.join(context.arena, &.{ directory, manifest_name });
    const create_build = try find(context, build_path) == .missing;
    const existing = try read(context, manifest_path);
    const base = existing orelse try newManifest(context, package_name, config_manifest);
    var paths: std.ArrayList([]const u8) = .fromOwnedSlice(contents.files);
    if (create_build) try paths.append(context.arena, build_name);
    if (existing == null) try paths.append(context.arena, manifest_name);
    const updated = render(context.arena, base, dependencies, paths.items) catch |err| return invalidManifest(context, err, manifest_path);

    if (create_build) try save(context, mode, build_path, build_file, .create);
    if (existing == null or !std.mem.eql(u8, existing.?, updated)) {
        try save(context, mode, manifest_path, updated, if (existing == null) .create else .update);
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
                try appendImports(context.arena, source, &imports);
            },
            else => {},
        }
    }
    return .{ .files = found.items, .imports = imports.items };
}

/// Appends the text of every `@import("...")` in `source`. A literal that does not parse is
/// skipped: the compiler has reported it already.
fn appendImports(arena: std.mem.Allocator, source: [:0]const u8, imports: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
    var tokenizer: std.zig.Tokenizer = .init(source);
    var previous: [2]std.zig.Token = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        const token = tokenizer.next();
        if (token.tag == .eof) return;
        defer previous = .{ previous[1], token };
        if (count < 2 or token.tag != .string_literal or previous[1].tag != .l_paren or previous[0].tag != .builtin) continue;
        if (!std.mem.eql(u8, source[previous[0].loc.start..previous[0].loc.end], "@import")) continue;
        const text = std.zig.string_literal.parseAlloc(arena, source[token.loc.start..token.loc.end]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        try imports.append(arena, text);
    }
}

/// kosm first, then every installed or local directory package in `imports`, sorted by name.
/// Each `.path` is made relative to `directory`. Names that are neither (`std`, `colors.zig`,
/// a typo the compiler has reported) are not dependencies.
fn packageDependencies(context: Context, package_name: []const u8, directory: []const u8, config_manifest: [:0]const u8, imports: []const []const u8) Error![]const manifest.Dependency {
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
        } else try localDependency(context, directory, name) orelse continue;
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
/// to the config, or null when `name` is not local. A single file, or a directory without a
/// manifest, cannot be a dependency, so either is an error naming the import (D62).
fn localDependency(context: Context, directory: []const u8, name: []const u8) Error!?manifest.Dependency {
    for (local_directories) |local_directory| {
        const file = try context.arena.print("{s}/{s}.zig", .{ local_directory, name });
        if (try find(context, file) == .file) {
            return context.fail("{s}/ imports '{s}', which is the single file {s}; a published package could not resolve it, so make it a directory package (D62)", .{ directory, name, file });
        }
        const package = try std.Io.Dir.path.join(context.arena, &.{ local_directory, name });
        if (try find(context, package) != .directory) continue;
        const package_manifest = try std.Io.Dir.path.join(context.arena, &.{ package, manifest_name });
        if (try find(context, package_manifest) != .file) {
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

/// Writes `bytes` to `path` and says so, or with `.report` only says it would.
fn save(context: Context, mode: Mode, path: []const u8, bytes: []const u8, change: enum { create, update }) Error!void {
    const verb = switch (change) {
        .create => "create",
        .update => "update",
    };
    switch (mode) {
        .report => return context.stdout.print("would {s} {s}\n", .{ verb, path }),
        .write => {
            const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, path });
            files.replace(context.io, full_path, bytes) catch |err| return context.fail("cannot write {s}: {s}", .{ path, @errorName(err) });
            try context.stdout.print("{s}d {s}\n", .{ verb, path });
        },
    }
}

const Found = enum { missing, file, directory, other };

/// What `path` (relative to the config) is.
fn find(context: Context, path: []const u8) Error!Found {
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

fn dependencyLessThan(_: void, left: manifest.Dependency, right: manifest.Dependency) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

const testing = std.testing;

/// A config project in a temp directory with directory kosmoi `nord` and `other`, local
/// directory app `bar`, single-file kosmos `base` and directory app `draft` without a manifest.
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
            .{ "apps/draft/root.zig", "" },
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

    try refresh(test_config.context(), "nord.iced", .write);
    try testing.expectEqualStrings("created kosmoi/nord/build.zig\ncreated kosmoi/nord/build.zig.zon\n", test_config.stdout.written());
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

    try refresh(test_config.context(), "nord", .write);
    try testing.expectEqualStrings("updated kosmoi/nord/build.zig.zon\n", test_config.stdout.written());
    const first = (try test_config.read("kosmoi/nord/build.zig.zon")).?;
    try testing.expect(std.mem.startsWith(u8, first, "// nord, by hand\n.{\n    .name = .nord,\n    .version = \"1.2.3\",\n    .fingerprint = 0x1, // mine\n    .paths = .{\n        \"build.zig\",\n"));
    try testing.expect(std.mem.endsWith(u8, first, "    },\n    .dependencies = .{\n        .kosm = .{\n            .path = \"../../../kosm\",\n        },\n" ++
        "        .bar = .{\n            .path = \"../../apps/bar\",\n        },\n        .kosm_kitty = .{\n" ++
        "            .url = \"git+https://example.com/kosm_kitty?ref=main#0123\",\n            .hash = \"kosm_kitty-0.0.0-AAAA\",\n        },\n    },\n}\n"));
    try testing.expectEqualStrings("// my own build\n", (try test_config.read("kosmoi/nord/build.zig")).?);

    test_config.stdout.clearRetainingCapacity();
    try refresh(test_config.context(), "nord", .write);
    try testing.expectEqualStrings("", test_config.stdout.written());
    try testing.expectEqualStrings(first, (try test_config.read("kosmoi/nord/build.zig.zon")).?);

    try test_config.write("kosmoi/nord/colors.zig", "const css = @import(\"kosm_css\");\n");
    try refresh(test_config.context(), "nord", .write);
    const second = (try test_config.read("kosmoi/nord/build.zig.zon")).?;
    try testing.expect(std.mem.find(u8, second, ".kosm_kitty") != null);
    try testing.expect(std.mem.find(u8, second, ".bar") == null);
    try testing.expect(std.mem.find(u8, second, "            .hash = \"kosm_css-0.0.0-BBBB\",\n            .lazy = true,\n") != null);
}

test "with --diff a manifest refresh only says what it would write" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try refresh(test_config.context(), "nord", .report);
    try testing.expectEqualStrings("would create kosmoi/nord/build.zig\nwould create kosmoi/nord/build.zig.zon\n", test_config.stdout.written());
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig"));
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig.zon"));

    try refresh(test_config.context(), "nord", .write);
    try test_config.write("kosmoi/nord/extra.txt", "");
    test_config.stdout.clearRetainingCapacity();
    const before = (try test_config.read("kosmoi/nord/build.zig.zon")).?;
    try refresh(test_config.context(), "nord", .report);
    try testing.expectEqualStrings("would update kosmoi/nord/build.zig.zon\n", test_config.stdout.written());
    try testing.expectEqualStrings(before, (try test_config.read("kosmoi/nord/build.zig.zon")).?);
}

test "importing a single-file or manifest-less local package is an error and writes nothing" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try test_config.write("kosmoi/nord/colors.zig", "const base = @import(\"base\");\n");
    try testing.expectError(error.Failed, refresh(test_config.context(), "nord", .write));
    try testing.expectEqualStrings("error: kosmoi/nord/ imports 'base', which is the single file kosmoi/base.zig; a published package could not resolve it, so make it a directory package (D62)\n", test_config.stderr.written());

    try test_config.write("kosmoi/nord/colors.zig", "const draft = @import(\"draft\");\n");
    try testing.expectError(error.Failed, refresh(test_config.context(), "nord", .report));
    try testing.expect(std.mem.endsWith(u8, test_config.stderr.written(), "error: kosmoi/nord/ imports 'draft', but apps/draft/ has no build.zig.zon yet, so it cannot be a dependency\n"));
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig"));
    try testing.expectEqual(null, try test_config.read("kosmoi/nord/build.zig.zon"));
}

test "single-file and installed kosmoi have no manifest to refresh" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try refresh(test_config.context(), "base.iced", .write);
    try refresh(test_config.context(), "kosm_kitty", .write);
    try testing.expectEqualStrings("", test_config.stdout.written());
}
