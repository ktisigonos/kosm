//! The roles a kosmos sets itself; every one left null takes its default from the palette.

const Color = @import("../../Color.zig");

/// Window and view backgrounds. null: black, white in light mode.
background: ?Color = null,
/// Text and icons on the background. null: white, black in light mode.
foreground: ?Color = null,
/// Selections, focus, active borders and suggested actions. null: cyan.
accent: ?Color = null,
/// A second highlight beside the accent. null: blue.
secondary: ?Color = null,
/// Links. null: the accent.
link: ?Color = null,
/// Successful actions and states. null: green.
success: ?Color = null,
/// Warnings and caution. null: yellow.
warning: ?Color = null,
/// Errors and destructive actions. null: red.
@"error": ?Color = null,
