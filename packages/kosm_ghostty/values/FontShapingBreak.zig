//! Where ghostty breaks text into separately shaped runs (`font-shaping-break`). Null flags keep ghostty's defaults.

const FontShapingBreak = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Break runs under the cursor, so ligatures split while editing. ghostty's default: on.
cursor: ?bool = null,

/// Writes the set flags the way ghostty spells them (`cursor,no-cursor`).
pub fn format(flags: FontShapingBreak, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
