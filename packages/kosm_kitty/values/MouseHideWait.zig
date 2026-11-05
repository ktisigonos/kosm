//! When the mouse pointer hides, and what brings it back.

const MouseHideWait = @This();

const std = @import("std");

/// Seconds of inactivity before hiding; 0 never hides, negative hides on typing.
seconds: f64,
/// Seconds of mouse activity to wait before unhiding; null: unhide at once, and the
/// two fields below are not written.
unhide_wait: ?f64 = null,
/// Mouse events per second needed to unhide while `unhide_wait` runs.
unhide_threshold: u32 = 40,
/// Whether scrolling unhides the pointer.
scroll_unhide: bool = true,

/// Writes the value the way kitty.conf spells it.
pub fn format(wait: MouseHideWait, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{wait.seconds});
    if (wait.unhide_wait) |unhide_wait| {
        try writer.print(" {d} {d} {s}", .{ unhide_wait, wait.unhide_threshold, if (wait.scroll_unhide) "yes" else "no" });
    }
}
