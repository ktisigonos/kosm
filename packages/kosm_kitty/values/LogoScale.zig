//! The window logo's size, in percent (0..100) of the window; 0 disables scaling.

const LogoScale = @This();

const Joined = @import("../Joined.zig");

/// Percent of the window's width, or of its shorter side when `height` is null.
width: f64,
/// Percent of the window's height; null: keep the logo's aspect ratio.
height: ?f64 = null,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(scale: LogoScale, joined: *Joined) Joined.Error!void {
    try joined.float(scale.width);
    if (scale.height) |height| {
        try joined.writer().writeByte(' ');
        try joined.float(height);
    }
}
