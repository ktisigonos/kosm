//! Walks the directories a selector glob reaches (D79), collecting the files it matches.
//! Everything lives in `allocator`, an arena.

const Walker = @This();

const std = @import("std");
const glob = @import("../glob.zig");
const Found = @import("Found.zig");
const Failure = @import("Failure.zig");

allocator: std.mem.Allocator,
io: std.Io,
failure: *Failure,
found: std.ArrayList(Found) = .empty,
/// A directory's real path with the number of segments left, so loops and repeated `**`
/// routes are walked once.
visited: std.StringHashMapUnmanaged(void) = .empty,

/// Adds every file under `directory` matching `segments`, each a suffix of one pattern's
/// segments. A file reached by two routes is added twice; `glob.expand` keeps one.
pub fn walk(walker: *Walker, directory: []const u8, segments: []const []const u8) glob.Error!void {
    if (!try walker.firstVisit(directory, segments.len)) return;
    const segment = segments[0];
    if (std.mem.eql(u8, segment, "**")) {
        try walker.walk(directory, segments[1..]);
        var dir = try walker.open(directory) orelse return;
        defer dir.close(walker.io);
        var iterator = dir.iterate();
        while (try walker.next(&iterator, directory)) |entry| {
            if (entry.name[0] == '.') continue;
            if (try walker.kindOf(dir, entry) == .directory) try walker.walk(try walker.join(directory, entry.name), segments);
        }
        return;
    }
    if (std.mem.indexOfScalar(u8, segment, '*') == null) {
        const child = try walker.join(directory, segment);
        const stat = std.Io.Dir.cwd().statFile(walker.io, child, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return,
            else => return walker.fail(child, err),
        };
        return walker.visit(child, stat.kind, segments);
    }
    var dir = try walker.open(directory) orelse return;
    defer dir.close(walker.io);
    var iterator = dir.iterate();
    while (try walker.next(&iterator, directory)) |entry| {
        if (!glob.matchesName(segment, entry.name)) continue;
        const kind = try walker.kindOf(dir, entry) orelse continue;
        try walker.visit(try walker.join(directory, entry.name), kind, segments);
    }
}

fn visit(walker: *Walker, path: []const u8, kind: std.Io.File.Kind, segments: []const []const u8) glob.Error!void {
    if (segments.len == 1) {
        if (kind == .file) try walker.addFile(path);
    } else if (kind == .directory) {
        try walker.walk(path, segments[1..]);
    }
}

fn addFile(walker: *Walker, path: []const u8) glob.Error!void {
    const real = std.Io.Dir.cwd().realPathFileAlloc(walker.io, path, walker.allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return walker.fail(path, err),
    };
    try walker.found.append(walker.allocator, .{ .path = path, .real = real });
}

fn firstVisit(walker: *Walker, directory: []const u8, segments_left: usize) glob.Error!bool {
    const real = std.Io.Dir.cwd().realPathFileAlloc(walker.io, directory, walker.allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return walker.fail(directory, err),
    };
    const key = try walker.allocator.print("{s}\x00{d}", .{ real, segments_left });
    const entry = try walker.visited.getOrPut(walker.allocator, key);
    return !entry.found_existing;
}

fn open(walker: *Walker, directory: []const u8) glob.Error!?std.Io.Dir {
    return std.Io.Dir.cwd().openDir(walker.io, directory, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => null,
        else => walker.fail(directory, err),
    };
}

fn next(walker: *Walker, iterator: *std.Io.Dir.Iterator, directory: []const u8) glob.Error!?std.Io.Dir.Entry {
    return iterator.next(walker.io) catch |err| walker.fail(directory, err);
}

/// The kind of what `entry` names, through symlinks; null for a broken link.
fn kindOf(walker: *Walker, dir: std.Io.Dir, entry: std.Io.Dir.Entry) glob.Error!?std.Io.File.Kind {
    if (entry.kind != .sym_link and entry.kind != .unknown) return entry.kind;
    const stat = dir.statFile(walker.io, entry.name, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return null,
        else => return walker.fail(entry.name, err),
    };
    return stat.kind;
}

fn join(walker: *Walker, directory: []const u8, name: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.Io.Dir.path.join(walker.allocator, &.{ directory, name });
}

fn fail(walker: *Walker, path: []const u8, err: anyerror) error{Unreadable} {
    walker.failure.* = .{ .path = path, .reason = @errorName(err) };
    return error.Unreadable;
}
