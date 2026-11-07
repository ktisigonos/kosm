//! The types Hyprland options take beyond numbers, booleans, strings and colors. Each one
//! writes itself through a `value` method, the way Hyprland's Lua config spells it, and may
//! refuse what Hyprland can't read through a `problem` method. Enums are written as their tag
//! name, or as their number when they declare `numbered`.

const std = @import("std");
const kosm = @import("kosm");

pub const Gradient = @import("values/Gradient.zig");
pub const Vec2 = @import("values/Vec2.zig");
pub const CssGap = @import("values/CssGap.zig");
pub const AccelCurve = @import("values/AccelCurve.zig");

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

/// A transform of input coordinates, like a monitor's: rotations counterclockwise in degrees,
/// then the same after flipping. Written as Hyprland's number.
pub const Transform = enum(i64) {
    normal = 0,
    rotate_90 = 1,
    rotate_180 = 2,
    rotate_270 = 3,
    flipped = 4,
    flipped_90 = 5,
    flipped_180 = 6,
    pub const numbered = true;
};

/// A built-in layout, or one a Lua config registers (`.{ .lua = "name" }`, written `lua:name`).
pub const Layout = union(enum) {
    dwindle,
    master,
    scrolling,
    monocle,
    lua: []const u8,

    /// The layout's name as Hyprland reads it.
    pub fn value(self: Layout, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
        return switch (self) {
            .lua => |name| .{ .string = try allocator.print("lua:{s}", .{name}) },
            else => .{ .string = @tagName(self) },
        };
    }
};

/// libinput's acceleration profiles; `custom` follows a curve of points.
pub const AccelProfile = union(enum) {
    adaptive,
    flat,
    custom: AccelCurve,

    /// `adaptive`, `flat`, or `custom <step> <points...>`.
    pub fn value(self: AccelProfile, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
        return switch (self) {
            .custom => |curve| .{ .string = try allocator.print("custom {f}", .{curve}) },
            else => .{ .string = @tagName(self) },
        };
    }
};
