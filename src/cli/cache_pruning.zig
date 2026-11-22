//! Deletes the cache folders of a config's executables that newer builds replaced. Zig never
//! deletes from its cache, and each change to a kosmos, script or package leaves the old
//! executable behind, tens or hundreds of megabytes each. Everything else in the cache stays.

const std = @import("std");
const Context = @import("Context.zig");

/// The executables a config build records in `records_folder`: a cache folder holding only one
/// of them is outdated once no record names it.
const recorded_executables = [_][]const u8{ "kosmos", "scripts", "inspect", "list", "kosm-apps" };
/// Zig's build runner, which a build cannot record; only the newest one is kept.
const build_runner = "configurer";
/// Where a config build writes, for each executable, the path of its cache folder.
const records_folder = "zig-out/built";
/// The config cache's folders of build outputs.
const outputs_folder = ".zig-cache/o";
/// A record holds one path; this only guards against reading something huge.
const max_record_size = 64 * 1024;

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error;

/// Deletes the outdated cache folders of the config, after a build that started at `started`.
/// Folders changed since then are kept, as another build may be writing them. Pruning only
/// saves space, so a failure is a warning.
pub fn prune(context: Context, started: std.Io.Timestamp) Error!void {
    var config = std.Io.Dir.cwd().openDir(context.io, context.config, .{}) catch |err| return warn(context, context.config, err);
    defer config.close(context.io);
    const folders = outdated(context.arena, context.io, config, started) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return warn(context, outputs_folder, err),
    };
    for (folders) |folder| {
        const path = try std.Io.Dir.path.join(context.arena, &.{ outputs_folder, folder });
        config.deleteTree(context.io, path) catch |err| return warn(context, path, err);
    }
}

fn warn(context: Context, path: []const u8, err: anyerror) Error!void {
    try context.stderr.print("warning: cannot prune the cache at {s} ({s}); kosm clean deletes it whole\n", .{ path, @errorName(err) });
}

/// One folder of `outputs_folder` holding nothing but an executable kosm prunes.
const Folder = struct {
    name: []const u8,
    executable: []const u8,
    modified: std.Io.Timestamp,
};

/// The names of the folders in `outputs_folder` that a newer build replaced and that have not
/// changed since `started`. A config whose build records nothing (one pinning an older kosm)
/// keeps every recorded kind of executable.
fn outdated(arena: std.mem.Allocator, io: std.Io, config: std.Io.Dir, started: std.Io.Timestamp) ![]const []const u8 {
    const folders = try executableFolders(arena, io, config);
    const current = try recordedFolders(arena, io, config);
    var newest_runner: ?Folder = null;
    for (folders) |folder| {
        if (!std.mem.eql(u8, folder.executable, build_runner)) continue;
        if (newest_runner == null or folder.modified.compare(.gt, newest_runner.?.modified)) newest_runner = folder;
    }
    var result: std.ArrayList([]const u8) = .empty;
    for (folders) |folder| {
        if (!folder.modified.compare(.lt, started)) continue;
        const replaced = if (std.mem.eql(u8, folder.executable, build_runner))
            !std.mem.eql(u8, folder.name, newest_runner.?.name)
        else if (current) |names|
            !names.contains(folder.name)
        else
            false;
        if (replaced) try result.append(arena, folder.name);
    }
    return result.items;
}

/// Every folder of `outputs_folder` whose only entry is an executable kosm prunes; none when
/// the config has no cache.
fn executableFolders(arena: std.mem.Allocator, io: std.Io, config: std.Io.Dir) ![]const Folder {
    var outputs = config.openDir(io, outputs_folder, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer outputs.close(io);
    var result: std.ArrayList(Folder) = .empty;
    var iterator = outputs.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        var folder = try outputs.openDir(io, entry.name, .{ .iterate = true });
        defer folder.close(io);
        const executable = try onlyExecutable(arena, io, folder) orelse continue;
        const stat = try folder.stat(io);
        try result.append(arena, .{ .name = try arena.dupe(u8, entry.name), .executable = executable, .modified = stat.mtime });
    }
    return result.items;
}

/// The name of `folder`'s only entry when it is a file named like an executable kosm prunes.
fn onlyExecutable(arena: std.mem.Allocator, io: std.Io, folder: std.Io.Dir) !?[]const u8 {
    var iterator = folder.iterate();
    const first = try iterator.next(io) orelse return null;
    if (first.kind != .file or !isPruned(first.name)) return null;
    const name = try arena.dupe(u8, first.name);
    if (try iterator.next(io) != null) return null;
    return name;
}

fn isPruned(name: []const u8) bool {
    if (std.mem.eql(u8, name, build_runner)) return true;
    for (recorded_executables) |executable| {
        if (std.mem.eql(u8, name, executable)) return true;
    }
    return false;
}

/// The names of the cache folders the records point into, or null when the config's build
/// records nothing.
fn recordedFolders(arena: std.mem.Allocator, io: std.Io, config: std.Io.Dir) !?std.StringHashMapUnmanaged(void) {
    var records = config.openDir(io, records_folder, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer records.close(io);
    var result: std.StringHashMapUnmanaged(void) = .empty;
    var walker = try records.walk(arena);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, arena, .limited(max_record_size));
        const path = try recordedPath(arena, source) orelse continue;
        const folder = std.Io.Dir.path.dirname(path) orelse continue;
        try result.put(arena, std.Io.Dir.path.basename(folder), {});
    }
    return result;
}

/// The path in a record, which the build writes as `pub const path: []const u8 = "...";`; null
/// for anything else.
fn recordedPath(arena: std.mem.Allocator, source: []const u8) !?[]const u8 {
    const start = std.mem.findScalar(u8, source, '"') orelse return null;
    const end = std.mem.findScalarLast(u8, source, '"') orelse return null;
    if (end <= start) return null;
    return std.zig.string_literal.parseAlloc(arena, source[start .. end + 1]) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => null,
    };
}

const testing = std.testing;

fn writeFiles(dir: std.Io.Dir, files: []const [2][]const u8) !void {
    for (files) |file| {
        if (std.Io.Dir.path.dirname(file[0])) |directory| try dir.createDirPath(testing.io, directory);
        try dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    }
}

fn record(comptime folder: []const u8, comptime executable: []const u8) []const u8 {
    return "pub const path: []const u8 = \".zig-cache/o/" ++ folder ++ "/" ++ executable ++ "\";\n";
}

fn sorted(names: []const []const u8) []const []const u8 {
    const copy = @constCast(names);
    std.mem.sort([]const u8, copy, {}, struct {
        fn lessThan(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.order(u8, left, right) == .lt;
        }
    }.lessThan);
    return copy;
}

fn later() std.Io.Timestamp {
    return std.Io.Timestamp.now(testing.io, .real).addDuration(.fromSeconds(60));
}

test "replaced executables are outdated, while recorded ones, other kosmoi and other outputs stay" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    try writeFiles(tmp.dir, &.{
        .{ "zig-out/built/kosmos/frost", record("frost-new", "kosmos") },
        .{ "zig-out/built/kosmos/frost.iced", record("iced", "kosmos") },
        .{ "zig-out/built/scripts", record("scripts-new", "scripts") },
        .{ ".zig-cache/o/frost-old/kosmos", "" },
        .{ ".zig-cache/o/frost-new/kosmos", "" },
        .{ ".zig-cache/o/iced/kosmos", "" },
        .{ ".zig-cache/o/scripts-old/scripts", "" },
        .{ ".zig-cache/o/scripts-new/scripts", "" },
        .{ ".zig-cache/o/inspect-old/inspect", "" },
        .{ ".zig-cache/o/grammar/parser.o", "" },
        .{ ".zig-cache/o/completions/kosmos", "" },
        .{ ".zig-cache/o/completions/editor", "" },
    });
    const found = try outdated(arena_state.allocator(), testing.io, tmp.dir, later());
    try testing.expectEqualDeep(@as([]const []const u8, &.{ "frost-old", "inspect-old", "scripts-old" }), sorted(found));
}

test "folders changed since the build started are never outdated" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    try writeFiles(tmp.dir, &.{
        .{ "zig-out/built/kosmos/frost", record("frost-new", "kosmos") },
        .{ ".zig-cache/o/frost-old/kosmos", "" },
    });
    const earlier = std.Io.Timestamp.now(testing.io, .real).subDuration(.fromSeconds(60));
    try testing.expectEqual(0, (try outdated(arena_state.allocator(), testing.io, tmp.dir, earlier)).len);
}

test "a config whose build records nothing keeps its executables but not old build runners" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    try writeFiles(tmp.dir, &.{
        .{ ".zig-cache/o/frost/kosmos", "" },
        .{ ".zig-cache/o/runner-old/configurer", "" },
    });
    // Folder times have a coarse resolution on some file systems, so the newer runner waits.
    try testing.io.sleep(.fromMilliseconds(20), .awake);
    try writeFiles(tmp.dir, &.{.{ ".zig-cache/o/runner-new/configurer", "" }});
    const found = try outdated(arena_state.allocator(), testing.io, tmp.dir, later());
    try testing.expectEqualDeep(@as([]const []const u8, &.{"runner-old"}), found);
}

test "prune deletes only the outdated folders" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try writeFiles(tmp.dir, &.{
        .{ "zig-out/built/kosmos/frost", record("frost-new", "kosmos") },
        .{ ".zig-cache/o/frost-old/kosmos", "" },
        .{ ".zig-cache/o/frost-new/kosmos", "" },
    });
    var stderr: std.Io.Writer.Allocating = .init(arena);
    var stdout: std.Io.Writer.Allocating = .init(arena);
    const context: Context = .{
        .io = testing.io,
        .arena = arena,
        .config = try tmp.dir.realPathFileAlloc(testing.io, ".", arena),
        .stdout = &stdout.writer,
        .stderr = &stderr.writer,
    };
    try prune(context, later());
    try testing.expectEqualStrings("", stderr.written());
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, ".zig-cache/o/frost-old", .{}));
    try tmp.dir.access(testing.io, ".zig-cache/o/frost-new/kosmos", .{});
}
