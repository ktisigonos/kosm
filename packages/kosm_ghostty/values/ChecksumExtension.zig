//! How the DECRQCRA checksum is calculated (`vt-xt-checksum-extension`). Null flags keep ghostty's defaults.

const ChecksumExtension = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Report the negated sum. ghostty's default: on.
negate: ?bool = null,
/// Add cell attributes to each cell's value. ghostty's default: on.
attributes: ?bool = null,
/// Omit plain spaces after the first cell. ghostty's default: on.
trim: ?bool = null,
/// Count never-written cells as spaces. ghostty's default: off.
undrawn: ?bool = null,
/// Use full codepoints instead of DEC 8-bit values. ghostty's default: off.
full: ?bool = null,

/// Writes the set flags the way ghostty spells them (`negate,no-full`).
pub fn format(flags: ChecksumExtension, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
