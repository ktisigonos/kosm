//! `kosm init`: creates whatever a config project is missing and never touches what
//! it already has, so it sets up a new project and fills in a partial one alike.

const std = @import("std");
const Context = @import("Context.zig");
const Packages = @import("Packages.zig");
const manifest = @import("manifest.zig");

pub const Error = Context.Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

/// What a new config's manifest says about kosm.
pub const Kosm = struct {
    /// Where `zig fetch` gets kosm: its git URL, or in tests a local directory.
    url: []const u8,
    /// Copied into a new config's manifest.
    minimum_zig_version: []const u8,
};

/// The name in a new config's manifest.
const config_name = "kosm_config";
const build_file =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    @import("kosm").addConfigProject(b, @import("build.zig.zon"));
    \\}
    \\
;
const local_directories = [_][]const u8{ "kosmoi", "apps", "adapters" };
/// The starting kosmos written into an empty `kosmoi/`.
const starting_kosmos = .{ .path = "kosmoi/kyanos.zig", .source = @embedFile("kosmoi/kyanos.zig") };

/// Creates the config project at `context.config` (which must exist) from what is missing in
/// it, printing each file and directory it creates.
pub fn init(context: Context, kosm: Kosm) Error!void {
    // Fetching kosm takes the network, so it happens only for a manifest that is really missing,
    // and before anything is created, so a failed fetch leaves the directory as it was.
    const new_manifest = if (try exists(context, "build.zig.zon")) null else try configManifest(context, kosm);
    var created = false;
    created = try createFile(context, "build.zig", build_file) or created;
    if (new_manifest) |bytes| created = try createFile(context, "build.zig.zon", bytes) or created;
    created = try createFile(context, Packages.file_name, try packagesFile(context.arena, if (new_manifest != null) kosm else null)) or created;
    for (local_directories) |directory| created = try createDirectory(context, directory) or created;
    if (try isEmpty(context, "kosmoi")) created = try createFile(context, starting_kosmos.path, starting_kosmos.source) or created;
    if (!created) try context.stdout.print("{s} is already a complete config project\n", .{context.config});
}

/// A new `build.zig.zon` depending on kosm as `zig fetch --save` writes it, its url pinned to
/// the commit it resolved to, with the package hash. The built-in packages need no entry:
/// kosm provides them.
fn configManifest(context: Context, kosm: Kosm) Error![]const u8 {
    const resolved = try fetchKosm(context, kosm);
    return context.arena.print(
        \\.{{
        \\    .name = .{s},
        \\    .version = "0.0.0",
        \\    .fingerprint = 0x{x}, // Changing this has security and trust implications.
        \\    .minimum_zig_version = "{f}",
        \\    .dependencies = .{{
        \\        .kosm = .{{
        \\            .url = "{f}",
        \\            .hash = "{f}",
        \\        }},
        \\    }},
        \\    .paths = .{{""}},
        \\}}
        \\
    , .{
        config_name,
        manifest.fingerprint(context.io, config_name),
        std.zig.fmtString(kosm.minimum_zig_version),
        std.zig.fmtString(resolved.url.?),
        std.zig.fmtString(resolved.hash.?),
    });
}

/// Where `fetchKosm` lets `zig fetch --save` write, inside the config's own Zig cache.
const fetch_directory = ".zig-cache/kosm-init";

/// Runs `zig fetch --save=kosm` against a throwaway manifest and returns the entry it wrote,
/// so the url is exactly what Zig resolved it to.
fn fetchKosm(context: Context, kosm: Kosm) Error!manifest.Dependency {
    const directory = try std.Io.Dir.path.join(context.arena, &.{ context.config, fetch_directory });
    std.Io.Dir.cwd().createDirPath(context.io, directory) catch |err|
        return context.fail("cannot create {s}: {s}", .{ directory, @errorName(err) });
    // Only a leftover throwaway manifest is lost if this fails.
    defer std.Io.Dir.cwd().deleteTree(context.io, directory) catch {};
    const throwaway = try std.fmt.allocPrint(context.arena,
        \\.{{ .name = .{s}, .version = "0.0.0", .fingerprint = 0x{x}, .paths = .{{""}} }}
        \\
    , .{ config_name, manifest.fingerprint(context.io, config_name) });
    const throwaway_path = try std.Io.Dir.path.join(context.arena, &.{ directory, "build.zig.zon" });
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = throwaway_path, .data = throwaway }) catch |err|
        return context.fail("cannot create {s}: {s}", .{ throwaway_path, @errorName(err) });
    // `zig fetch --save` only works in a project with a build.zig.
    const build_path = try std.Io.Dir.path.join(context.arena, &.{ directory, "build.zig" });
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = build_path, .data = "pub fn build(_: *@import(\"std\").Build) void {}\n" }) catch |err|
        return context.fail("cannot create {s}: {s}", .{ build_path, @errorName(err) });

    var in_directory = context;
    in_directory.config = directory;
    const fetched = try in_directory.runZig(&.{ "fetch", "--save=kosm", kosm.url });
    if (!fetched.term.success()) {
        try context.stderr.writeAll(fetched.stderr);
        return context.fail("zig fetch could not fetch kosm from {s}, so build.zig.zon was not created", .{kosm.url});
    }
    const saved = std.Io.Dir.cwd().readFileAllocOptions(context.io, throwaway_path, context.arena, .limited(1024 * 1024), .of(u8), 0) catch |err|
        return context.fail("cannot read {s}: {s}", .{ throwaway_path, @errorName(err) });
    const dependencies = manifest.dependencies(context.arena, saved) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidManifest => return context.fail("zig fetch --save wrote a manifest kosm cannot read: {s}", .{throwaway_path}),
    };
    for (dependencies) |dependency| {
        if (std.mem.eql(u8, dependency.name, "kosm") and dependency.url != null and dependency.hash != null) return dependency;
    }
    return context.fail("zig fetch --save wrote no url and hash for kosm into {s}", .{throwaway_path});
}

/// A new `packages.zon`, following kosm's default branch when `kosm` was just added.
fn packagesFile(arena: std.mem.Allocator, kosm: ?Kosm) std.mem.Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(arena);
    var packages: Packages = .{};
    if (kosm) |added| try packages.put(arena, .{ .name = "kosm", .url = added.url });
    packages.write(&text.writer) catch return error.OutOfMemory;
    return text.written();
}

/// Whether anything is at `name` in the config.
fn exists(context: Context, name: []const u8) Error!bool {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, name });
    std.Io.Dir.cwd().access(context.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) }),
    };
    return true;
}

/// Writes `bytes` to `name` in the config unless something is already there; returns whether it did.
fn createFile(context: Context, name: []const u8, bytes: []const u8) Error!bool {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, name });
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = path, .data = bytes, .flags = .{ .exclusive = true } }) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => return context.fail("cannot create {s}: {s}", .{ path, @errorName(err) }),
    };
    try context.stdout.print("created {s}\n", .{name});
    return true;
}

/// Creates directory `name` in the config unless it exists; returns whether it did.
fn createDirectory(context: Context, name: []const u8) Error!bool {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, name });
    std.Io.Dir.cwd().createDir(context.io, path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => return context.fail("cannot create {s}: {s}", .{ path, @errorName(err) }),
    };
    try context.stdout.print("created {s}/\n", .{name});
    return true;
}

/// Whether directory `name` holds nothing but hidden entries (a `.gitkeep`).
fn isEmpty(context: Context, name: []const u8) Error!bool {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, name });
    var directory = std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch |err|
        return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) });
    defer directory.close(context.io);
    var iterator = directory.iterate();
    while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) })) |entry| {
        if (!std.mem.startsWith(u8, entry.name, ".")) return false;
    }
    return true;
}

const testing = std.testing;
const test_kosm = @import("test_kosm.zig");

/// A temp directory holding a stub kosm package to fetch, offline, and the config project
/// `project/`. Zig's global cache is the tests' own, so nothing lands in ~/.cache/zig.
const TestConfig = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    environ: std.process.Environ.Map,
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,
    /// The temp directory's absolute path.
    root: []const u8,
    kosm: Kosm,

    /// Assumes the tests run from the repository root, as `zig build test` does.
    fn init(test_config: *TestConfig) !void {
        test_config.tmp = testing.tmpDir(.{});
        test_config.arena = .init(testing.allocator);
        const arena = test_config.arena.allocator();
        test_config.stdout = .init(arena);
        test_config.stderr = .init(arena);
        test_config.root = try test_config.tmp.dir.realPathFileAlloc(testing.io, ".", arena);
        const repository = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", arena);
        test_config.environ = try testing.environ.createMap(arena);
        _ = test_config.environ.swapRemove("ZIG_PROGRESS");
        // Shared with the package command tests, so the compiled std stays warm.
        try test_config.environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ repository, ".zig-cache/kosm-test-global-cache" }));
        try test_config.environ.put("HOME", try std.Io.Dir.path.join(arena, &.{ test_config.root, "home" }));
        try test_config.environ.put("XDG_STATE_HOME", try std.Io.Dir.path.join(arena, &.{ test_config.root, "state" }));
        try test_config.tmp.dir.createDirPath(testing.io, "home");
        try test_config.tmp.dir.createDirPath(testing.io, "project");
        test_config.kosm = try test_kosm.stub(arena, testing.io, test_config.tmp.dir, test_config.root);
    }

    fn deinit(test_config: *TestConfig) void {
        test_config.arena.deinit();
        test_config.tmp.cleanup();
    }

    fn context(test_config: *TestConfig) Context {
        return .{
            .io = testing.io,
            .arena = test_config.arena.allocator(),
            .config = std.Io.Dir.path.join(test_config.arena.allocator(), &.{ test_config.root, "project" }) catch @panic("OOM"),
            .environ_map = &test_config.environ,
            .stdout = &test_config.stdout.writer,
            .stderr = &test_config.stderr.writer,
        };
    }

    /// A project file's contents, or null when it does not exist.
    fn read(test_config: *TestConfig, name: []const u8) !?[]const u8 {
        const path = try std.Io.Dir.path.join(test_config.arena.allocator(), &.{ "project", name });
        return test_config.tmp.dir.readFileAlloc(testing.io, path, test_config.arena.allocator(), .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => |other| other,
        };
    }

    fn write(test_config: *TestConfig, name: []const u8, data: []const u8) !void {
        const path = try std.Io.Dir.path.join(test_config.arena.allocator(), &.{ "project", name });
        if (std.Io.Dir.path.dirname(path)) |directory| try test_config.tmp.dir.createDirPath(testing.io, directory);
        try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }
};

test "init in an empty directory creates the whole project, depending on kosm alone by url" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try init(test_config.context(), test_config.kosm);
    try testing.expectEqualStrings(
        \\created build.zig
        \\created build.zig.zon
        \\created packages.zon
        \\created kosmoi/
        \\created apps/
        \\created adapters/
        \\created kosmoi/kyanos.zig
        \\
    , test_config.stdout.written());
    try testing.expectEqualStrings(build_file, (try test_config.read("build.zig")).?);
    try testing.expectEqualStrings(starting_kosmos.source, (try test_config.read("kosmoi/kyanos.zig")).?);
    const arena = test_config.arena.allocator();
    const written: [:0]const u8 = try arena.dupeSentinel(u8, (try test_config.read("build.zig.zon")).?, 0);
    const dependencies = try manifest.dependencies(arena, written);
    try testing.expectEqual(1, dependencies.len);
    try testing.expectEqualStrings("kosm", dependencies[0].name);
    try testing.expectEqualStrings(test_config.kosm.url, dependencies[0].url.?);
    try testing.expect(std.mem.startsWith(u8, dependencies[0].hash.?, "kosm-0.0.0-"));
    try testing.expect(std.mem.find(u8, written, ".minimum_zig_version = \"0.17.0\",") != null);

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const packages_source = try arena.dupeSentinel(u8, (try test_config.read("packages.zon")).?, 0);
    const packages = try Packages.parse(arena, packages_source, &diagnostics);
    try testing.expectEqualStrings(test_config.kosm.url, packages.find("kosm").?.url);
    try testing.expectEqual(null, packages.find("kosm").?.ref);
}

test "a kosm that can't be fetched fails init before anything is created" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    var kosm = test_config.kosm;
    kosm.url = try std.Io.Dir.path.join(test_config.arena.allocator(), &.{ test_config.root, "missing" });

    try testing.expectError(error.Failed, init(test_config.context(), kosm));
    try testing.expect(std.mem.find(u8, test_config.stderr.written(), "zig fetch could not fetch kosm from") != null);
    try testing.expectEqual(null, try test_config.read("build.zig"));
}

test "init on a complete project changes no byte" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try init(test_config.context(), test_config.kosm);
    try test_config.write("build.zig.zon", ".{ .name = .mine } // edited\n");
    try test_config.tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try test_config.write("kosmoi/frost.zig", "// mine\n");
    test_config.stdout.clearRetainingCapacity();

    var kosm = test_config.kosm;
    // A complete project fetches nothing, so an unreachable url changes nothing either.
    kosm.url = "/nowhere";
    try init(test_config.context(), kosm);
    try testing.expectEqualStrings(try test_config.arena.allocator().print("{s} is already a complete config project\n", .{test_config.context().config}), test_config.stdout.written());
    try testing.expectEqualStrings(".{ .name = .mine } // edited\n", (try test_config.read("build.zig.zon")).?);
    try testing.expectEqual(null, try test_config.read("kosmoi/kyanos.zig"));
}

test "init on a directory holding kosmoi adds only the project files and other directories" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.write("kosmoi/nord/root.zig", "// mine\n");

    try init(test_config.context(), test_config.kosm);
    try testing.expectEqualStrings(
        \\created build.zig
        \\created build.zig.zon
        \\created packages.zon
        \\created apps/
        \\created adapters/
        \\
    , test_config.stdout.written());
    try testing.expectEqualStrings("// mine\n", (try test_config.read("kosmoi/nord/root.zig")).?);
    try testing.expectEqual(null, try test_config.read("kosmoi/kyanos.zig"));
}

test "init on a project missing only kosmoi adds kosmoi and the starting kosmos" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    for ([_][]const u8{ "build.zig", "build.zig.zon", "packages.zon" }) |name| try test_config.write(name, "// mine\n");
    try test_config.tmp.dir.createDirPath(testing.io, "project/apps");
    try test_config.tmp.dir.createDirPath(testing.io, "project/adapters/.hidden");

    try init(test_config.context(), test_config.kosm);
    try testing.expectEqualStrings("created kosmoi/\ncreated kosmoi/kyanos.zig\n", test_config.stdout.written());
    for ([_][]const u8{ "build.zig", "build.zig.zon", "packages.zon" }) |name| {
        try testing.expectEqualStrings("// mine\n", (try test_config.read(name)).?);
    }
}

test "an empty kosmoi with only hidden entries gets the starting kosmos" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.write("kosmoi/.gitkeep", "");

    try init(test_config.context(), test_config.kosm);
    try testing.expectEqualStrings(starting_kosmos.source, (try test_config.read("kosmoi/kyanos.zig")).?);
}

test "an initialized config builds with the forked kosm sources, applies its starting kosmos and lists it" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    const arena = test_config.arena.allocator();
    var context = test_config.context();
    try init(context, test_config.kosm);
    // The starting kosmos writes Zen's prefs into every profile, so the home needs one.
    try test_config.tmp.dir.createDirPath(testing.io, "home/.zen/a.default");
    try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = "home/.zen/a.default/prefs.js", .data = "" });

    // The pinned kosm is an empty stub, so only the fork to this repository can build the config.
    context.sources = try test_kosm.sources(arena, testing.io);
    const build = try context.runZig(&.{ "build", "-Dkosmos=kyanos" });
    if (!build.term.success()) std.debug.print("{s}\n", .{build.stderr});
    try testing.expect(build.term.success());
    // Editors learn the config's imports from the check step.
    const check = try context.runZig(&.{ "build", "check" });
    if (!check.term.success()) std.debug.print("{s}\n", .{check.stderr});
    try testing.expect(check.term.success());
    const runner = try std.Io.Dir.path.join(arena, &.{ context.config, "zig-out/bin/kosmos" });
    const applied = try context.run(&.{ runner, "--config", context.config });
    if (!applied.term.success()) std.debug.print("{s}\n", .{applied.stderr});
    try testing.expect(applied.term.success());
    const kitty = try test_config.tmp.dir.readFileAlloc(testing.io, "home/.config/kitty/kosm.conf", arena, .limited(1024 * 1024));
    try testing.expect(std.mem.find(u8, kitty, "font_size 13") != null);

    test_config.stdout.clearRetainingCapacity();
    try @import("list.zig").list(context, "kyanos");
    try testing.expectEqualStrings(
        \\kyanos  kosmoi/kyanos.zig
        \\  kitty: kosm_kitty.App
        \\  ghostty: kosm_ghostty.App
        \\  hyprland: kosm_hyprland.App
        \\  zen: kosm_zen.App
        \\  nvim: kosm_nvim.App
        \\
    , test_config.stdout.written());
    test_config.stdout.clearRetainingCapacity();
    try @import("list.zig").list(context, null);
    try testing.expect(std.mem.startsWith(u8, test_config.stdout.written(), "kosmoi:\n  kyanos  kosmoi/kyanos.zig\npackages:\n  kosm_css\n    adapter  css\n"));

    context.sources = null;
    const pinned = try context.runZig(&.{ "build", "-Dkosmos=kyanos" });
    try testing.expect(!pinned.term.success());
}

test "a runner speaking another interface fails before planning, naming both numbers" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    const arena = test_config.arena.allocator();
    var context = test_config.context();
    try init(context, test_config.kosm);
    context.sources = try test_kosm.sources(arena, testing.io);
    const build = try context.runZig(&.{ "build", "-Dkosmos=kyanos" });
    try testing.expect(build.term.success());

    try test_config.environ.put("KOSM_INTERFACE", "999");
    const runner = try std.Io.Dir.path.join(arena, &.{ context.config, "zig-out/bin/kosmos" });
    const applied = try context.run(&.{ runner, "--config", context.config });
    try testing.expect(!applied.term.success());
    try testing.expect(std.mem.find(u8, applied.stderr, "speaks interface 999, but the kosm this config builds with speaks interface") != null);
    try testing.expectError(error.FileNotFound, test_config.tmp.dir.access(testing.io, "home/.config/kitty/kosm.conf", .{}));
}
