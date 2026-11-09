//! The kosm sources the builds kosm runs use in place of the kosm a config pins: the
//! per-machine override `kosm source` records, else the sources installed beside the binary.

const Sources = @This();

const std = @import("std");
const Record = @import("kosm_current");
const manifest = @import("manifest.zig");

/// The sources' absolute path: a directory holding kosm's `build.zig.zon`.
directory: []const u8,
origin: Origin,

pub const Origin = enum {
    /// Recorded with `kosm source <dir>`.
    override,
    /// `<prefix>/share/kosm`, beside the running `<prefix>/bin/kosm`.
    installed,
};

/// The override's file name in kosm's state directory.
const override_file = "source.zon";
/// Where `zig build install` puts the sources, relative to the binary's directory.
const installed_relative = "../share/kosm";
/// The override is one line; anything bigger is not one.
const max_override_size = 64 * 1024;

const Override = struct { directory: []const u8 };

pub const LoadError = error{ ParseZon, OutOfMemory } || std.Io.Dir.ReadFileAllocError;

/// The sources builds use, or null to build with the kosm each config pins. On
/// `error.ParseZon`, `diagnostics` says what is wrong with the override file.
pub fn find(io: std.Io, arena: std.mem.Allocator, environ: *const std.process.Environ.Map, diagnostics: *std.zon.parse.Diagnostics) LoadError!?Sources {
    if (try loadOverride(io, arena, environ, diagnostics)) |directory| return .{ .directory = directory, .origin = .override };
    // A binary that cannot find itself has no installed sources to use.
    const executable_directory = std.process.executableDirPathAlloc(io, arena) catch return null;
    const installed = try installedBeside(io, arena, executable_directory) orelse return null;
    return .{ .directory = installed, .origin = .installed };
}

/// `share/kosm` beside the `bin/` directory `executable_directory`, when it holds kosm's sources.
pub fn installedBeside(io: std.Io, arena: std.mem.Allocator, executable_directory: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const directory = try std.Io.Dir.path.resolve(arena, &.{ executable_directory, installed_relative });
    return if (try holdsKosm(io, arena, directory)) directory else null;
}

/// Whether `directory` holds a manifest named `kosm`.
pub fn holdsKosm(io: std.Io, arena: std.mem.Allocator, directory: []const u8) std.mem.Allocator.Error!bool {
    const path = try std.Io.Dir.path.join(arena, &.{ directory, "build.zig.zon" });
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .limited(1024 * 1024), .of(u8), 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    const name = manifest.packageName(arena, source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidManifest => return false,
    };
    return if (name) |found| std.mem.eql(u8, found, "kosm") else false;
}

/// The override file's path; null without a state directory.
pub fn overridePath(arena: std.mem.Allocator, environ: *const std.process.Environ.Map) std.mem.Allocator.Error!?[]const u8 {
    return Record.statePath(arena, environ, override_file);
}

/// The directory `kosm source` recorded, or null when there is none.
pub fn loadOverride(io: std.Io, arena: std.mem.Allocator, environ: *const std.process.Environ.Map, diagnostics: *std.zon.parse.Diagnostics) LoadError!?[]const u8 {
    const path = try overridePath(arena, environ) orelse return null;
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .limited(max_override_size), .of(u8), 0) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |other| return other,
    };
    const override = try std.zon.parse.fromSlice(Override, .{ .gpa = arena, .arena = arena, .source = source, .diagnostics = diagnostics });
    return override.directory;
}

/// Records `directory`, an absolute path, as the sources builds use on this machine.
pub fn saveOverride(io: std.Io, path: []const u8, directory: []const u8) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    var buffer: [1024]u8 = undefined;
    var file_writer = atomic.file.writer(io, &buffer);
    const override: Override = .{ .directory = directory };
    std.zon.stringify.serialize(override, .{}, &file_writer.interface) catch return file_writer.err orelse error.WriteFailed;
    file_writer.interface.writeByte('\n') catch return file_writer.err orelse error.WriteFailed;
    file_writer.interface.flush() catch return file_writer.err orelse error.WriteFailed;
    try atomic.replace(io);
}

/// Removes the override; returns whether there was one.
pub fn removeOverride(io: std.Io, path: []const u8) !bool {
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    return true;
}

/// `--fork=<directory>` for a `zig build` in `project`, or null when its manifest does not depend
/// on `kosm` by hash: a `.path` kosm can't be forked, and Zig fails a fork that matches nothing.
pub fn forkArgument(sources: Sources, io: std.Io, arena: std.mem.Allocator, project: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const path = try std.Io.Dir.path.join(arena, &.{ project, "build.zig.zon" });
    // A missing or broken manifest is for `zig build` itself to report.
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .limited(1024 * 1024), .of(u8), 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    const dependencies = manifest.dependencies(arena, source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidManifest => return null,
    };
    for (dependencies) |dependency| {
        if (std.mem.eql(u8, dependency.name, "kosm") and dependency.hash != null) return try std.fmt.allocPrint(arena, "--fork={s}", .{sources.directory});
    }
    return null;
}

const testing = std.testing;

const TestDirectory = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root: []const u8,

    fn init(test_directory: *TestDirectory) !void {
        test_directory.tmp = testing.tmpDir(.{});
        test_directory.arena = .init(testing.allocator);
        test_directory.root = try test_directory.tmp.dir.realPathFileAlloc(testing.io, ".", test_directory.arena.allocator());
    }

    fn deinit(test_directory: *TestDirectory) void {
        test_directory.arena.deinit();
        test_directory.tmp.cleanup();
    }

    fn write(test_directory: *TestDirectory, path: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(path)) |directory| try test_directory.tmp.dir.createDirPath(testing.io, directory);
        try test_directory.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }
};

test "installed sources are found beside the binary only when they hold kosm" {
    var test_directory: TestDirectory = undefined;
    try test_directory.init();
    defer test_directory.deinit();
    const arena = test_directory.arena.allocator();
    const bin = try std.Io.Dir.path.join(arena, &.{ test_directory.root, "usr/bin" });
    try test_directory.tmp.dir.createDirPath(testing.io, "usr/bin");

    try testing.expectEqual(null, try installedBeside(testing.io, arena, bin));
    try test_directory.write("usr/share/kosm/build.zig.zon", ".{ .name = .other, .version = \"0.0.0\" }\n");
    try testing.expectEqual(null, try installedBeside(testing.io, arena, bin));
    try test_directory.write("usr/share/kosm/build.zig.zon", ".{ .name = .kosm, .version = \"0.0.0\" }\n");
    const expected = try std.Io.Dir.path.join(arena, &.{ test_directory.root, "usr/share/kosm" });
    try testing.expectEqualStrings(expected, (try installedBeside(testing.io, arena, bin)).?);
}

test "the override is saved, found first, and removed" {
    var test_directory: TestDirectory = undefined;
    try test_directory.init();
    defer test_directory.deinit();
    const arena = test_directory.arena.allocator();
    var environ: std.process.Environ.Map = .init(arena);
    try environ.put("XDG_STATE_HOME", try std.Io.Dir.path.join(arena, &.{ test_directory.root, "state" }));
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const path = (try overridePath(arena, &environ)).?;

    try testing.expectEqual(null, try loadOverride(testing.io, arena, &environ, &diagnostics));
    try saveOverride(testing.io, path, "/home/me/kosm \"checkout\"");
    try testing.expectEqualStrings("/home/me/kosm \"checkout\"", (try loadOverride(testing.io, arena, &environ, &diagnostics)).?);
    const found = (try find(testing.io, arena, &environ, &diagnostics)).?;
    try testing.expectEqual(Origin.override, found.origin);
    try testing.expectEqualStrings("/home/me/kosm \"checkout\"", found.directory);

    try testing.expect(try removeOverride(testing.io, path));
    try testing.expect(!try removeOverride(testing.io, path));
    try testing.expectEqual(null, try loadOverride(testing.io, arena, &environ, &diagnostics));
}

test "a broken override is an error, never ignored" {
    var test_directory: TestDirectory = undefined;
    try test_directory.init();
    defer test_directory.deinit();
    const arena = test_directory.arena.allocator();
    var environ: std.process.Environ.Map = .init(arena);
    try environ.put("XDG_STATE_HOME", try std.Io.Dir.path.join(arena, &.{ test_directory.root, "state" }));
    try test_directory.write("state/kosm/source.zon", ".{ .folder = 1 }\n");
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    try testing.expectError(error.ParseZon, loadOverride(testing.io, arena, &environ, &diagnostics));
}

test "only a project depending on kosm by hash gets --fork" {
    var test_directory: TestDirectory = undefined;
    try test_directory.init();
    defer test_directory.deinit();
    const arena = test_directory.arena.allocator();
    const sources: Sources = .{ .directory = "/usr/share/kosm", .origin = .installed };

    try testing.expectEqual(null, try sources.forkArgument(testing.io, arena, test_directory.root));
    try test_directory.write("build.zig.zon", ".{ .name = .config, .dependencies = .{ .kosm = .{ .path = \"../kosm\" } } }\n");
    try testing.expectEqual(null, try sources.forkArgument(testing.io, arena, test_directory.root));
    try test_directory.write("build.zig.zon", ".{ .name = .config, .dependencies = .{ .other = .{ .url = \"x\", .hash = \"h\" } } }\n");
    try testing.expectEqual(null, try sources.forkArgument(testing.io, arena, test_directory.root));
    try test_directory.write("build.zig.zon", ".{ .name = .config, .dependencies = .{ .kosm = .{ .url = \"git+https://example.com/kosm\", .hash = \"kosm-0.0.0-abc\" } } }\n");
    try testing.expectEqualStrings("--fork=/usr/share/kosm", (try sources.forkArgument(testing.io, arena, test_directory.root)).?);
}
