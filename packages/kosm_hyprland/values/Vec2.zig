//! Two numbers, written `{ x, y }`.

const Vec2 = @This();

const std = @import("std");
const kosm = @import("kosm");

x: f64,
y: f64,

/// The list `{ x, y }`.
pub fn value(self: Vec2, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
    return .{ .list = try allocator.dupe(kosm.Value, &.{ .{ .float = self.x }, .{ .float = self.y } }) };
}
