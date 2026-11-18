//! The folders a path a kosmos loads (an image, a file) may start from, and how such a path
//! becomes absolute.

const Places = @This();

const std = @import("std");

/// What `~/` stands for: the home directory.
home: []const u8,
/// What `~~/` stands for: the config project kosm runs from.
config: []const u8,
/// What `~~kosmos/` stands for: the folder of the kosmos being applied ("kosmoi/" for a kosmos
/// file, "kosmoi/nord/" for a kosmos folder). Relative paths a kosmos writes start here too.
kosmos: []const u8,
/// What `~~<name>/` stands for: the folder of each package and local kosmos, app or adapter in
/// the config, by the name it is imported by.
folders: []const Folder = &.{},

/// A package's or local module's folder, which `~~<name>/` stands for.
pub const Folder = struct {
    /// The name the module is imported by: "kosm_krystallos", "nord".
    name: []const u8,
    /// The absolute path of the folder holding the module's root file.
    path: []const u8,
};

pub const Error = error{
    /// The path starts with `~` but names none of the folders kosm knows.
    UnknownPlace,
} || std.mem.Allocator.Error;

/// The name `~~kosmos/` takes, which no package or local module may have.
pub const kosmos_name = "kosmos";

/// `path` as an absolute path, allocated in `arena` unless it already is one.
pub fn resolve(places: Places, arena: std.mem.Allocator, path: []const u8) Error![]const u8 {
    if (std.Io.Dir.path.isAbsolute(path)) return path;
    if (!std.mem.startsWith(u8, path, "~")) return std.Io.Dir.path.resolveAlloc(arena, &.{ places.kosmos, path });
    const end = std.mem.findScalar(u8, path, '/') orelse path.len;
    const rest = std.mem.trimStart(u8, path[end..], "/");
    const folder = places.folderNamed(path[0..end]) orelse return error.UnknownPlace;
    return std.Io.Dir.path.join(arena, &.{ folder, rest });
}

/// The folder `place` stands for ("~", "~~", "~~kosmos", "~~nord"), or null.
fn folderNamed(places: Places, place: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, place, "~")) return places.home;
    if (!std.mem.startsWith(u8, place, "~~")) return null;
    const name = place[2..];
    if (name.len == 0) return places.config;
    if (std.mem.eql(u8, name, kosmos_name)) return places.kosmos;
    for (places.folders) |folder| {
        if (std.mem.eql(u8, folder.name, name)) return folder.path;
    }
    return null;
}

/// What `UnknownPlace` means for `path`, naming every folder a path may start from.
pub fn unknownPlaceMessage(places: Places, arena: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]const u8 {
    var message: std.Io.Writer.Allocating = .init(arena);
    const writer = &message.writer;
    writeUnknownPlace(writer, places, path) catch return error.OutOfMemory;
    return message.written();
}

fn writeUnknownPlace(writer: *std.Io.Writer, places: Places, path: []const u8) std.Io.Writer.Error!void {
    const end = std.mem.findScalar(u8, path, '/') orelse path.len;
    try writer.print("{s}/ names no folder kosm knows: use ~/ (home), ~~/ (the config), ~~kosmos/ (the applied kosmos' folder) or ~~<name>/ (a package's or local module's folder", .{path[0..end]});
    for (places.folders, 0..) |folder, index| try writer.print("{s}{s}", .{ if (index == 0) ": " else ", ", folder.name });
    try writer.writeAll(")");
}

/// `path` as given on the command line: relative paths become absolute against
/// `working_directory`, so they mean the same wherever the apply is repeated; every other path
/// is kept for `resolve`.
pub fn fromCommandLine(arena: std.mem.Allocator, working_directory: []const u8, path: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.startsWith(u8, path, "~") or std.Io.Dir.path.isAbsolute(path)) return path;
    return std.Io.Dir.path.resolveAlloc(arena, &.{ working_directory, path });
}

const testing = std.testing;

const test_places: Places = .{
    .home = "/home/user",
    .config = "/home/user/.config/kosm",
    .kosmos = "/home/user/.config/kosm/kosmoi/personal",
    .folders = &.{
        .{ .name = "kosm_krystallos", .path = "/cache/kosm_krystallos" },
        .{ .name = "nord", .path = "/home/user/.config/kosm/kosmoi/nord" },
    },
};

fn expectResolved(expected: []const u8, path: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings(expected, try test_places.resolve(arena.allocator(), path));
}

test "home, config, applied kosmos and named folders, absolute and relative paths resolve" {
    try expectResolved("/home/user/x.jxl", "~/x.jxl");
    try expectResolved("/home/user/.config/kosm/wallpapers/x.jxl", "~~/wallpapers/x.jxl");
    try expectResolved("/home/user/.config/kosm/kosmoi/personal/wallpapers/x.jxl", "~~kosmos/wallpapers/x.jxl");
    try expectResolved("/cache/kosm_krystallos/wallpapers/glass.jxl", "~~kosm_krystallos/wallpapers/glass.jxl");
    try expectResolved("/home/user/.config/kosm/kosmoi/nord/x.jxl", "~~nord/x.jxl");
    try expectResolved("/srv/x.jxl", "/srv/x.jxl");
    try expectResolved("/home/user/.config/kosm/kosmoi/personal/x.lua", "x.lua");
    try expectResolved("/home/user/.config/kosm/kosmoi/personal/x.lua", "./x.lua");
    try expectResolved("/home/user/.config/kosm/kosmoi/x.lua", "../x.lua");
}

test "a place alone names its folder" {
    try expectResolved("/home/user", "~");
    try expectResolved("/home/user/.config/kosm", "~~");
    try expectResolved("/home/user/.config/kosm/kosmoi/personal", "~~kosmos/");
    try expectResolved("/cache/kosm_krystallos", "~~kosm_krystallos");
}

test "an unknown place is an error naming the folders there are" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.UnknownPlace, test_places.resolve(arena.allocator(), "~~kosm_krystalos/x.jxl"));
    try testing.expectError(error.UnknownPlace, test_places.resolve(arena.allocator(), "~user/x.jxl"));
    try testing.expectError(error.UnknownPlace, test_places.resolve(arena.allocator(), "~~kosmosx"));
    try testing.expectEqualStrings(
        "~~kosm_krystalos/ names no folder kosm knows: use ~/ (home), ~~/ (the config), ~~kosmos/ (the applied kosmos' folder) or ~~<name>/ (a package's or local module's folder: kosm_krystallos, nord)",
        try test_places.unknownPlaceMessage(arena.allocator(), "~~kosm_krystalos/x.jxl"),
    );
}

test "a relative command-line path becomes absolute against the working directory, others are kept" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("/work/x.lua", try fromCommandLine(arena.allocator(), "/work/sub", "../x.lua"));
    try testing.expectEqualStrings("/work/sub/x.lua", try fromCommandLine(arena.allocator(), "/work/sub", "x.lua"));
    try testing.expectEqualStrings("~~kosmos/x.lua", try fromCommandLine(arena.allocator(), "/work", "~~kosmos/x.lua"));
    try testing.expectEqualStrings("/abs/x.lua", try fromCommandLine(arena.allocator(), "/work", "/abs/x.lua"));
}
