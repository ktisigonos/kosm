//! When the terminal scrolls to the bottom (`scroll-to-bottom`). Null flags keep ghostty's defaults.

const ScrollToBottom = @This();

const std = @import("std");
const values = @import("../values.zig");

/// On a keystroke that sends input. ghostty's default: on.
keystroke: ?bool = null,
/// When new output arrives. ghostty's default: off.
output: ?bool = null,

/// Writes the set flags the way ghostty spells them (`keystroke,no-output`).
pub fn format(flags: ScrollToBottom, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
