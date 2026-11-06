//! `kosm init` (D83, D84): creates whatever a config project is missing and never touches what
//! it already has, so it sets up a new project and fills in a partial one alike.

const std = @import("std");
const Context = @import("Context.zig");
const Packages = @import("Packages.zig");
const manifest = @import("manifest.zig");

pub const Error = Context.Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

/// Where kosm and its built-in packages live while they are developed in one repo (D67).
pub const Repository = struct {
    /// The repo's absolute path.
    root: []const u8,
    /// The names of the packages in `packages/`.
    built_in_packages: []const []const u8,
    /// Copied into a new config's manifest (D44).
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
/// The starting kosmos written into an empty `kosmoi/` (D84).
const starting_kosmos = .{ .path = "kosmoi/kyanos.zig", .source = @embedFile("kosmoi/kyanos.zig") };

/// Creates the config project at `context.config` (which must exist) from what is missing in
/// it, printing each file and directory it creates.
pub fn init(context: Context, repository: Repository) Error!void {
    var created = false;
    created = try createFile(context, "build.zig", build_file) or created;
    created = try createFile(context, "build.zig.zon", try configManifest(context, repository)) or created;
    created = try createFile(context, Packages.file_name, try packagesFile(context.arena)) or created;
    for (local_directories) |directory| created = try createDirectory(context, directory) or created;
    if (try isEmpty(context, "kosmoi")) created = try createFile(context, starting_kosmos.path, starting_kosmos.source) or created;
    if (!created) try context.stdout.print("{s} is already a complete config project\n", .{context.config});
}

/// A new `build.zig.zon` depending on kosm and every built-in package by relative path (D83).
fn configManifest(context: Context, repository: Repository) Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(context.arena);
    const writer = &text.writer;
    try writer.print(
        \\.{{
        \\    .name = .{s},
        \\    .version = "0.0.0",
        \\    .fingerprint = 0x{x}, // Changing this has security and trust implications.
        \\    .minimum_zig_version = "{f}",
        \\    .dependencies = .{{
        \\        .kosm = .{{ .path = "{f}" }},
        \\
    , .{
        config_name,
        manifest.fingerprint(context.io, config_name),
        std.zig.fmtString(repository.minimum_zig_version),
        std.zig.fmtString(try relativeTo(context, repository.root)),
    });
    for (repository.built_in_packages) |name| {
        const package = try std.Io.Dir.path.join(context.arena, &.{ repository.root, "packages", name });
        try writer.print("        .{f} = .{{ .path = \"{f}\" }},\n", .{ std.zig.fmtId(name), std.zig.fmtString(try relativeTo(context, package)) });
    }
    try writer.writeAll(
        \\    },
        \\    .paths = .{""},
        \\}
        \\
    );
    return text.written();
}

/// `path` relative to the config, since Zig rejects an absolute `.path` dependency.
fn relativeTo(context: Context, path: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.Io.Dir.path.relativeAlloc(context.arena, context.config, null, context.config, path);
}

fn packagesFile(arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(arena);
    const packages: Packages = .{};
    packages.write(&text.writer) catch return error.OutOfMemory;
    return text.written();
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

const TestConfig = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,
    config: []const u8,

    const repository: Repository = .{
        .root = "/repo/kosm",
        .built_in_packages = &.{ "kosm_css", "kosm_kitty" },
        .minimum_zig_version = "0.17.0",
    };

    fn init(test_config: *TestConfig) !void {
        test_config.tmp = testing.tmpDir(.{});
        test_config.arena = .init(testing.allocator);
        const arena = test_config.arena.allocator();
        test_config.stdout = .init(arena);
        test_config.stderr = .init(arena);
        test_config.config = try test_config.tmp.dir.realPathFileAlloc(testing.io, ".", arena);
    }

    fn deinit(test_config: *TestConfig) void {
        test_config.arena.deinit();
        test_config.tmp.cleanup();
    }

    fn context(test_config: *TestConfig) Context {
        return .{ .io = testing.io, .arena = test_config.arena.allocator(), .config = test_config.config, .stdout = &test_config.stdout.writer, .stderr = &test_config.stderr.writer };
    }

    fn read(test_config: *TestConfig, path: []const u8) !?[]const u8 {
        return test_config.tmp.dir.readFileAlloc(testing.io, path, test_config.arena.allocator(), .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => |other| other,
        };
    }
};

test "init in an empty directory creates the whole project and the starting kosmos" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();

    try init(test_config.context(), TestConfig.repository);
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
    try testing.expect(std.mem.startsWith(u8, (try test_config.read("packages.zon")).?, "// Written by kosm add"));
    const written = (try test_config.read("build.zig.zon")).?;
    const arena = test_config.arena.allocator();
    for ([_][2][]const u8{ .{ "kosm", "/repo/kosm" }, .{ "kosm_kitty", "/repo/kosm/packages/kosm_kitty" } }) |dependency| {
        const relative = try std.Io.Dir.path.relativeAlloc(arena, "/", null, test_config.config, dependency[1]);
        try testing.expect(std.mem.find(u8, written, try arena.print(".{s} = .{{ .path = \"{s}\" }},", .{ dependency[0], relative })) != null);
    }
    try testing.expect(std.mem.find(u8, written, "\"/repo") == null);
    try testing.expect(std.mem.find(u8, written, ".minimum_zig_version = \"0.17.0\",") != null);
}

test "init on a complete project changes no byte" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try init(test_config.context(), TestConfig.repository);
    try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = "build.zig.zon", .data = ".{ .name = .mine } // edited\n" });
    try test_config.tmp.dir.deleteFile(testing.io, "kosmoi/kyanos.zig");
    try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmoi/frost.zig", .data = "// mine\n" });
    test_config.stdout.clearRetainingCapacity();

    try init(test_config.context(), TestConfig.repository);
    try testing.expectEqualStrings(try test_config.arena.allocator().print("{s} is already a complete config project\n", .{test_config.config}), test_config.stdout.written());
    try testing.expectEqualStrings(".{ .name = .mine } // edited\n", (try test_config.read("build.zig.zon")).?);
    try testing.expectEqual(null, try test_config.read("kosmoi/kyanos.zig"));
}

test "init on a directory holding kosmoi adds only the project files and other directories" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.tmp.dir.createDirPath(testing.io, "kosmoi/nord");
    try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmoi/nord/root.zig", .data = "// mine\n" });

    try init(test_config.context(), TestConfig.repository);
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
    for ([_][]const u8{ "build.zig", "build.zig.zon", "packages.zon" }) |name| {
        try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = name, .data = "// mine\n" });
    }
    try test_config.tmp.dir.createDirPath(testing.io, "apps");
    try test_config.tmp.dir.createDirPath(testing.io, "adapters/.hidden");

    try init(test_config.context(), TestConfig.repository);
    try testing.expectEqualStrings("created kosmoi/\ncreated kosmoi/kyanos.zig\n", test_config.stdout.written());
    for ([_][]const u8{ "build.zig", "build.zig.zon", "packages.zon" }) |name| {
        try testing.expectEqualStrings("// mine\n", (try test_config.read(name)).?);
    }
}

test "an empty kosmoi with only hidden entries gets the starting kosmos" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.tmp.dir.createDirPath(testing.io, "kosmoi");
    try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmoi/.gitkeep", .data = "" });

    try init(test_config.context(), TestConfig.repository);
    try testing.expectEqualStrings(starting_kosmos.source, (try test_config.read("kosmoi/kyanos.zig")).?);
}

test "an initialized config applies its starting kosmos and lists it" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    const arena = test_config.arena.allocator();
    // Assumes the tests run from the repository root, as `zig build test` does.
    const root = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", arena);
    var environ = try testing.environ.createMap(arena);
    _ = environ.swapRemove("ZIG_PROGRESS");
    // Shared with the package command tests, so the compiled std stays warm.
    try environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ root, ".zig-cache/kosm-test-global-cache" }));
    try environ.put("HOME", try std.Io.Dir.path.join(arena, &.{ test_config.config, "home" }));
    try environ.put("XDG_STATE_HOME", try std.Io.Dir.path.join(arena, &.{ test_config.config, "state" }));
    try test_config.tmp.dir.createDirPath(testing.io, "home");
    try test_config.tmp.dir.createDirPath(testing.io, "project");
    var context = test_config.context();
    context.config = try std.Io.Dir.path.join(arena, &.{ test_config.config, "project" });
    context.environ_map = &environ;

    const built_in = @import("kosm_repository");
    try init(context, .{ .root = root, .built_in_packages = built_in.built_in_packages, .minimum_zig_version = built_in.minimum_zig_version });
    const build = try context.runZig(&.{ "build", "-Dkosmos=kyanos" });
    if (!build.term.success()) std.debug.print("{s}\n", .{build.stderr});
    try testing.expect(build.term.success());
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
        \\  zen: kosm_zen.App
        \\  nvim: kosm_nvim.App
        \\
    , test_config.stdout.written());
    test_config.stdout.clearRetainingCapacity();
    try @import("list.zig").list(context, null);
    try testing.expect(std.mem.startsWith(u8, test_config.stdout.written(), "kosmoi:\n  kyanos  kosmoi/kyanos.zig\npackages:\n  kosm_css\n    adapter  css\n"));
}
