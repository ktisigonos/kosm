//! The files a selector glob picks (D79): `*` matches any part of a name inside one directory,
//! `**` as a whole segment matches zero or more directories. Hidden entries match only a segment
//! that itself starts with a dot. Symlinks are followed; a file reached twice counts once.

const std = @import("std");
const Walker = @import("glob/Walker.zig");

/// One file a glob picked.
pub const Found = @import("glob/Found.zig");
/// Why a glob could not be expanded.
pub const Failure = @import("glob/Failure.zig");

/// Errors from `expand`; `error.Unreadable` fills the `Failure`.
pub const Error = std.mem.Allocator.Error || error{Unreadable};

/// The files matching absolute `pattern` and none of the absolute `exclude` globs, sorted by
/// path (D31's match order). Missing directories match nothing. Everything lives in `allocator`.
pub fn expand(allocator: std.mem.Allocator, io: std.Io, pattern: []const u8, exclude: []const []const u8, failure: *Failure) Error![]const Found {
    std.debug.assert(std.Io.Dir.path.isAbsolute(pattern));
    var segments = try split(allocator, pattern);
    // A final `**` means every file beneath, which is `**/*`.
    if (segments.items.len != 0 and std.mem.eql(u8, segments.items[segments.items.len - 1], "**")) try segments.append(allocator, "*");
    if (segments.items.len == 0) return &.{};

    var walker: Walker = .{ .allocator = allocator, .io = io, .failure = failure };
    try walker.walk("/", segments.items);

    // Sorting first makes the route kept for a file reached twice the first by path.
    std.mem.sort(Found, walker.found.items, {}, pathLessThan);
    var real_paths: std.StringHashMapUnmanaged(void) = .empty;
    var kept: std.ArrayList(Found) = .empty;
    for (walker.found.items) |found| {
        if ((try real_paths.getOrPut(allocator, found.real)).found_existing) continue;
        if (!try isExcluded(allocator, found.path, exclude)) try kept.append(allocator, found);
    }
    return kept.items;
}

fn isExcluded(allocator: std.mem.Allocator, path: []const u8, exclude: []const []const u8) std.mem.Allocator.Error!bool {
    if (exclude.len == 0) return false;
    const path_segments = try split(allocator, path);
    for (exclude) |pattern| {
        const pattern_segments = try split(allocator, pattern);
        if (matchesSegments(pattern_segments.items, path_segments.items)) return true;
    }
    return false;
}

fn split(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error!std.ArrayList([]const u8) {
    var segments: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, path, '/');
    while (iterator.next()) |segment| try segments.append(allocator, segment);
    return segments;
}

fn pathLessThan(_: void, left: Found, right: Found) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

/// Whether path segments match glob segments, `**` taking zero or more of them.
fn matchesSegments(pattern: []const []const u8, path: []const []const u8) bool {
    if (pattern.len == 0) return path.len == 0;
    if (std.mem.eql(u8, pattern[0], "**")) {
        for (0..path.len + 1) |skipped| {
            if (matchesSegments(pattern[1..], path[skipped..])) return true;
        }
        return false;
    }
    return path.len != 0 and matchesName(pattern[0], path[0]) and matchesSegments(pattern[1..], path[1..]);
}

/// Whether `name` matches one glob segment, where `*` is any run of characters. A hidden name
/// matches only a segment starting with a dot.
pub fn matchesName(pattern: []const u8, name: []const u8) bool {
    if (name.len != 0 and name[0] == '.' and (pattern.len == 0 or pattern[0] != '.')) return false;
    var pattern_index: usize = 0;
    var name_index: usize = 0;
    var star: ?usize = null;
    var star_name_index: usize = 0;
    while (name_index < name.len) {
        if (pattern_index < pattern.len and pattern[pattern_index] == '*') {
            star = pattern_index;
            star_name_index = name_index;
            pattern_index += 1;
        } else if (pattern_index < pattern.len and pattern[pattern_index] == name[name_index]) {
            pattern_index += 1;
            name_index += 1;
        } else if (star) |star_index| {
            // Let the last `*` take one more character and retry from there.
            pattern_index = star_index + 1;
            star_name_index += 1;
            name_index = star_name_index;
        } else return false;
    }
    while (pattern_index < pattern.len and pattern[pattern_index] == '*') pattern_index += 1;
    return pattern_index == pattern.len;
}

const testing = std.testing;

test "matchesName takes * as any run and keeps hidden names out" {
    try testing.expect(matchesName("*.lua", "blur.lua"));
    try testing.expect(matchesName("*", "x"));
    try testing.expect(matchesName("a*b*c", "aXbYbZc"));
    try testing.expect(!matchesName("*.lua", "blur.luac"));
    try testing.expect(!matchesName("*", ".git"));
    try testing.expect(matchesName(".*", ".git"));
    try testing.expect(matchesName("blur.lua", "blur.lua"));
}

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    root: []const u8 = "",

    fn init(fixture: *Fixture, files: []const []const u8) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator) };
        fixture.root = fixture.root_buffer[0..try fixture.tmp.dir.realPath(testing.io, &fixture.root_buffer)];
        for (files) |file| {
            if (std.Io.Dir.path.dirname(file)) |parent| try fixture.tmp.dir.createDirPath(testing.io, parent);
            try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = file, .data = "" });
        }
    }

    fn deinit(fixture: *Fixture) void {
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    /// The files `pattern` (relative to the fixture root) picks, relative again, joined by spaces.
    fn expandRelative(fixture: *Fixture, pattern: []const u8, exclude: []const []const u8) ![]const u8 {
        const allocator = fixture.arena.allocator();
        const absolute_exclude = try allocator.alloc([]const u8, exclude.len);
        for (exclude, absolute_exclude) |relative, *absolute| absolute.* = try std.Io.Dir.path.join(allocator, &.{ fixture.root, relative });
        var failure: Failure = .{};
        const found = try expand(allocator, testing.io, try std.Io.Dir.path.join(allocator, &.{ fixture.root, pattern }), absolute_exclude, &failure);
        var names: std.ArrayList(u8) = .empty;
        for (found, 0..) |file, index| {
            if (index != 0) try names.append(allocator, ' ');
            try names.appendSlice(allocator, file.path[fixture.root.len + 1 ..]);
        }
        return names.items;
    }
};

test "expand matches * in one directory and ** across any depth, sorted" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ "hypr/b.lua", "hypr/a.lua", "hypr/a.conf", "hypr/deco/blur.lua", "hypr/deco/deep/x.lua", "hypr/.git/hook.lua" });
    defer fixture.deinit();
    try testing.expectEqualStrings("hypr/a.lua hypr/b.lua", try fixture.expandRelative("hypr/*.lua", &.{}));
    try testing.expectEqualStrings("hypr/a.lua hypr/b.lua hypr/deco/blur.lua hypr/deco/deep/x.lua", try fixture.expandRelative("hypr/**/*.lua", &.{}));
    try testing.expectEqualStrings("hypr/a.conf hypr/a.lua hypr/b.lua hypr/deco/blur.lua hypr/deco/deep/x.lua", try fixture.expandRelative("hypr/**", &.{}));
    try testing.expectEqualStrings("hypr/.git/hook.lua", try fixture.expandRelative("hypr/.git/*.lua", &.{}));
    try testing.expectEqualStrings("hypr/deco/blur.lua", try fixture.expandRelative("hypr/*/blur.lua", &.{}));
}

test "expand leaves out excluded files, and a missing literal path matches nothing" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ "hypr/a.lua", "hypr/old/a.lua", "hypr/old/deep/b.lua", "hypr/gamemode.lua" });
    defer fixture.deinit();
    try testing.expectEqualStrings("hypr/a.lua", try fixture.expandRelative("hypr/**/*.lua", &.{ "hypr/old/**", "hypr/game*.lua" }));
    try testing.expectEqualStrings("hypr/a.lua", try fixture.expandRelative("hypr/a.lua", &.{}));
    try testing.expectEqualStrings("", try fixture.expandRelative("hypr/missing.lua", &.{}));
    try testing.expectEqualStrings("", try fixture.expandRelative("nowhere/**/*.lua", &.{}));
    try testing.expectEqualStrings("", try fixture.expandRelative("hypr", &.{}));
}

test "expand follows symlinks, counts a file once and survives a loop" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ "ktisis/hypr/a.lua", "ktisis/hypr/deco/b.lua" });
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "config");
    try fixture.tmp.dir.symLink(testing.io, "../ktisis/hypr", "config/hypr", .{ .is_directory = true });
    try fixture.tmp.dir.symLink(testing.io, "a.lua", "ktisis/hypr/link.lua", .{});
    try fixture.tmp.dir.symLink(testing.io, "..", "ktisis/hypr/deco/loop", .{ .is_directory = true });
    try testing.expectEqualStrings("config/hypr/a.lua config/hypr/deco/b.lua", try fixture.expandRelative("config/hypr/**/*.lua", &.{}));
}
