//! Script kosmoi for `kosm apply` and `kosm build`: a file `kosmoi/<name>.<extension>` that a
//! frontend reads, run by the one runner every script shares. The runner is rebuilt only when Zig
//! code it is built from (the config's, its local packages' or kosm's own) changed since it was
//! last built, never on a script edit.

const std = @import("std");
const Context = @import("Context.zig");
const interface = @import("kosm_interface");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dscripts`.
pub const runner_path = "zig-out/bin/scripts";
/// Written when a build of the runner starts and kept once it succeeded; Zig code newer than
/// it means the runner is stale.
const stamp_path = "zig-out/scripts.built";
/// Where script kosmoi live, in the config's root.
const kosmoi_directory = "kosmoi";
/// The config's own files and folders the runner is built from.
const config_files = [_][]const u8{ "build.zig", "build.zig.zon" };
const config_folders = [_][]const u8{ "kosmoi", "apps", "adapters" };
/// Kosm's own files and folders in its sources.
const source_files = [_][]const u8{ "build.zig", "build.zig.zon" };
const source_folders = [_][]const u8{ "src", "build" };
/// Folders a walk never enters: build output, fetched packages, caches.
const skipped_folders = [_][]const u8{ "zig-out", "zig-pkg", ".zig-cache" };

/// Whether kosmos `name` ("minimal", or "minimal.x" which the runner refuses) is a script: a
/// file in `kosmoi/` named after its part before the first dot, with any extension but Zig's.
/// An empty `name` asks whether there is any script.
pub fn isScript(context: Context, name: []const u8) Error!bool {
    const file_part = name[0 .. std.mem.findScalar(u8, name, '.') orelse name.len];
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, kosmoi_directory });
    var dir = std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch return false;
    defer dir.close(context.io);
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) })) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (std.mem.startsWith(u8, entry.name, ".") or std.mem.endsWith(u8, entry.name, ".zig")) continue;
        const dot = std.mem.findScalar(u8, entry.name, '.') orelse continue;
        if (file_part.len == 0 or std.mem.eql(u8, entry.name[0..dot], file_part)) return true;
    }
    return false;
}

/// Whether `kosmoi/` holds any script kosmos.
pub fn any(context: Context) Error!bool {
    return isScript(context, "");
}

/// Builds the runner when it is missing or stale; returns whether it is ready.
pub fn prepare(context: Context) Error!bool {
    if (!try isStale(context)) return true;
    return build(context);
}

/// Builds the runner, whatever its state; returns whether it succeeded.
pub fn build(context: Context) Error!bool {
    const stamp = try std.Io.Dir.path.join(context.arena, &.{ context.config, stamp_path });
    // Stamped before building, so a file edited during the build is newer than the stamp.
    std.Io.Dir.cwd().createDirPath(context.io, std.Io.Dir.path.dirname(stamp).?) catch |err|
        return context.fail("cannot create {s}: {s}", .{ std.Io.Dir.path.dirname(stamp).?, @errorName(err) });
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = stamp, .data = "" }) catch |err|
        return context.fail("cannot write {s}: {s}", .{ stamp, @errorName(err) });
    if (try context.runBuild(&.{ "build", "-Dscripts" })) return true;
    std.Io.Dir.cwd().deleteFile(context.io, stamp) catch {};
    return false;
}

/// Whether the runner is missing, or any Zig file it is built from is newer than its stamp. What
/// cannot be read counts as changed: a needless build is safe, a stale runner is not.
fn isStale(context: Context) Error!bool {
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    std.Io.Dir.cwd().access(context.io, runner, .{}) catch return true;
    const stamp_file = try std.Io.Dir.path.join(context.arena, &.{ context.config, stamp_path });
    const stamp = std.Io.Dir.cwd().statFile(context.io, stamp_file, .{}) catch return true;
    if (try anyNewer(context, context.config, &config_files, &config_folders, stamp.mtime)) return true;
    const sources = context.sources orelse return false;
    return anyNewer(context, sources.directory, &source_files, &source_folders, stamp.mtime);
}

/// Whether one of `files` in `root`, or a Zig file or manifest anywhere in its `folders`, was
/// changed after `since`.
fn anyNewer(context: Context, root: []const u8, files: []const []const u8, folders: []const []const u8, since: std.Io.Timestamp) Error!bool {
    var dir = std.Io.Dir.cwd().openDir(context.io, root, .{}) catch return true;
    defer dir.close(context.io);
    for (files) |file| {
        const stat = dir.statFile(context.io, file, .{}) catch continue;
        if (stat.mtime.compare(.gt, since)) return true;
    }
    for (folders) |folder| {
        var tree = dir.openDir(context.io, folder, .{ .iterate = true }) catch continue;
        defer tree.close(context.io);
        var walker = tree.walkSelectively(context.arena) catch return true;
        defer walker.deinit();
        while (walker.next(context.io) catch return true) |entry| {
            if (std.mem.startsWith(u8, entry.basename, ".")) continue;
            switch (entry.kind) {
                .directory => if (!isSkipped(entry.basename)) walker.enter(context.io, entry) catch return true,
                .file, .sym_link => if (std.mem.endsWith(u8, entry.basename, ".zig") or std.mem.endsWith(u8, entry.basename, ".zon")) {
                    const stat = entry.dir.statFile(context.io, entry.basename, .{}) catch return true;
                    if (stat.mtime.compare(.gt, since)) return true;
                },
                else => {},
            }
        }
    }
    return false;
}

fn isSkipped(folder: []const u8) bool {
    for (skipped_folders) |skipped| {
        if (std.mem.eql(u8, folder, skipped)) return true;
    }
    return false;
}

const testing = std.testing;

/// A frontend reading one setting per line: `base frost`, `param size=12`,
/// `theme palette.black=#000000` or `set kitty.fonts.font_size=9`.
const test_frontend =
    \\const std = @import("std");
    \\const kosm = @import("kosm");
    \\
    \\pub const frontend: kosm.Frontend = .{ .name = "lines", .extensions = &.{".kosmos"}, .load = load };
    \\
    \\fn load(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.Script {
    \\    var script: kosm.Frontend.Script = .{};
    \\    var params: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    var theme: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    var overrides: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    var number: usize = 0;
    \\    while (lines.next()) |line| {
    \\        number += 1;
    \\        if (line.len == 0) continue;
    \\        const space = std.mem.findScalar(u8, line, ' ') orelse return context.fail("{s}: expected a keyword and a value", .{try context.at(number)});
    \\        const rest = line[space + 1 ..];
    \\        if (std.mem.eql(u8, line[0..space], "base")) {
    \\            script.base = rest;
    \\            continue;
    \\        }
    \\        const list = if (std.mem.eql(u8, line[0..space], "param")) &params else if (std.mem.eql(u8, line[0..space], "theme")) &theme else &overrides;
    \\        const equals = std.mem.findScalar(u8, rest, '=') orelse return context.fail("{s}: expected path=value", .{try context.at(number)});
    \\        try list.append(context.arena, try nested(context.arena, rest[0..equals], .{ .value = .{ .text = rest[equals + 1 ..] }, .origin = try context.at(number) }));
    \\    }
    \\    if (params.items.len != 0) script.params = .{ .value = .{ .table = params.items } };
    \\    if (theme.items.len != 0) script.theme = .{ .value = .{ .table = theme.items } };
    \\    if (overrides.items.len != 0) script.overrides = .{ .value = .{ .table = overrides.items } };
    \\    return script;
    \\}
    \\
    \\fn nested(arena: std.mem.Allocator, path: []const u8, leaf: kosm.Loose) !kosm.Loose.Entry {
    \\    const dot = std.mem.findScalar(u8, path, '.') orelse return .{ .key = path, .value = leaf };
    \\    const inner = try arena.dupe(kosm.Loose.Entry, &.{try nested(arena, path[dot + 1 ..], leaf)});
    \\    return .{ .key = path[0..dot], .value = .{ .value = .{ .table = inner } } };
    \\}
    \\
;

/// A Zig kosmos wearing the stub kitty, its font size a parameter.
const test_frost =
    \\const kosm = @import("kosm");
    \\const kitty = @import("kosm_kitty");
    \\
    \\pub fn kosmos(params: struct { size: u32 = 10 }) struct { kitty: kitty.App } {
    \\    return .{ .kitty = .{ .fonts = .{ .font_size = params.size } } };
    \\}
    \\
;

/// Runs script kosmos `name` with `--diff`; returns stdout, or stderr when it failed.
fn testDiff(context: Context, name: []const u8) ![]const u8 {
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    const applied = try context.run(&.{ runner, name, "--diff", "--config", context.config });
    return if (applied.term.success()) applied.stdout else applied.stderr;
}

test "script kosmoi apply on a Zig kosmos, on each other and on none, and a script edit builds nothing" {
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
    // The starting kosmos needs the real official packages, and the runner holds every kosmos.
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.zig", .data = test_frost });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/lines.zig", .data = test_frontend });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/on.kosmos", .data = "base frost\nparam size=12\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/over.kosmos", .data = "base on\nset kitty.fonts.font_size=14\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/alone.kosmos", .data = "theme palette.black=#000000\ntheme palette.white=#ffffff\ntheme mode=dark\nset kitty.fonts.font_size=9\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/bad.kosmos", .data = "base frost\nset kitty.fonts.font_size=big\n" });

    try testing.expect(try isScript(context, "on"));
    try testing.expect(!try isScript(context, "frost"));
    try testing.expect(try prepare(context));
    try testing.expect(std.mem.find(u8, try testDiff(context, "on"), "+font_size 12\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "over"), "+font_size 14\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "alone"), "+font_size 9\n") != null);
    try testing.expectEqualStrings("error: kosmos 'bad': kosmoi/bad.kosmos:2: kitty.fonts.font_size: expected an integer that fits u32, got 'big'\n", try testDiff(context, "bad"));

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/on.kosmos", .data = "base frost\nparam size=13\n" });
    try testing.expect(!try isStale(context));
    try testing.expect(std.mem.find(u8, try testDiff(context, "on"), "+font_size 13\n") != null);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.zig", .data = test_frost });
    try testing.expect(try isStale(context));

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.kosmos", .data = "" });
    stderr.clearRetainingCapacity();
    try testing.expect(!try build(context));
    try testing.expect(std.mem.find(u8, stderr.written(), "'frost' names both the script kosmoi/frost.kosmos and kosmoi/frost.zig") != null);
}
