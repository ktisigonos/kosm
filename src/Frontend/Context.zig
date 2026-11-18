//! What a frontend's `load` gets besides the script's text.

const Context = @This();

const std = @import("std");
const Frontend = @import("../Frontend.zig");

/// Holds everything `load` allocates, for the whole run.
arena: std.mem.Allocator,
/// The script as messages show it: "kosmoi/personal.lua".
path: []const u8,
/// Why `load` failed, set by `fail`.
message: ?[]const u8 = null,

/// Where a value was written, for `Loose.origin` and messages: "kosmoi/personal.lua:12".
pub fn at(context: Context, line: usize) std.mem.Allocator.Error![]const u8 {
    return context.arena.print("{s}:{d}", .{ context.path, line });
}

/// Records why the script cannot be read and returns `error.InvalidScript`. Start the message
/// with `at(line)` when the line is known; otherwise kosm puts the script's path before it.
pub fn fail(context: *Context, comptime format: []const u8, arguments: anytype) Frontend.Error {
    context.message = try context.arena.print(format, arguments);
    return error.InvalidScript;
}
