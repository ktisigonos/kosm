//! How long to wait, in seconds, before redrawing during a live resize.

const ResizeDebounce = @This();

const std = @import("std");

/// The wait after resize events stop; the only one used outside macOS.
wait: f64,
/// The wait after a pause in a live resize, on macOS; null: kitty's default, 0.5.
wait_after_pause: ?f64 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(debounce: ResizeDebounce, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{debounce.wait});
    if (debounce.wait_after_pause) |wait| try writer.print(" {d}", .{wait});
}
