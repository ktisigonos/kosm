//! One codepoint, or an inclusive range of them.

const CodepointRange = @This();

const std = @import("std");

/// The first codepoint.
first: u21,
/// The last codepoint; null: only `first`.
last: ?u21 = null,

/// Writes the value the way ghostty spells it (`U+E0A0-U+E0A3`).
pub fn format(range: CodepointRange, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("U+{X:0>4}", .{range.first});
    if (range.last) |last| try writer.print("-U+{X:0>4}", .{last});
}
