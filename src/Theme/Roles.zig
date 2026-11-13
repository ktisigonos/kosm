//! The colors apps give meaning to, in libadwaita's names. An app reads these, never the
//! palette color one defaults to, so setting a role recolors every app.

const Roles = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const Palette = @import("../Palette.zig");
const Mode = @import("../Theme.zig").Mode;

/// Window and view backgrounds, opaque: apps give it the theme's `background_alpha` through
/// `Theme.asBackground`. Default: black, white in light mode.
background: Color,
/// Text and icons on the background. Default: white, black in light mode.
foreground: Color,
/// Selections, focus, active borders and suggested actions. Default: cyan.
accent: Color,
/// A second highlight beside the accent. Default: blue.
secondary: Color,
/// Links. Default: the accent.
link: Color,
/// Successful actions and states. Default: green.
success: Color,
/// Warnings and caution. Default: yellow.
warning: Color,
/// Errors and destructive actions. Default: red.
@"error": Color,

/// The roles a kosmos sets itself, each optional.
pub const Overrides = @import("Roles/Overrides.zig");

/// A role by name, for lists that pick roles: `&.{ .accent, .secondary }` is a constant, so it
/// stays valid wherever it is written.
pub const Name = enum { background, foreground, accent, secondary, link, success, warning, @"error" };

/// The color of the role `name`.
pub fn get(roles: Roles, name: Name) Color {
    return switch (name) {
        inline else => |tag| @field(roles, @tagName(tag)),
    };
}

/// Every role `overrides` leaves null from `palette`, background and foreground following
/// `mode`, and the link following the accent.
pub fn from(palette: Palette.Resolved, mode: Mode, overrides: Overrides) Roles {
    const accent = overrides.accent orelse palette.cyan;
    return .{
        .background = overrides.background orelse switch (mode) {
            .dark => palette.black,
            .light => palette.white,
        },
        .foreground = overrides.foreground orelse switch (mode) {
            .dark => palette.white,
            .light => palette.black,
        },
        .accent = accent,
        .secondary = overrides.secondary orelse palette.blue,
        .link = overrides.link orelse accent,
        .success = overrides.success orelse palette.green,
        .warning = overrides.warning orelse palette.yellow,
        .@"error" = overrides.@"error" orelse palette.red,
    };
}

test "every role has a name" {
    try std.testing.expectEqualDeep(
        std.meta.fieldNames(Roles),
        std.meta.fieldNames(Name),
    );
}

test "every role can be overridden" {
    try std.testing.expectEqualDeep(
        std.meta.fieldNames(Roles),
        std.meta.fieldNames(Overrides),
    );
}
