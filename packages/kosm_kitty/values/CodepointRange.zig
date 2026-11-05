//! One codepoint, or an inclusive range of them.

const CodepointRange = @This();

const std = @import("std");

/// The first codepoint.
first: u21,
/// The last codepoint; null: only `first`.
last: ?u21 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(range: CodepointRange, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("U+{X:0>4}", .{range.first});
    if (range.last) |last| try writer.print("-U+{X:0>4}", .{last});
}

/// Writes `ranges` comma-separated.
pub fn writeList(ranges: []const CodepointRange, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (ranges, 0..) |range, index| {
        if (index != 0) try writer.writeByte(',');
        try range.format(writer);
    }
}
