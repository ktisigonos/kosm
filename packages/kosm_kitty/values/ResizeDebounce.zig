//! How long to wait, in seconds, before redrawing during a live resize.

const ResizeDebounce = @This();

const Joined = @import("../Joined.zig");

/// The wait after resize events stop; the only one used outside macOS.
wait: f64,
/// The wait after a pause in a live resize, on macOS; null: kitty's default, 0.5.
wait_after_pause: ?f64 = null,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(debounce: ResizeDebounce, joined: *Joined) Joined.Error!void {
    try joined.float(debounce.wait);
    if (debounce.wait_after_pause) |wait| {
        try joined.writer().writeByte(' ');
        try joined.float(wait);
    }
}
