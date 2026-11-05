//! A change to one font metric.

const ModifyFont = @This();

const std = @import("std");
const values = @import("../values.zig");

/// The metric to change.
metric: enum {
    underline_position,
    underline_thickness,
    strikethrough_position,
    strikethrough_thickness,
    cell_width,
    cell_height,
    baseline,

    pub const underscored = true;
},
/// How much to change it.
amount: values.FontAmount,

/// Writes the value the way kitty.conf spells it.
pub fn format(modify_font: ModifyFont, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{s} {f}", .{ @tagName(modify_font.metric), modify_font.amount });
}
