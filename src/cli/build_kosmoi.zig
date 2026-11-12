//! `kosm build`: compiles the runner of every kosmos and variant in a config project in one
//! `zig build`, so the next `kosm apply` of any of them compiles nothing until a file changes.

const std = @import("std");
const Context = @import("Context.zig");
const interface = @import("kosm_interface");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dlist`.
const lister_path = "zig-out/bin/list";
/// Where `addConfigProject` marks each kosmos `-Dprebuild=` compiled, with an empty file.
const markers_path = "zig-out/prebuilt";

/// Lists the config's kosmoi, compiles them all, and names each one that does not compile
/// after the others are built.
pub fn build(context: Context) Error!void {
    const names = try kosmosNames(context);
    if (names.len == 0) return context.stdout.writeAll("no kosmoi to build\n");
    try context.stdout.print("building {d} kosmo{s}: {s}\n", .{ names.len, if (names.len == 1) "s" else "i", try std.mem.join(context.arena, ", ", names) });
    try context.stdout.flush();

    const markers = try std.Io.Dir.path.join(context.arena, &.{ context.config, markers_path });
    try deleteMarkers(context, markers);
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.append(context.arena, "build");
    for (names) |name| try arguments.append(context.arena, try context.arena.print("-Dprebuild={s}", .{name}));
    // Which kosmoi failed is read from the markers, so the build's own result adds nothing.
    _ = try context.runBuild(arguments.items);

    var failed: std.ArrayList([]const u8) = .empty;
    for (names) |name| {
        const marker = try std.Io.Dir.path.join(context.arena, &.{ markers, name });
        if (std.Io.Dir.cwd().access(context.io, marker, .{})) |_| {
            try context.stdout.print("built {s}\n", .{name});
        } else |err| switch (err) {
            error.FileNotFound => try failed.append(context.arena, name),
            else => return context.fail("cannot check {s}: {s}", .{ marker, @errorName(err) }),
        }
    }
    try deleteMarkers(context, markers);
    if (failed.items.len == 0) return;
    try context.stdout.flush();
    return context.fail("{s} {s} {s} not build{s}", .{
        if (failed.items.len == 1) "kosmos" else "kosmoi",
        try std.mem.join(context.arena, ", ", failed.items),
        if (failed.items.len == 1) "does" else "do",
        if (failed.items.len == names.len) "" else "; the others are built",
    });
}

/// Every kosmos and variant in the config, as `kosm apply` spells them, from the config's
/// listing program.
fn kosmosNames(context: Context) Error![]const []const u8 {
    if (!try context.runBuild(&.{ "build", "-Dlist" }))
        return context.fail("the config project {s} does not build, so its kosmoi cannot be listed", .{context.config});
    var environ: std.process.Environ.Map = if (context.environ_map) |map| try map.clone(context.arena) else .init(context.arena);
    try environ.put(interface.completions_variable, "1");
    var listing = context;
    listing.environ_map = &environ;
    const result = try listing.run(&.{try std.Io.Dir.path.join(context.arena, &.{ context.config, lister_path })});
    if (!result.term.success()) {
        try context.stderr.writeAll(result.stderr);
        return context.fail("cannot list the kosmoi of {s}", .{context.config});
    }
    return parseNames(context.arena, result.stdout);
}

/// The names in the lister's completion lines, `name<TAB>origin` each.
fn parseNames(arena: std.mem.Allocator, listing: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.tokenizeScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        try names.append(arena, fields.first());
    }
    return names.items;
}

/// Deletes the markers, so none is left from an earlier build.
fn deleteMarkers(context: Context, markers: []const u8) Error!void {
    std.Io.Dir.cwd().deleteTree(context.io, markers) catch |err|
        return context.fail("cannot delete {s}: {s}", .{ markers, @errorName(err) });
}

const testing = std.testing;

/// A kosmos with a variant, holding an app that writes nothing.
const test_frost =
    \\const kosm = @import("kosm");
    \\
    \\pub const Quiet = struct {
    \\    pub fn apply(self: Quiet, output: *kosm.Output) !void {
    \\        _ = self;
    \\        _ = output;
    \\    }
    \\};
    \\
    \\pub fn kosmos() struct { quiet: Quiet } {
    \\    return .{ .quiet = .{} };
    \\}
    \\
    \\pub fn iced() struct { quiet: Quiet } {
    \\    return .{ .quiet = .{} };
    \\}
    \\
;
/// A kosmos that lists, since its signature is fine, but does not compile.
const test_broken =
    \\pub fn kosmos() struct { quiet: @import("frost").Quiet } {
    \\    const size: u8 = "large";
    \\    _ = size;
    \\    return .{ .quiet = .{} };
    \\}
    \\
;

test "build compiles every kosmos and variant for apply, and names the one that does not compile" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var stdout: std.Io.Writer.Allocating = .init(arena);
    var stderr: std.Io.Writer.Allocating = .init(arena);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", arena);
    // Assumes the tests run from the repository root, as `zig build test` does.
    const repository_root = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", arena);
    var environ = try testing.environ.createMap(arena);
    _ = environ.swapRemove("ZIG_PROGRESS");
    // Shared with the other config tests, so the compiled std stays warm.
    try environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ repository_root, ".zig-cache/kosm-test-global-cache" }));
    try environ.put("HOME", try std.Io.Dir.path.join(arena, &.{ root, "home" }));
    try environ.put(interface.environment_variable, try arena.print("{d}", .{interface.version}));
    try tmp.dir.createDirPath(testing.io, "home");
    try tmp.dir.createDirPath(testing.io, "project");
    const test_kosm = @import("test_kosm.zig");
    const context: Context = .{
        .io = testing.io,
        .arena = arena,
        .config = try std.Io.Dir.path.join(arena, &.{ root, "project" }),
        .environ_map = &environ,
        .sources = try test_kosm.sources(arena, testing.io),
        .stdout = &stdout.writer,
        .stderr = &stderr.writer,
    };
    try @import("init.zig").init(context, try test_kosm.stub(arena, testing.io, tmp.dir, root));
    // The starting kosmos needs the real official packages, so it can't be built here.
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.zig", .data = test_frost });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/broken.zig", .data = test_broken });
    stdout.clearRetainingCapacity();

    try testing.expectError(error.Failed, build(context));
    try testing.expect(std.mem.find(u8, stdout.written(), "built frost\n") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), "built frost.iced\n") != null);
    try testing.expect(std.mem.find(u8, stderr.written(), "broken.zig:2:22: error: expected type 'u8'") != null);
    try testing.expect(std.mem.endsWith(u8, stderr.written(), "error: kosmos broken does not build; the others are built\n"));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "project/" ++ markers_path, .{}));

    for ([_][]const u8{ "-Dkosmos=frost", "-Dkosmos=frost.iced" }) |option| {
        const applied = try context.runZig(&.{ "build", option, "--summary", "all" });
        try testing.expect(applied.term.success());
        try testing.expect(std.mem.find(u8, applied.stderr, "compile exe kosmos debug native cached") != null);
    }
}
