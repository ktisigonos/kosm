//! An entry in the global menubar (macOS).

const MenuMap = @This();

const std = @import("std");
const values = @import("../values.zig");

/// The menu path, one name per level: `&.{ "Actions", "Launch something" }`.
path: []const []const u8,
/// The action to run, as in a `map` line.
action: []const u8,

/// Writes the value the way kitty.conf spells it.
pub fn format(entry: MenuMap, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll("global \"");
    for (entry.path, 0..) |level, index| {
        if (index != 0) try writer.writeAll("::");
        try values.writeEscaped(writer, level);
    }
    try writer.print("\" {s}", .{entry.action});
}
