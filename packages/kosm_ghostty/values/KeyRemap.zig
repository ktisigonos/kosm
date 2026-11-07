//! One modifier key acting as another inside ghostty; one-way and not transitive.

const KeyRemap = @This();

const std = @import("std");

/// The key pressed.
from: Modifier,
/// The modifier it acts as.
to: Modifier,

/// A modifier, on either side or on one side only.
pub const Modifier = enum {
    shift,
    ctrl,
    alt,
    super,
    left_shift,
    left_ctrl,
    left_alt,
    left_super,
    right_shift,
    right_ctrl,
    right_alt,
    right_super,
};

/// Writes the value the way ghostty spells it (`ctrl=super`).
pub fn format(remap: KeyRemap, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{t}={t}", .{ remap.from, remap.to });
}
