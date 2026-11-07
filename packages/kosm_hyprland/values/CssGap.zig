//! A gap in layout pixels per side, like CSS margins. `.all(5)` is the same on every side.

const CssGap = @This();

const std = @import("std");
const kosm = @import("kosm");

top: i64,
right: i64,
bottom: i64,
left: i64,

/// `size` on every side.
pub fn all(size: i64) CssGap {
    return .{ .top = size, .right = size, .bottom = size, .left = size };
}

/// One number when every side is the same, else `{ top = ..., right = ..., ... }`.
pub fn value(self: CssGap, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
    if (self.top == self.right and self.top == self.bottom and self.top == self.left) return .{ .integer = self.top };
    return .{ .table = try allocator.dupe(kosm.Value.Entry, &.{
        .{ .key = "top", .value = .{ .integer = self.top } },
        .{ .key = "right", .value = .{ .integer = self.right } },
        .{ .key = "bottom", .value = .{ .integer = self.bottom } },
        .{ .key = "left", .value = .{ .integer = self.left } },
    }) };
}
