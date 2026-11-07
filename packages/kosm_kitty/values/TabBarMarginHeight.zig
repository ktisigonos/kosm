//! The margins along the tab bar's edge, in points.

const TabBarMarginHeight = @This();

const Joined = @import("../Joined.zig");

/// Between the OS window's edge and the tab bar.
outer: f64,
/// Between the tab bar and the tab's contents.
inner: f64,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(margin: TabBarMarginHeight, joined: *Joined) Joined.Error!void {
    try joined.floats(&.{ margin.outer, margin.inner }, " ");
}
