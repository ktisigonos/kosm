//! An environment variable for commands ghostty starts.

const Env = @This();

const std = @import("std");

/// The variable's name.
name: []const u8,
/// Its value; empty removes the variable.
value: []const u8 = "",

/// Writes the value the way ghostty spells it (`EDITOR=nvim`).
pub fn format(env: Env, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{s}={s}", .{ env.name, env.value });
}
