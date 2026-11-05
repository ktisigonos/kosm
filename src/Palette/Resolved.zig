//! The palette modules see: every hue filled in, plus gray (D9).

const Resolved = @This();

const Color = @import("../Color.zig");
const Hue = @import("../Palette.zig").Hue;

black: Color,
white: Color,
/// Halfway between black and white (D8).
gray: Color,
red: Color,
orange: Color,
yellow: Color,
lime: Color,
green: Color,
teal: Color,
cyan: Color,
sky: Color,
blue: Color,
purple: Color,
magenta: Color,
pink: Color,

/// The color at a wheel position.
pub fn get(resolved: Resolved, hue: Hue) Color {
    return switch (hue) {
        inline else => |tag| @field(resolved, @tagName(tag)),
    };
}
