//! One modifier acting as others.

const ModifierRemap = @This();

const std = @import("std");
const values = @import("../values.zig");

/// The modifier pressed.
from: values.Modifier,
/// The modifiers it acts as.
to: values.Modifiers,

/// Writes the value the way kitty.conf spells it.
pub fn format(remap: ModifierRemap, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{s}:{f}", .{ @tagName(remap.from), remap.to });
}
