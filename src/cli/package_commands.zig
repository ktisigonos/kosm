//! `kosm add`, `kosm remove` and `kosm update`. They wrap `zig fetch`, check every fetched
//! package by building it against the config, and keep the user's url and ref in packages.zon.
//! Any failure puts build.zig.zon back as it was; an interrupt (Ctrl-C) midway is not covered.

const std = @import("std");
const Packages = @import("Packages.zig");
const manifest = @import("manifest.zig");
const files = @import("files.zig");

/// Where a package command works and reports.
pub const Context = @import("Context.zig");

/// The command failed and has said why on stderr.
pub const Failed = Context.Failed;

pub const Error = Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

/// The config's own name in `.dependencies`, which every config needs.
const kosm_name = "kosm";
const manifest_name = "build.zig.zon";
/// What `addConfigProject` installs for `-Dinspect=...`.
const inspector_path = "zig-out/bin/inspect";

/// `kosm add <url>[#ref]`: fetches the package, refuses it when its name is already installed or
/// when it provides no app, adapter or kosmos, and records the url and ref in packages.zon.
pub fn add(context: Context, argument: []const u8) Error!void {
    const package = try fetchName(context, splitRef(argument));
    const original = try readManifest(context);
    if (try isInstalled(context, original, package.name)) {
        return fail(context, "package '{s}' is already installed; kosm update {s} fetches it again", .{ package.name, package.name });
    }
    var packages = try loadPackages(context);

    errdefer restoreManifest(context, original);
    try save(context, package);
    try check(context, package.name);
    try packages.put(context.arena, package);
    try savePackages(context, packages);
    try context.stdout.print("added {s}\n", .{package.name});
}

/// `kosm remove <name>`: deletes the package's entries from build.zig.zon and packages.zon,
/// leaving every other byte of build.zig.zon as it was.
pub fn remove(context: Context, name: []const u8) Error!void {
    if (std.mem.eql(u8, name, kosm_name)) return fail(context, "kosm itself cannot be removed: every config project needs it", .{});
    const original = try readManifest(context);
    const found = manifest.withoutDependency(context.arena, original, name) catch |err| return invalidManifest(context, err);
    const without = found orelse return fail(context, "there is no package '{s}' in {s}", .{ name, manifest_name });
    var packages = try loadPackages(context);

    try writeManifest(context, without);
    errdefer restoreManifest(context, original);
    if (packages.remove(name)) try savePackages(context, packages);
    try context.stdout.print("removed {s}\n", .{name});
}

/// `kosm update [name]`: fetches every package in packages.zon again (or only `name`) at its
/// ref and checks each but kosm itself like `add`. Dependencies missing from packages.zon
/// are skipped.
pub fn update(context: Context, name: ?[]const u8) Error!void {
    const packages = try loadPackages(context);
    const original = try readManifest(context);
    const selected: []const Packages.Package = if (name) |only| blk: {
        const index = for (packages.entries.items, 0..) |package, index| {
            if (std.mem.eql(u8, package.name, only)) break index;
        } else return fail(context, "package '{s}' is not in {s}; kosm update only fetches packages added with kosm add", .{ only, Packages.file_name });
        break :blk packages.entries.items[index..][0..1];
    } else blk: {
        for (manifest.dependencyNames(context.arena, original) catch |err| return invalidManifest(context, err)) |installed| {
            if (packages.find(installed) == null) try context.stdout.print("skipped {s}: kosm add did not install it, so {s} has no url for it\n", .{ installed, Packages.file_name });
        }
        break :blk packages.entries.items;
    };
    if (selected.len == 0) return context.stdout.print("nothing to update: {s} lists no packages\n", .{Packages.file_name});

    errdefer restoreManifest(context, original);
    for (selected) |package| try save(context, package);
    for (selected) |package| {
        // Kosm provides no app, adapter or kosmos; the next build checks it.
        if (!std.mem.eql(u8, package.name, kosm_name)) try check(context, package.name);
    }
    for (selected) |package| try context.stdout.print("updated {s}\n", .{package.name});
}

/// `url#ref` split at the last `#`; the name is filled in by `fetchName`.
fn splitRef(argument: []const u8) Packages.Package {
    const hash = std.mem.findScalarLast(u8, argument, '#') orelse return .{ .name = "", .url = argument };
    return .{ .name = "", .url = argument[0..hash], .ref = argument[hash + 1 ..] };
}

/// Fetches `package` without saving it and names it after its manifest name, which leads
/// its package hash (`kosm_kitty-0.1.0-...`).
fn fetchName(context: Context, package: Packages.Package) Error!Packages.Package {
    const result = try context.runZig(&.{ "fetch", try package.fetchArgument(context.arena) });
    if (!result.term.success()) return failRun(context, result, "zig fetch could not fetch {s}", .{package.url});
    const hash = std.mem.trim(u8, result.stdout, " \t\r\n");
    const dash = std.mem.findScalar(u8, hash, '-') orelse
        return fail(context, "{s} has no package name in its hash ({s}); is its build.zig.zon missing .name?", .{ package.url, hash });
    var named = package;
    named.name = hash[0..dash];
    return named;
}

/// `zig fetch --save=<name>`: writes the package's url and hash into build.zig.zon.
fn save(context: Context, package: Packages.Package) Error!void {
    const result = try context.runZig(&.{ "fetch", try context.arena.print("--save={s}", .{package.name}), try package.fetchArgument(context.arena) });
    if (!result.term.success()) return failRun(context, result, "zig fetch could not save {s}", .{package.name});
}

/// Builds the package against the config and prints what it provides; fails when it does not
/// compile there or provides no app, adapter or kosmos.
fn check(context: Context, name: []const u8) Error!void {
    const build = try context.runZig(&.{ "build", try context.arena.print("-Dinspect={s}", .{name}) });
    if (!build.term.success()) return failRun(context, build, "package '{s}' does not build in this config project", .{name});
    const inspector = try std.Io.Dir.path.join(context.arena, &.{ context.config, inspector_path });
    const result = try context.run(&.{inspector});
    if (!result.term.success()) {
        try context.stderr.writeAll(result.stderr);
        return error.Failed;
    }
    try context.stdout.writeAll(result.stdout);
}

/// Whether `name` is in `source`'s dependencies; reports a manifest it cannot read.
fn isInstalled(context: Context, source: [:0]const u8, name: []const u8) Error!bool {
    return manifest.hasDependency(context.arena, source, name) catch |err| invalidManifest(context, err);
}

const RunResult = std.process.RunResult;

fn readManifest(context: Context) Error![:0]const u8 {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, manifest_name });
    return std.Io.Dir.cwd().readFileAllocOptions(context.io, path, context.arena, .limited(max_manifest_size), .of(u8), 0) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => fail(context, "cannot read {s}: {s}", .{ path, @errorName(err) }),
    };
}

/// A config's manifest is a few dozen lines; this only guards against reading something huge.
const max_manifest_size = 1024 * 1024;

/// Replaces build.zig.zon atomically, keeping its permissions.
fn writeManifest(context: Context, bytes: []const u8) Error!void {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, manifest_name });
    files.replace(context.io, path, bytes) catch |err| return fail(context, "cannot write {s}: {s}", .{ path, @errorName(err) });
}

/// Puts back what build.zig.zon held before the command, after a failure.
fn restoreManifest(context: Context, original: []const u8) void {
    const path = std.Io.Dir.path.join(context.arena, &.{ context.config, manifest_name }) catch return reportUnrestored(context, error.OutOfMemory);
    files.replace(context.io, path, original) catch |err| reportUnrestored(context, err);
}

fn reportUnrestored(context: Context, err: anyerror) void {
    // Already failing; a broken stderr leaves nothing else to report to.
    context.stderr.print("error: cannot put {s} back as it was ({s}); check it with git\n", .{ manifest_name, @errorName(err) }) catch {};
}

fn loadPackages(context: Context) Error!Packages {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, Packages.file_name });
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return Packages.load(context.arena, context.io, path, &diagnostics) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ParseZon => {
            try context.stderr.print("{f}\n", .{diagnostics.fmt(path)});
            return error.Failed;
        },
        else => fail(context, "cannot read {s}: {s}", .{ path, @errorName(err) }),
    };
}

fn savePackages(context: Context, packages: Packages) Error!void {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, Packages.file_name });
    packages.save(context.io, path) catch |err| return fail(context, "cannot write {s}: {s}", .{ path, @errorName(err) });
}

fn invalidManifest(context: Context, err: manifest.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidManifest => fail(context, "{s} in {s} is not valid; zig build says why", .{ manifest_name, context.config }),
    };
}

fn fail(context: Context, comptime format: []const u8, arguments: anytype) Error {
    return context.fail(format, arguments);
}

/// Prints what the failing `zig` said, then the error.
fn failRun(context: Context, result: RunResult, comptime format: []const u8, arguments: anytype) Error {
    context.stderr.writeAll(result.stderr) catch |err| return err;
    return fail(context, format, arguments);
}

const testing = std.testing;

test "a ref is split off at the last #" {
    const with_ref = splitRef("git+https://example.com/x#main");
    try testing.expectEqualStrings("git+https://example.com/x", with_ref.url);
    try testing.expectEqualStrings("main", with_ref.ref.?);
    const without_ref = splitRef("file:///x.tar");
    try testing.expectEqualStrings("file:///x.tar", without_ref.url);
    try testing.expectEqual(null, without_ref.ref);
}

/// A config project in a temp directory, running on this repository's kosm, with tarball
/// packages beside it. Assumes the tests run from the repository root, as `zig build test` does.
const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    /// The temp directory's absolute path.
    root: []const u8,
    environ: std.process.Environ.Map,
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,

    /// Shared by every run so the fetched and compiled std stays warm; fetched test packages
    /// land here instead of in ~/.cache/zig.
    const global_cache = ".zig-cache/kosm-test-global-cache";

    fn init(fixture: *Fixture) !void {
        fixture.tmp = testing.tmpDir(.{});
        fixture.arena = .init(testing.allocator);
        const arena = fixture.arena.allocator();
        fixture.root = try fixture.tmp.dir.realPathFileAlloc(testing.io, ".", arena);
        const repository = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", arena);
        fixture.environ = try testing.environ.createMap(arena);
        _ = fixture.environ.swapRemove("ZIG_PROGRESS");
        try fixture.environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ repository, global_cache }));
        fixture.stdout = .init(arena);
        fixture.stderr = .init(arena);

        const config = try std.Io.Dir.path.join(arena, &.{ fixture.root, "config" });
        const kosm_path = try std.Io.Dir.path.relativeAlloc(arena, repository, null, config, repository);
        try fixture.tmp.dir.createDirPath(testing.io, "config");
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "config/build.zig.zon", .data = try arena.print(
            \\.{{
            \\    .name = .test_config,
            \\    .version = "0.0.0",
            \\    .fingerprint = 0x435328528ec39a09, // Changing this has security and trust implications.
            \\    .minimum_zig_version = "0.17.0",
            \\    .dependencies = .{{
            \\        .kosm = .{{ .path = "{f}" }},
            \\    }},
            \\    .paths = .{{""}},
            \\}}
            \\
        , .{std.zig.fmtString(kosm_path)}) });
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "config/build.zig", .data =
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {
            \\    @import("kosm").addConfigProject(b, @import("build.zig.zon"));
            \\}
            \\
        });
    }

    fn deinit(fixture: *Fixture) void {
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn context(fixture: *Fixture) Context {
        return .{
            .io = testing.io,
            .arena = fixture.arena.allocator(),
            .config = std.Io.Dir.path.join(fixture.arena.allocator(), &.{ fixture.root, "config" }) catch @panic("OOM"),
            .environ_map = &fixture.environ,
            .stdout = &fixture.stdout.writer,
            .stderr = &fixture.stderr.writer,
        };
    }

    /// Packs a package `name` whose root.zig is `root` into `<name>.tar` and returns its url.
    /// The package imports a stub kosm, which the config replaces with its own.
    fn writePackage(fixture: *Fixture, name: []const u8, fingerprint: u64, root: []const u8) ![]const u8 {
        const arena = fixture.arena.allocator();
        var archive: std.Io.Writer.Allocating = .init(arena);
        var tar: std.tar.Writer = .{ .underlying_writer = &archive.writer };
        try tar.writeFileBytes("build.zig.zon", try arena.print(
            \\.{{ .name = .{s}, .version = "0.0.0", .fingerprint = 0x{x}, .minimum_zig_version = "0.17.0", .paths = .{{""}} }}
            \\
        , .{ name, fingerprint }), .{});
        try tar.writeFileBytes("build.zig", try arena.print(
            \\const std = @import("std");
            \\pub fn build(b: *std.Build) void {{
            \\    _ = b.standardTargetOptions(.{{}});
            \\    _ = b.standardOptimizeOption(.{{}});
            \\    const module = b.addModule("{s}", .{{ .root_source_file = b.path("root.zig") }});
            \\    module.addImport("kosm", b.createModule(.{{ .root_source_file = b.path("kosm_stub.zig") }}));
            \\}}
            \\
        , .{name}), .{});
        try tar.writeFileBytes("kosm_stub.zig", "", .{});
        try tar.writeFileBytes("root.zig", root, .{});
        try tar.finishPedantically();
        const file_name = try arena.print("{s}.tar", .{name});
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = file_name, .data = archive.written() });
        return arena.print("file://{s}/{s}", .{ fixture.root, file_name });
    }

    /// A config file's contents, or null when it does not exist.
    fn read(fixture: *Fixture, name: []const u8) !?[]const u8 {
        const path = try std.Io.Dir.path.join(fixture.arena.allocator(), &.{ "config", name });
        return fixture.tmp.dir.readFileAlloc(testing.io, path, fixture.arena.allocator(), .limited(max_manifest_size)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => |other| other,
        };
    }
};

const adapter_fingerprint = 0xc59db0b428404232;
const empty_fingerprint = 0x63199bcf55242cf4;

fn adapterRoot(comptime adapter_name: []const u8) []const u8 {
    return
    \\const kosm = @import("kosm");
    \\pub const adapter: kosm.Adapter = .{ .name = "
    ++ adapter_name ++
        \\", .extensions = &.{".probe"} };
        \\
    ;
}

const empty_root = "pub const answer = 42;\n";

test "add installs a package, reports what it provides and records its url" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const url = try fixture.writePackage("test_adapter", adapter_fingerprint, adapterRoot("probe"));

    try add(fixture.context(), url);
    try testing.expectEqualStrings("test_adapter provides:\n  adapter  probe\nadded test_adapter\n", fixture.stdout.written());
    try testing.expect(std.mem.find(u8, (try fixture.read("build.zig.zon")).?, ".test_adapter = .{") != null);
    const packages = (try fixture.read(Packages.file_name)).?;
    try testing.expect(std.mem.find(u8, packages, try fixture.arena.allocator().print(".test_adapter = .{{ .url = \"{s}\" }},", .{url})) != null);
}

test "add of a package that provides nothing leaves every file as it was" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const url = try fixture.writePackage("test_empty", empty_fingerprint, empty_root);
    const before = (try fixture.read("build.zig.zon")).?;

    try testing.expectError(error.Failed, add(fixture.context(), url));
    try testing.expect(std.mem.find(u8, fixture.stderr.written(), "package 'test_empty' provides no app, adapter or kosmos") != null);
    try testing.expectEqualStrings(before, (try fixture.read("build.zig.zon")).?);
    try testing.expectEqual(null, try fixture.read(Packages.file_name));
}

test "add of an installed name is refused before anything is saved" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const url = try fixture.writePackage("test_adapter", adapter_fingerprint, adapterRoot("probe"));
    try add(fixture.context(), url);
    const installed = (try fixture.read("build.zig.zon")).?;
    const other_url = try fixture.writePackage("test_adapter", adapter_fingerprint, adapterRoot("other"));

    try testing.expectError(error.Failed, add(fixture.context(), other_url));
    try testing.expect(std.mem.find(u8, fixture.stderr.written(), "package 'test_adapter' is already installed; kosm update test_adapter") != null);
    try testing.expectEqualStrings(installed, (try fixture.read("build.zig.zon")).?);
}

test "remove takes back exactly what add wrote, and refuses kosm and unknown names" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const before = (try fixture.read("build.zig.zon")).?;
    try add(fixture.context(), try fixture.writePackage("test_adapter", adapter_fingerprint, adapterRoot("probe")));

    try remove(fixture.context(), "test_adapter");
    try testing.expectEqualStrings(before, (try fixture.read("build.zig.zon")).?);
    try testing.expect(std.mem.find(u8, (try fixture.read(Packages.file_name)).?, "test_adapter") == null);
    try testing.expectError(error.Failed, remove(fixture.context(), "kosm"));
    try testing.expectError(error.Failed, remove(fixture.context(), "test_adapter"));
    try testing.expectEqualStrings(before, (try fixture.read("build.zig.zon")).?);
}

test "update fetches a package again, and a failing check puts build.zig.zon back" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try add(fixture.context(), try fixture.writePackage("test_adapter", adapter_fingerprint, adapterRoot("probe")));
    const added = (try fixture.read("build.zig.zon")).?;

    _ = try fixture.writePackage("test_adapter", adapter_fingerprint, adapterRoot("changed"));
    fixture.stdout.clearRetainingCapacity();
    try update(fixture.context(), null);
    try testing.expectEqualStrings("skipped kosm: kosm add did not install it, so packages.zon has no url for it\n" ++
        "test_adapter provides:\n  adapter  changed\nupdated test_adapter\n", fixture.stdout.written());
    const updated = (try fixture.read("build.zig.zon")).?;
    try testing.expect(!std.mem.eql(u8, added, updated));

    _ = try fixture.writePackage("test_adapter", adapter_fingerprint, empty_root);
    try testing.expectError(error.Failed, update(fixture.context(), "test_adapter"));
    try testing.expectEqualStrings(updated, (try fixture.read("build.zig.zon")).?);
    try testing.expectError(error.Failed, update(fixture.context(), "kosm"));
}

const kosmoi_fingerprint = 0xb0c4401d1234abcd;

/// A package exporting an app writing `~/probe.txt`, a default kosmos and a variant.
const kosmoi_root =
    \\const kosm = @import("kosm");
    \\pub const App = struct {
    \\    size: u8,
    \\    pub fn apply(self: App, output: *kosm.Output) !void {
    \\        try output.template(self, .{ .file = "~/probe.txt", .text = "size kosm.size\n" });
    \\    }
    \\};
    \\pub const Tree = struct { probe: App };
    \\pub const Params = struct { size: u8 = 1 };
    \\pub fn kosmos(params: Params) Tree {
    \\    return .{ .probe = .{ .size = params.size } };
    \\}
    \\pub fn iced() Tree {
    \\    return .{ .probe = .{ .size = 9 } };
    \\}
    \\
;

test "a kosmos from an installed package applies by the package's name" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const arena = fixture.arena.allocator();
    try add(fixture.context(), try fixture.writePackage("test_kosmoi", kosmoi_fingerprint, kosmoi_root));
    try fixture.tmp.dir.createDirPath(testing.io, "home");
    try fixture.environ.put("HOME", try std.Io.Dir.path.join(arena, &.{ fixture.root, "home" }));
    try fixture.environ.put("XDG_STATE_HOME", try std.Io.Dir.path.join(arena, &.{ fixture.root, "state" }));
    const context = fixture.context();
    const runner = try std.Io.Dir.path.join(arena, &.{ context.config, "zig-out/bin/kosmos" });

    const iced_build = try context.runZig(&.{ "build", "-Dkosmos=test_kosmoi.iced" });
    try testing.expect(iced_build.term.success());
    try testing.expect((try context.run(&.{ runner, "--config", context.config })).term.success());
    try testing.expectEqualStrings("size 9\n", try fixture.tmp.dir.readFileAlloc(testing.io, "home/probe.txt", arena, .limited(64)));

    const default_build = try context.runZig(&.{ "build", "-Dkosmos=test_kosmoi" });
    try testing.expect(default_build.term.success());
    const diff = try context.run(&.{ runner, "--size", "4", "--diff", "--config", context.config });
    try testing.expect(diff.term.success());
    try testing.expect(std.mem.find(u8, diff.stdout, "+size 4") != null);

    const missing = try context.runZig(&.{ "build", "-Dkosmos=test_missing" });
    try testing.expect(!missing.term.success());
    try testing.expect(std.mem.find(u8, missing.stderr, "installed packages: test_kosmoi") != null);
}
