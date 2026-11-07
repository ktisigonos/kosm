//! Codepoints drawn from a named font (`font-codepoint-map`).

const CodepointMap = @This();

const std = @import("std");
const CodepointRange = @import("CodepointRange.zig");

/// The codepoints to map.
codepoints: []const CodepointRange,
/// A font family name, as `font_family` takes it.
font: []const u8,

/// Writes the value the way ghostty spells it (`U+E0A0-U+E0A3,U+2665=Symbols Nerd Font`).
pub fn format(map: CodepointMap, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (map.codepoints, 0..) |range, index| {
        if (index != 0) try writer.writeByte(',');
        try range.format(writer);
    }
    try writer.print("={s}", .{map.font});
}
