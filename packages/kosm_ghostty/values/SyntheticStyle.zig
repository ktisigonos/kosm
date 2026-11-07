//! Which styles ghostty draws itself when the font lacks them (`font-synthetic-style`). Null flags keep ghostty's defaults.

const SyntheticStyle = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Synthesize bold. ghostty's default: on.
bold: ?bool = null,
/// Synthesize italic. ghostty's default: on.
italic: ?bool = null,
/// Synthesize bold italic; not turned off by `bold` or `italic`. ghostty's default: on.
bold_italic: ?bool = null,

/// Writes the set flags the way ghostty spells them (`bold,no-bold-italic`).
pub fn format(flags: SyntheticStyle, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
