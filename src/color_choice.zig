//! A kosmos parameter that is either a color or a palette hue.

const std = @import("std");
const Color = @import("Color.zig");
const Palette = @import("Palette.zig");

/// A color, or a hue name to look up in the kosmos' palette. Kosm parses it from a flag
/// (`--accent sky`, `--accent '#88c0d0'`) before the palette exists, so read it through `resolve`.
pub const ColorChoice = union(enum) {
    color: Color,
    hue: Palette.Hue,

    /// The chosen color, looking a hue up in `palette`.
    pub fn resolve(choice: ColorChoice, palette: Palette.Resolved) Color {
        return switch (choice) {
            .color => |color| color,
            .hue => |hue| palette.get(hue),
        };
    }

    /// Parses a hue name (`sky`) or any text `Color.parse` takes.
    pub fn parse(text: []const u8) Color.ParseError!ColorChoice {
        if (std.meta.stringToEnum(Palette.Hue, std.mem.trim(u8, text, " \t"))) |hue| return .{ .hue = hue };
        return .{ .color = try Color.parse(text) };
    }
};

test "a hue name resolves against the palette, a color stays itself" {
    const palette = (Palette{ .black = try Color.parseHex("000"), .white = try Color.parseHex("fff"), .sky = try Color.parseHex("88c0d0") }).resolve();
    const sky = try ColorChoice.parse("sky");
    try std.testing.expectEqualStrings("#88c0d0", sky.resolve(palette).hex().slice());
    const given = try ColorChoice.parse("rgb(255, 0, 0)");
    try std.testing.expectEqualStrings("#ff0000", given.resolve(palette).hex().slice());
    try std.testing.expectError(error.InvalidColor, ColorChoice.parse("skyy"));
}
