//! Codepoints drawn with a particular font.

const SymbolMap = @This();

const std = @import("std");
const CodepointRange = @import("CodepointRange.zig");

/// The codepoints to map.
codepoints: []const CodepointRange,
/// The font family drawing them.
font: []const u8,

/// Writes the value the way kitty.conf spells it.
pub fn format(map: SymbolMap, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try CodepointRange.writeList(map.codepoints, writer);
    try writer.print(" {s}", .{map.font});
}
