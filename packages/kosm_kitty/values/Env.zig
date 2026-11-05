//! An environment variable for child processes.

const Env = @This();

const std = @import("std");

/// The variable's name.
name: []const u8,
/// Its value, expanded by kitty; null: remove the variable.
value: ?[]const u8 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(env: Env, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(env.name);
    if (env.value) |value| try writer.print("={s}", .{value});
}
