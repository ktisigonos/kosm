//! Line widths for box drawing characters, in points.

const BoxDrawingScale = @This();

const std = @import("std");

/// Thin lines.
thin: f64,
/// Normal lines.
normal: f64,
/// Thick lines.
thick: f64,
/// Very thick lines.
very_thick: f64,

/// Writes the value the way kitty.conf spells it.
pub fn format(scale: BoxDrawingScale, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}, {d}, {d}, {d}", .{ scale.thin, scale.normal, scale.thick, scale.very_thick });
}
