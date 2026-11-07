//! A CSS `cubic-bezier()` easing curve.

const CubicBezier = @This();

const Joined = @import("../Joined.zig");

/// The first control point.
x1: f64,
y1: f64,
/// The second control point.
x2: f64,
y2: f64,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(curve: CubicBezier, joined: *Joined) Joined.Error!void {
    try joined.writer().writeAll("cubic-bezier(");
    try joined.floats(&.{ curve.x1, curve.y1, curve.x2, curve.y2 }, ", ");
    try joined.writer().writeByte(')');
}
