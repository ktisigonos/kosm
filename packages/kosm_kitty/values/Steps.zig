//! A CSS `steps()` easing function.

const Steps = @This();

const std = @import("std");

/// How many steps.
count: u32,
/// Where the jumps happen.
position: enum { start, end, none, both } = .end,

/// Writes the value the way kitty.conf spells it.
pub fn format(steps: Steps, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("steps({d}, {s})", .{ steps.count, @tagName(steps.position) });
}
