//! A libinput acceleration curve: the points of the curve, `step` apart in input speed.

const AccelCurve = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The distance between points, in input speed.
step: f64,
/// The curve's output at 0, `step`, `2 * step`, ...
points: []const f64,

/// `<step> <points...>`, as Hyprland reads it.
pub fn format(self: AccelCurve, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{self.step});
    for (self.points) |point| try writer.print(" {d}", .{point});
}

/// The curve as text, as `scroll_points` takes it.
pub fn value(self: AccelCurve, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
    return .{ .string = try allocator.print("{f}", .{self}) };
}
