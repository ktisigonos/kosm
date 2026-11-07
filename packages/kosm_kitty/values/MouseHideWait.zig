//! When the mouse pointer hides, and what brings it back.

const MouseHideWait = @This();

const std = @import("std");
const Joined = @import("../Joined.zig");

/// Seconds of inactivity before hiding; 0 never hides, negative hides on typing.
seconds: f64,
/// Seconds of mouse activity to wait before unhiding; null: unhide at once, and the
/// two fields below are not written.
unhide_wait: ?f64 = null,
/// Mouse events per second needed to unhide while `unhide_wait` runs.
unhide_threshold: u32 = 40,
/// Whether scrolling unhides the pointer.
scroll_unhide: bool = true,

/// Writes the value the way kitty.conf spells it, numbers and booleans in the file's format.
pub fn write(wait: MouseHideWait, joined: *Joined) Joined.Error!void {
    try joined.float(wait.seconds);
    if (wait.unhide_wait) |unhide_wait| {
        try joined.writer().writeByte(' ');
        try joined.float(unhide_wait);
        try joined.writer().print(" {d} ", .{wait.unhide_threshold});
        try joined.boolean(wait.scroll_unhide);
    }
}
