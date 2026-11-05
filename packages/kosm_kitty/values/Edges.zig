//! A width for each side of a window, in points.

const Edges = @This();

const std = @import("std");

top: f64,
right: f64,
bottom: f64,
left: f64,

/// The same width on every side.
pub fn all(width: f64) Edges {
    return .{ .top = width, .right = width, .bottom = width, .left = width };
}

/// Writes the value the way kitty.conf spells it.
pub fn format(edges: Edges, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const same = edges.top == edges.right and edges.top == edges.bottom and edges.top == edges.left;
    if (same) return writer.print("{d}", .{edges.top});
    try writer.print("{d} {d} {d} {d}", .{ edges.top, edges.right, edges.bottom, edges.left });
}
