//! The window logo's size, in percent (0..100) of the window; 0 disables scaling.

const LogoScale = @This();

const std = @import("std");

/// Percent of the window's width, or of its shorter side when `height` is null.
width: f64,
/// Percent of the window's height; null: keep the logo's aspect ratio.
height: ?f64 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(scale: LogoScale, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{scale.width});
    if (scale.height) |height| try writer.print(" {d}", .{height});
}
