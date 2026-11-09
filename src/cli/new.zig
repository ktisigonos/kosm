//! `kosm new kosmos|app|adapter <name>`: scaffolds a directory package with a
//! commented `root.zig`, and the `build.zig` and `build.zig.zon` every directory package has.

const std = @import("std");
const Context = @import("Context.zig");
const directory_package = @import("directory_package.zig");
const manifest = @import("manifest.zig");

pub const Error = Context.Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

/// What `kosm new` scaffolds, and where it goes in the config.
pub const Kind = enum {
    kosmos,
    app,
    adapter,

    fn directory(kind: Kind) []const u8 {
        return switch (kind) {
            .kosmos => "kosmoi",
            .app => "apps",
            .adapter => "adapters",
        };
    }

    fn scaffold(kind: Kind) []const u8 {
        return switch (kind) {
            .kosmos => @embedFile("scaffolds/kosmos.zig"),
            .app => @embedFile("scaffolds/app.zig"),
            .adapter => @embedFile("scaffolds/adapter.zig"),
        };
    }
};

/// Stands for the package's name in the scaffolds.
const name_placeholder = "scaffold_name";
/// Import names Zig itself gives meaning to.
const reserved_names = [_][]const u8{ "std", "builtin", "root" };

/// Creates `<kind directory>/<name>/` in the config, printing each file it writes. A name that
/// is no Zig identifier or already names a local kosmos, app or adapter or an installed
/// package is refused, and nothing is written.
pub fn new(context: Context, kind: Kind, name: []const u8) Error!void {
    try checkName(context, name);
    const directory = try std.Io.Dir.path.join(context.arena, &.{ kind.directory(), name });
    const root = try std.Io.Dir.path.join(context.arena, &.{ directory, "root.zig" });
    const full_root = try std.Io.Dir.path.join(context.arena, &.{ context.config, root });
    const source = try std.mem.replaceOwned(u8, context.arena, kind.scaffold(), name_placeholder, name);
    std.Io.Dir.cwd().createDirPath(context.io, std.Io.Dir.path.dirname(full_root).?) catch |err|
        return context.fail("cannot create {s}/: {s}", .{ directory, @errorName(err) });
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = full_root, .data = source, .flags = .{ .exclusive = true } }) catch |err|
        return context.fail("cannot create {s}: {s}", .{ root, @errorName(err) });
    try context.stdout.print("created {s}\n", .{root});
    try directory_package.refresh(context, directory, .write);
}

fn checkName(context: Context, name: []const u8) Error!void {
    if (!std.zig.isValidId(name)) {
        return context.fail("'{s}' cannot be a package name: it must be a Zig identifier, like my_bar", .{name});
    }
    for (reserved_names) |reserved| {
        if (std.mem.eql(u8, name, reserved)) return context.fail("'{s}' cannot be a package name: Zig's own @import(\"{s}\") already means something", .{ name, name });
    }
    for (directory_package.local_directories) |local_directory| {
        for ([_][]const u8{ ".zig", "" }) |suffix| {
            const path = try context.arena.print("{s}/{s}{s}", .{ local_directory, name, suffix });
            const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, path });
            std.Io.Dir.cwd().access(context.io, full_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) }),
            };
            return context.fail("'{s}' is taken by {s}; kosmoi, apps, adapters and packages need unique names", .{ name, path });
        }
    }
    const config_manifest = std.Io.Dir.cwd().readFileAllocOptions(context.io, try std.Io.Dir.path.join(context.arena, &.{ context.config, "build.zig.zon" }), context.arena, .limited(16 * 1024 * 1024), .of(u8), 0) catch |err| switch (err) {
        error.FileNotFound => return context.fail("{s} has no build.zig.zon; run kosm init first", .{context.config}),
        error.OutOfMemory => return error.OutOfMemory,
        else => return context.fail("cannot read build.zig.zon: {s}", .{@errorName(err)}),
    };
    const installed = manifest.dependencyNames(context.arena, config_manifest) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidManifest => return context.fail("build.zig.zon is not a valid manifest; zig build says why", .{}),
    };
    for (installed) |package| {
        if (std.mem.eql(u8, package, name)) return context.fail("'{s}' is taken by the installed package '{s}'; kosmoi, apps, adapters and packages need unique names", .{ name, name });
    }
    for (@import("kosm_package").built_in_packages) |package| {
        if (std.mem.eql(u8, package, name)) return context.fail("'{s}' is taken by the built-in package '{s}' kosm provides; kosmoi, apps, adapters and packages need unique names", .{ name, name });
    }
}

const testing = std.testing;

const TestConfig = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,
    config: []const u8,

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

    fn write(test_config: *TestConfig, path: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(path)) |parent| try test_config.tmp.dir.createDirPath(testing.io, parent);
        try test_config.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }

    fn exists(test_config: *TestConfig, path: []const u8) bool {
        test_config.tmp.dir.access(testing.io, path, .{}) catch return false;
        return true;
    }
};

const test_manifest =
    \\.{
    \\    .name = .test_config,
    \\    .version = "0.0.0",
    \\    .fingerprint = 0x435328528ec39a09,
    \\    .minimum_zig_version = "0.17.0",
    \\    .dependencies = .{
    \\        .kosm = .{ .path = "../kosm" },
    \\        .kosm_kitty = .{ .path = "../kosm/packages/kosm_kitty" },
    \\    },
    \\    .paths = .{""},
    \\}
    \\
;

test "new writes the scaffold with its name, and build files depending on what it imports" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.write("build.zig.zon", test_manifest);

    try new(test_config.context(), .kosmos, "frost");
    try testing.expectEqualStrings("created kosmoi/frost/root.zig\ncreated kosmoi/frost/build.zig\ncreated kosmoi/frost/build.zig.zon\n", test_config.stdout.written());
    const arena = test_config.arena.allocator();
    const root = try test_config.tmp.dir.readFileAlloc(testing.io, "kosmoi/frost/root.zig", arena, .limited(1024 * 1024));
    try testing.expect(std.mem.find(u8, root, "kosm apply frost.light") != null);
    try testing.expect(std.mem.find(u8, root, name_placeholder) == null);
    const written = try test_config.tmp.dir.readFileAlloc(testing.io, "kosmoi/frost/build.zig.zon", arena, .limited(1024 * 1024));
    try testing.expect(std.mem.find(u8, written, ".name = .frost,") != null);
    try testing.expect(std.mem.find(u8, written, "        .kosm_kitty = .{\n            .path = \"../../../kosm/packages/kosm_kitty\",\n") != null);
}

test "new refuses a name that is taken or no identifier, and writes nothing" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    try test_config.write("build.zig.zon", test_manifest);
    try test_config.write("kosmoi/frost.zig", "");
    try test_config.write("adapters/lang/root.zig", "");

    try testing.expectError(error.Failed, new(test_config.context(), .app, "frost"));
    try testing.expectError(error.Failed, new(test_config.context(), .kosmos, "lang"));
    try testing.expectError(error.Failed, new(test_config.context(), .adapter, "kosm_kitty"));
    try testing.expectError(error.Failed, new(test_config.context(), .app, "kosm_lua"));
    try testing.expectError(error.Failed, new(test_config.context(), .app, "my-bar"));
    try testing.expectError(error.Failed, new(test_config.context(), .app, "std"));
    try testing.expectEqualStrings(
        \\error: 'frost' is taken by kosmoi/frost.zig; kosmoi, apps, adapters and packages need unique names
        \\error: 'lang' is taken by adapters/lang; kosmoi, apps, adapters and packages need unique names
        \\error: 'kosm_kitty' is taken by the installed package 'kosm_kitty'; kosmoi, apps, adapters and packages need unique names
        \\error: 'kosm_lua' is taken by the built-in package 'kosm_lua' kosm provides; kosmoi, apps, adapters and packages need unique names
        \\error: 'my-bar' cannot be a package name: it must be a Zig identifier, like my_bar
        \\error: 'std' cannot be a package name: Zig's own @import("std") already means something
        \\
    , test_config.stderr.written());
    try testing.expectEqualStrings("", test_config.stdout.written());
    try testing.expect(!test_config.exists("apps"));
    try testing.expect(!test_config.exists("kosmoi/lang"));
}

test "every scaffold builds in an initialized config, and the kosmos applies with --diff" {
    var test_config: TestConfig = undefined;
    try test_config.init();
    defer test_config.deinit();
    const arena = test_config.arena.allocator();
    // Assumes the tests run from the repository root, as `zig build test` does.
    const repository_root = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", arena);
    var environ = try testing.environ.createMap(arena);
    _ = environ.swapRemove("ZIG_PROGRESS");
    // Shared with the other config tests, so the compiled std stays warm.
    try environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ repository_root, ".zig-cache/kosm-test-global-cache" }));
    try environ.put("HOME", try std.Io.Dir.path.join(arena, &.{ test_config.config, "home" }));
    try test_config.tmp.dir.createDirPath(testing.io, "home");
    try test_config.tmp.dir.createDirPath(testing.io, "project");
    var context = test_config.context();
    context.config = try std.Io.Dir.path.join(arena, &.{ test_config.config, "project" });
    context.environ_map = &environ;

    const test_kosm = @import("test_kosm.zig");
    try @import("init.zig").init(context, try test_kosm.stub(arena, testing.io, test_config.tmp.dir, test_config.config));
    context.sources = try test_kosm.sources(arena, testing.io);
    try new(context, .kosmos, "frost");
    try new(context, .app, "my_bar");
    try new(context, .adapter, "my_lang");

    // Each package builds on its own, which proves its manifest.
    for ([_][]const u8{ "kosmoi/frost", "apps/my_bar", "adapters/my_lang" }) |directory| {
        var package_context = context;
        package_context.config = try std.Io.Dir.path.join(arena, &.{ context.config, directory });
        const built = try package_context.runZig(&.{ "build", "test" });
        if (!built.term.success()) std.debug.print("{s}: {s}\n", .{ directory, built.stderr });
        try testing.expect(built.term.success());
    }

    try test_config.write("project/kosmoi/check.zig", check_kosmos);
    const frost = try applyDiff(context, "frost.light");
    try testing.expect(std.mem.find(u8, frost, "+font_size 12") != null);
    const check = try applyDiff(context, "check");
    try testing.expect(std.mem.find(u8, check, "+foreground = #") != null);
    try testing.expect(std.mem.find(u8, check, "+size = 3\n") != null);
    try testing.expect(!test_config.exists("home/.config"));
}

/// Uses the scaffolded app, and writes a file through the scaffolded adapter.
const check_kosmos =
    \\const kosm = @import("kosm");
    \\const my_bar = @import("my_bar");
    \\
    \\const Lang = struct {
    \\    accent: kosm.Color,
    \\    pub fn apply(self: Lang, output: *kosm.Output) !void {
    \\        try output.generate(.{ .file = "~/check.my_lang" }, .{ .accent = self.accent, .size = 3 });
    \\    }
    \\};
    \\
    \\pub const Check = struct { bar: my_bar.App, lang: Lang };
    \\
    \\pub fn kosmos() Check {
    \\    const theme = kosm.Theme.from(.{ .black = kosm.hex("000000"), .white = kosm.hex("ffffff") }, .dark);
    \\    return .{ .bar = my_bar.from(theme), .lang = .{ .accent = theme.palette.cyan } };
    \\}
    \\
;

/// Builds kosmos `name` in the config and runs it with `--diff`; returns the diff.
fn applyDiff(context: Context, name: []const u8) ![]const u8 {
    const build = try context.runZig(&.{ "build", try context.arena.print("-Dkosmos={s}", .{name}) });
    if (!build.term.success()) std.debug.print("{s}\n", .{build.stderr});
    try testing.expect(build.term.success());
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, "zig-out/bin/kosmos" });
    const applied = try context.run(&.{ runner, "--diff", "--config", context.config });
    if (!applied.term.success()) std.debug.print("{s}\n", .{applied.stderr});
    try testing.expect(applied.term.success());
    return applied.stdout;
}
