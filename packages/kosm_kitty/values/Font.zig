//! A font face for `font_family` and its variants: a family, or a precise font specification.

const Font = @This();

const std = @import("std");
const Joined = @import("../Joined.zig");
const values = @import("../values.zig");

/// The font family name.
family: ?[]const u8 = null,
/// A style within `family`, or a named style of a variable font.
style: ?[]const u8 = null,
/// The exact face, by PostScript name.
postscript_name: ?[]const u8 = null,
/// The exact face, by full name.
full_name: ?[]const u8 = null,
/// The named variable font within a family.
variable_name: ?[]const u8 = null,
/// OpenType features, such as `+zero` or `cv01=2`.
features: []const []const u8 = &.{},
/// Values for the font's variable axes, such as `wght`.
axes: []const values.FontAxis = &.{},

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(font: Font, joined: *Joined) Joined.Error!void {
    const writer = joined.writer();
    var separator: []const u8 = "";
    inline for (.{ "family", "style", "postscript_name", "full_name", "variable_name" }) |key| {
        if (@field(font, key)) |text| {
            try writer.print("{s}{s}=", .{ separator, key });
            try values.writeQuoted(writer, text);
            separator = " ";
        }
    }
    if (font.features.len != 0) {
        try writer.print("{s}features=\"", .{separator});
        for (font.features, 0..) |feature, index| {
            if (index != 0) try writer.writeByte(' ');
            try writer.writeAll(feature);
        }
        try writer.writeByte('"');
        separator = " ";
    }
    for (font.axes) |axis| {
        try writer.print("{s}{s}=", .{ separator, axis.name });
        try joined.float(axis.value);
        separator = " ";
    }
}
