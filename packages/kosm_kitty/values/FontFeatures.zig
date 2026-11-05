//! OpenType features for one font face.

const FontFeatures = @This();

const std = @import("std");

/// The face, by PostScript name.
postscript_name: []const u8,
/// The features, such as `+zero` or `cv01=2`.
features: []const []const u8,

/// Writes the value the way kitty.conf spells it.
pub fn format(font_features: FontFeatures, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(font_features.postscript_name);
    for (font_features.features) |feature| try writer.print(" {s}", .{feature});
}
