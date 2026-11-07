//! A Hyprland gradient: up to 10 colors drawn at an angle. `.solid(color)` is one color;
//! `.from(&.{ a, b })` blends several.

const Gradient = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The colors in order; null slots are skipped. Set at least one: Hyprland refuses an empty
/// gradient.
colors: [max_colors]?kosm.Color = @splat(null),
/// The direction in degrees. null: Hyprland's default, 0.
angle: ?f64 = null,

/// The most colors Hyprland's shaders draw.
pub const max_colors = 10;

/// One color all around.
pub fn solid(color: kosm.Color) Gradient {
    var gradient: Gradient = .{};
    gradient.colors[0] = color;
    return gradient;
}

/// `colors` in order, at most `max_colors` of them.
pub fn from(colors: []const kosm.Color) Gradient {
    // More colors is a mistake in the kosmos itself, like an index out of bounds.
    if (colors.len > max_colors) @panic("a Hyprland gradient holds at most 10 colors");
    var gradient: Gradient = .{};
    for (colors, 0..) |color, index| gradient.colors[index] = color;
    return gradient;
}

/// Every set color with `modifier` applied, the angle kept.
pub fn modified(self: Gradient, modifier: kosm.Modifier) Gradient {
    var result = self;
    for (&result.colors) |*slot| {
        if (slot.*) |color| slot.* = modifier.apply(color);
    }
    return result;
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
