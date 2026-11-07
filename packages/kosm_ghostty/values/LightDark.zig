//! One theme for light mode and one for dark, picked by the desktop's theme.

const LightDark = @This();

const std = @import("std");

/// The theme in light mode, by name or absolute path.
light: []const u8,
/// The theme in dark mode, by name or absolute path.
dark: []const u8,

/// Writes the value the way ghostty spells it (`light:Rose Pine Dawn,dark:Rose Pine`).
pub fn format(themes: LightDark, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("light:{s},dark:{s}", .{ themes.light, themes.dark });
}
