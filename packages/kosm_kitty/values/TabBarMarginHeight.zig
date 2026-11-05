//! The margins along the tab bar's edge, in points.

const TabBarMarginHeight = @This();

const std = @import("std");

/// Between the OS window's edge and the tab bar.
outer: f64,
/// Between the tab bar and the tab's contents.
inner: f64,

/// Writes the value the way kitty.conf spells it.
pub fn format(margin: TabBarMarginHeight, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d} {d}", .{ margin.outer, margin.inner });
}
