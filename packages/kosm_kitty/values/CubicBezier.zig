//! A CSS `cubic-bezier()` easing curve.

const CubicBezier = @This();

const std = @import("std");

/// The first control point.
x1: f64,
y1: f64,
/// The second control point.
x2: f64,
y2: f64,

/// Writes the value the way kitty.conf spells it.
pub fn format(curve: CubicBezier, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("cubic-bezier({d}, {d}, {d}, {d})", .{ curve.x1, curve.y1, curve.x2, curve.y2 });
}
