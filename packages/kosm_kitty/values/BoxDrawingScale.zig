//! Line widths for box drawing characters, in points.

const BoxDrawingScale = @This();

const Joined = @import("../Joined.zig");

/// Thin lines.
thin: f64,
/// Normal lines.
normal: f64,
/// Thick lines.
thick: f64,
/// Very thick lines.
very_thick: f64,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(scale: BoxDrawingScale, joined: *Joined) Joined.Error!void {
    try joined.floats(&.{ scale.thin, scale.normal, scale.thick, scale.very_thick }, ", ");
}
