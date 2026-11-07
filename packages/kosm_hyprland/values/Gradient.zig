//! A Hyprland gradient: up to 10 colors drawn at an angle. `.solid(color)` is one color;
//! `.from(&.{ a, b })` blends several.

const Gradient = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The colors in order; null slots are skipped. Set at least one: Hyprland refuses an empty
/// gradient, and so does the apply.
colors: [max_colors]?kosm.Color = @splat(null),
/// The direction in degrees. null: Hyprland's default, 0.
angle: ?f64 = null,
/// How many colors `from` was given beyond `max_colors`; anything but 0 fails the apply.
extra_colors: usize = 0,

/// The most colors Hyprland's shaders draw.
pub const max_colors = 10;

/// One color all around.
pub fn solid(color: kosm.Color) Gradient {
    var gradient: Gradient = .{};
    gradient.colors[0] = color;
    return gradient;
}

/// `colors` in order. Past `max_colors`, the rest are counted in `extra_colors`.
pub fn from(colors: []const kosm.Color) Gradient {
    var gradient: Gradient = .{};
    const kept = @min(colors.len, max_colors);
    for (colors[0..kept], 0..) |color, index| gradient.colors[index] = color;
    gradient.extra_colors = colors.len - kept;
    return gradient;
}

/// Every set color with `modifier` applied, the rest kept.
pub fn modified(self: Gradient, modifier: kosm.Modifier) Gradient {
    var result = self;
    for (&result.colors) |*slot| {
        if (slot.*) |color| slot.* = modifier.apply(color);
    }
    return result;
}

/// Why Hyprland can't draw this gradient, if it can't.
pub fn problem(self: Gradient, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
    if (self.extra_colors != 0)
        return try allocator.print("the gradient holds {d} colors; Hyprland draws at most {d}", .{ max_colors + self.extra_colors, max_colors });
    for (self.colors) |slot| {
        if (slot != null) return null;
    }
    return "the gradient has no colors; set at least one";
}

/// A plain color when there is one and no angle, else `{ colors = { ... }, angle = ... }`.
pub fn value(self: Gradient, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
    var colors: std.ArrayList(kosm.Value) = .empty;
    for (self.colors) |slot| {
        if (slot) |color| try colors.append(allocator, .{ .color = color });
    }
    if (colors.items.len == 1 and self.angle == null) return colors.items[0];
    var entries: std.ArrayList(kosm.Value.Entry) = .empty;
    try entries.append(allocator, .{ .key = "colors", .value = .{ .list = colors.items } });
    if (self.angle) |angle| try entries.append(allocator, .{ .key = "angle", .value = .{ .float = angle } });
    return .{ .table = entries.items };
}
