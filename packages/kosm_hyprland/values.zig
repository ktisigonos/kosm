//! The types Hyprland options take beyond numbers, booleans, strings and colors. Each one
//! writes itself through a `value` method, the way Hyprland's Lua config spells it.

const std = @import("std");
const kosm = @import("kosm");

pub const Gradient = @import("values/Gradient.zig");
pub const Vec2 = @import("values/Vec2.zig");
pub const CssGap = @import("values/CssGap.zig");

/// A font weight by name (`.{ .name = .bold }`) or as a number from 0 (`.{ .weight = 450 }`).
pub const FontWeight = union(enum) {
    name: Name,
    weight: u16,

    /// Hyprland's weight names, thinnest first.
    pub const Name = enum { thin, ultralight, light, semilight, book, normal, medium, semibold, bold, ultrabold, heavy, ultraheavy };

    /// The name as a string, or the weight as a number.
    pub fn value(self: FontWeight, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
        _ = allocator;
        return switch (self) {
            .name => |name| .{ .string = @tagName(name) },
            .weight => |weight| .{ .integer = weight },
        };
    }
};

/// Whether Hyprland draws the cursor in software (`cursor.no_hardware_cursors`).
pub const NoHardwareCursors = enum(i64) {
    disabled = 0,
    enabled = 1,
    auto = 2,

    /// The number, since Hyprland spells the names capitalized (`Disabled`).
    pub fn value(self: NoHardwareCursors, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
        _ = allocator;
        return .{ .integer = @backingInt(self) };
    }
};
