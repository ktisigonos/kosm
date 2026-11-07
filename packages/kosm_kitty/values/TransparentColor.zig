//! A cell background color drawn see-through.

const TransparentColor = @This();

const Joined = @import("../Joined.zig");
const kosm = @import("kosm");

/// The background color to match, written in the file's color format.
color: kosm.Color,
/// Its opacity, 0..1; null: `background_opacity`.
opacity: ?f64 = null,

/// Writes the value the way kitty.conf spells it, the color and opacity in the file's format.
pub fn write(transparent: TransparentColor, joined: *Joined) Joined.Error!void {
    try joined.color(transparent.color);
    if (transparent.opacity) |opacity| {
        try joined.writer().writeByte('@');
        try joined.float(opacity);
    }
}
