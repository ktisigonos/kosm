//! A remote control password and what it may do.

const RemoteControlPassword = @This();

const std = @import("std");
const values = @import("../values.zig");

/// The password; it may not start with `-`.
password: []const u8,
/// The remote control actions it allows, such as `get-colors`; empty: kitty asks.
actions: []const []const u8 = &.{},

/// Writes the value the way kitty.conf spells it.
pub fn format(entry: RemoteControlPassword, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try values.writeQuoted(writer, entry.password);
    for (entry.actions) |action| try writer.print(" {s}", .{action});
}
