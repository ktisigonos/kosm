//! The folders a path a kosmos loads (an image, a file) may start from, and how such a path
//! becomes absolute.

const Places = @This();

const std = @import("std");

/// What `~/` stands for: the home directory.
home: []const u8,
/// What `~~/` stands for: the config project kosm runs from.
config: []const u8,
/// What `~~kosmos/` stands for: the kosmos' own folder ("kosmoi/" for a kosmos file,
/// "kosmoi/nord/" for a kosmos folder). Relative paths a kosmos writes start here too.
kosmos: []const u8,

pub const Error = error{
    /// The path starts with `~` but not with `~/`, `~~/` or `~~kosmos/`.
    UnknownPlace,
} || std.mem.Allocator.Error;

/// What `UnknownPlace` means, for messages.
pub const unknown_place_message = "the path starts with ~ but names no folder kosm knows: use ~/ (home), ~~/ (the config) or ~~kosmos/ (the kosmos' folder)";

/// The prefixes `resolve` reads, longest first so `~~kosmos/` is not taken for `~~/`.
const Prefix = struct { text: []const u8, field: []const u8 };
const prefixes = [_]Prefix{
    .{ .text = "~~kosmos", .field = "kosmos" },
    .{ .text = "~~", .field = "config" },
    .{ .text = "~", .field = "home" },
};

/// `path` as an absolute path, allocated in `arena` unless it already is one.
pub fn resolve(places: Places, arena: std.mem.Allocator, path: []const u8) Error![]const u8 {
    if (std.Io.Dir.path.isAbsolute(path)) return path;
    inline for (prefixes) |prefix| {
        if (startsPlace(path, prefix.text)) {
            const rest = std.mem.trimStart(u8, path[prefix.text.len..], "/");
            return std.Io.Dir.path.join(arena, &.{ @field(places, prefix.field), rest });
        }
    }
    if (std.mem.startsWith(u8, path, "~")) return error.UnknownPlace;
    return std.Io.Dir.path.resolveAlloc(arena, &.{ places.kosmos, path });
}

/// Whether `path` is the place `prefix` names, or a path inside it.
fn startsPlace(path: []const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    return path.len == prefix.len or path[prefix.len] == '/';
}

/// `path` as given on the command line: relative paths become absolute against
/// `working_directory`, so they mean the same wherever the apply is repeated; every other path
/// is kept for `resolve`.
pub fn fromCommandLine(arena: std.mem.Allocator, working_directory: []const u8, path: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.startsWith(u8, path, "~") or std.Io.Dir.path.isAbsolute(path)) return path;
    return std.Io.Dir.path.resolveAlloc(arena, &.{ working_directory, path });
}

const testing = std.testing;

const test_places: Places = .{ .home = "/home/user", .config = "/home/user/.config/kosm", .kosmos = "/home/user/.config/kosm/kosmoi/nord" };

fn expectResolved(expected: []const u8, path: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings(expected, try test_places.resolve(arena.allocator(), path));
}

test "home, config and kosmos folders, absolute and relative paths resolve" {
    try expectResolved("/home/user/x.jxl", "~/x.jxl");
    try expectResolved("/home/user/.config/kosm/wallpapers/x.jxl", "~~/wallpapers/x.jxl");
    try expectResolved("/home/user/.config/kosm/kosmoi/nord/wallpapers/x.jxl", "~~kosmos/wallpapers/x.jxl");
    try expectResolved("/srv/x.jxl", "/srv/x.jxl");
    try expectResolved("/home/user/.config/kosm/kosmoi/nord/x.lua", "x.lua");
    try expectResolved("/home/user/.config/kosm/kosmoi/nord/x.lua", "./x.lua");
    try expectResolved("/home/user/.config/kosm/kosmoi/x.lua", "../x.lua");
}

test "a place alone names its folder" {
    try expectResolved("/home/user", "~");
    try expectResolved("/home/user/.config/kosm", "~~");
    try expectResolved("/home/user/.config/kosm/kosmoi/nord", "~~kosmos/");
}

test "an unknown place is an error, not a folder named after it" {
    try testing.expectError(error.UnknownPlace, test_places.resolve(testing.allocator, "~~kosmso/x.jxl"));
    try testing.expectError(error.UnknownPlace, test_places.resolve(testing.allocator, "~user/x.jxl"));
    try testing.expectError(error.UnknownPlace, test_places.resolve(testing.allocator, "~~kosmosx"));
}

test "a relative command-line path becomes absolute against the working directory, others are kept" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("/work/x.lua", try fromCommandLine(arena.allocator(), "/work/sub", "../x.lua"));
    try testing.expectEqualStrings("/work/sub/x.lua", try fromCommandLine(arena.allocator(), "/work/sub", "x.lua"));
    try testing.expectEqualStrings("~~kosmos/x.lua", try fromCommandLine(arena.allocator(), "/work", "~~kosmos/x.lua"));
    try testing.expectEqualStrings("/abs/x.lua", try fromCommandLine(arena.allocator(), "/work", "/abs/x.lua"));
}
