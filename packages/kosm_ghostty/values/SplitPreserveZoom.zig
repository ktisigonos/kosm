//! When a zoomed split stays zoomed (`split-preserve-zoom`). Null flags keep ghostty's defaults.

const SplitPreserveZoom = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Moving to another split zooms that one instead of unzooming. ghostty's default: off.
navigation: ?bool = null,

/// Writes the set flags the way ghostty spells them (`navigation,no-navigation`).
pub fn format(flags: SplitPreserveZoom, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
