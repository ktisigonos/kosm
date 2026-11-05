//! A name standing for an action or kitten invocation.

const Alias = @This();

const std = @import("std");

/// The alias.
name: []const u8,
/// What it expands to.
action: []const u8,

/// Writes the value the way kitty.conf spells it.
pub fn format(alias: Alias, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{s} {s}", .{ alias.name, alias.action });
}
