//! A width for each side of a window, in points.

const Edges = @This();

const Joined = @import("../Joined.zig");

top: f64,
right: f64,
bottom: f64,
left: f64,

/// The same width on every side.
pub fn all(width: f64) Edges {
    return .{ .top = width, .right = width, .bottom = width, .left = width };
}

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(edges: Edges, joined: *Joined) Joined.Error!void {
    const same = edges.top == edges.right and edges.top == edges.bottom and edges.top == edges.left;
    if (same) return joined.float(edges.top);
    try joined.floats(&.{ edges.top, edges.right, edges.bottom, edges.left }, " ");
}
