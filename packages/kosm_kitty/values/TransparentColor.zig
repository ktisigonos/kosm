//! A cell background color drawn see-through.

const TransparentColor = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The background color to match; written as `#rrggbb`, which is all kitty reads here.
color: kosm.Color,
/// Its opacity, 0..1; null: `background_opacity`.
opacity: ?f64 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(transparent: TransparentColor, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("#{s}", .{transparent.color.hex().slice()});
    if (transparent.opacity) |opacity| try writer.print("@{d}", .{opacity});
}
