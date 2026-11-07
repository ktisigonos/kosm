//! Padding on the two sides of one axis, in points: left and right, or top and bottom.

const Padding = @This();

const std = @import("std");

/// Left (`window_padding_x`) or top (`window_padding_y`).
start: u32,
/// Right (`window_padding_x`) or bottom (`window_padding_y`).
end: u32,

/// The same padding on both sides.
pub fn all(points: u32) Padding {
    return .{ .start = points, .end = points };
}

/// Writes the value the way ghostty spells it (`10`, `2,4`).
pub fn format(padding: Padding, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (padding.start == padding.end) return writer.print("{d}", .{padding.start});
    try writer.print("{d},{d}", .{ padding.start, padding.end });
}
