//! The colors apps give meaning to, in libadwaita's names. An app reads these, never the
//! palette color one defaults to, so assigning a role recolors every app.

const Roles = @This();

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
/// Successful actions and states. Default: green.
success: Color,
/// Warnings and caution. Default: yellow.
warning: Color,
/// Errors and destructive actions. Default: red.
@"error": Color,

/// Every role's default from `palette`, background and foreground following `mode`.
pub fn from(palette: Palette.Resolved, mode: Mode) Roles {
    return .{
        .background = switch (mode) {
            .dark => palette.black,
            .light => palette.white,
        },
        .foreground = switch (mode) {
            .dark => palette.white,
            .light => palette.black,
        },
        .accent = palette.cyan,
        .secondary = palette.blue,
        .success = palette.green,
        .warning = palette.yellow,
        .@"error" = palette.red,
    };
}
