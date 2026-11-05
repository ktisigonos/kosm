//! How many cells the cursor must move before its trail starts.

const TrailThreshold = @This();

const std = @import("std");

/// Cells moved horizontally, or in both directions when `vertical` is null.
horizontal: u32,
/// Cells moved vertically; null: same as `horizontal`.
vertical: ?u32 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(threshold: TrailThreshold, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{threshold.horizontal});
    if (threshold.vertical) |vertical| try writer.print(" {d}", .{vertical});
}
