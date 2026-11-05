//! A duration in seconds, optionally animated with easing functions.

const Timing = @This();

const std = @import("std");
const values = @import("../values.zig");

/// The duration in seconds; what 0 and negative values mean depends on the option.
seconds: f64,
/// The easing of the animation, or of its first half; null: not animated.
easing: ?values.Easing = null,
/// The easing of the animation's second half; null: same as `easing`.
second_easing: ?values.Easing = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(timing: Timing, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{timing.seconds});
    if (timing.easing) |easing| try writer.print(" {f}", .{easing});
    if (timing.second_easing) |easing| try writer.print(" {f}", .{easing});
}
