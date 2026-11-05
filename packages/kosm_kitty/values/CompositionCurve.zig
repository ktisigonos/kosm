//! A custom contrast curve for compositing text glyphs.

const CompositionCurve = @This();

const std = @import("std");

/// Thickness of dark text on light backgrounds, 0.01 and up.
gamma: f64,
/// Extra contrast in percent, 0..100; null: kitty's platform default.
contrast: ?f64 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(curve: CompositionCurve, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{curve.gamma});
    if (curve.contrast) |contrast| try writer.print(" {d}", .{contrast});
}
