//! A config project's `kosm.zon`: kosm's own settings, written by hand. The file is optional;
//! a missing one, or a missing field, takes the default.

const Settings = @This();

const std = @import("std");

/// The kosmoi `kosm build` builds when its command line names none.
build: Selection = .all,

/// Which kosmoi a command works on. A name means a kosmos file or group and every variant in
/// it ("frost", "frost.cold"), or one variant ("frost.iced"), as `kosm list` matches them.
pub const Selection = union(enum) {
    /// Every kosmos in `kosmoi/`, with its variants. Kosmoi that local apps and adapters or
    /// installed packages declare are left out.
    all,
    /// Only the named kosmoi, wherever they are declared.
    only: []const []const u8,
    /// Every kosmos in `kosmoi/` but the named ones.
    except: []const []const u8,
};

/// The file name in the config's root.
pub const file_name = "kosm.zon";

/// A settings file is a few lines; anything bigger is not one.
const max_size = 1024 * 1024;

pub const LoadError = error{ ParseZon, OutOfMemory } || std.Io.Dir.ReadFileAllocError;

/// Reads `path` into `arena`; a missing file gives the defaults. On `error.ParseZon`,
/// `diagnostics` says what is wrong with the file.
pub fn load(arena: std.mem.Allocator, io: std.Io, path: []const u8, diagnostics: *std.zon.parse.Diagnostics) LoadError!Settings {
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .limited(max_size), .of(u8), 0) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => |other| return other,
    };
    return std.zon.parse.fromSlice(Settings, .{ .gpa = arena, .arena = arena, .source = source, .diagnostics = diagnostics });
}

const testing = std.testing;

fn testParse(arena: std.mem.Allocator, source: [:0]const u8) !Settings {
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(Settings, .{ .gpa = arena, .arena = arena, .source = source, .diagnostics = &diagnostics });
}

test "build is all, only or except, and all when left out" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(.all, (try testParse(arena.allocator(), ".{}")).build);
    try testing.expectEqual(.all, (try testParse(arena.allocator(), ".{ .build = .all }")).build);
    const only = (try testParse(arena.allocator(), ".{ .build = .{ .only = .{ \"personal\", \"everforest\" } } }")).build.only;
    try testing.expectEqual(2, only.len);
    try testing.expectEqualStrings("everforest", only[1]);
    try testing.expectEqualStrings("personal.everforest", (try testParse(arena.allocator(), ".{ .build = .{ .except = .{\"personal.everforest\"} } }")).build.except[0]);
    try testing.expectError(error.ParseZon, testParse(arena.allocator(), ".{ .build = .some }"));
    try testing.expectError(error.ParseZon, testParse(arena.allocator(), ".{ .bild = .all }"));
}
