//! A custom contrast curve for compositing text glyphs.

const CompositionCurve = @This();

const Joined = @import("../Joined.zig");

/// Thickness of dark text on light backgrounds, 0.01 and up.
gamma: f64,
/// Extra contrast in percent, 0..100; null: kitty's platform default.
contrast: ?f64 = null,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(curve: CompositionCurve, joined: *Joined) Joined.Error!void {
    try joined.float(curve.gamma);
    if (curve.contrast) |contrast| {
        try joined.writer().writeByte(' ');
        try joined.float(contrast);
    }
}
