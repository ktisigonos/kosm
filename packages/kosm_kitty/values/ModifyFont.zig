//! A change to one font metric.

const ModifyFont = @This();

const Joined = @import("../Joined.zig");
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

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(modify_font: ModifyFont, joined: *Joined) Joined.Error!void {
    try joined.writer().print("{s} ", .{@tagName(modify_font.metric)});
    try modify_font.amount.write(joined);
}
