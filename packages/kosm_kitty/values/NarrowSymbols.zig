//! Codepoints restricted to a number of cells.

const NarrowSymbols = @This();

const std = @import("std");
const CodepointRange = @import("CodepointRange.zig");

/// The codepoints to restrict.
codepoints: []const CodepointRange,
/// How many cells they take; null: kitty's default, 1.
cells: ?u8 = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(symbols: NarrowSymbols, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try CodepointRange.writeList(symbols.codepoints, writer);
    if (symbols.cells) |cells| try writer.print(" {d}", .{cells});
}
