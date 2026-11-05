//! The hue circle HSV and HSL share: a hue from sRGB channels, and channels from a hue.

const std = @import("std");
const Color = @import("../Color.zig");
const Rgb = @import("Rgb.zig");

/// Below this spread between the largest and smallest channel, a color counts as gray.
/// Grays coming back from OKLCH differ in the 1e-16 range, which would give a random hue.
const gray_spread = 1e-9;

/// Hue in degrees 0..360 of `rgb`, whose largest channel is `largest` and whose largest
/// minus smallest is `spread`. A gray has hue 0, so saturating it gives red, as in colorsys.
pub fn hue(rgb: Rgb, largest: f64, spread: f64) f64 {
    if (spread < gray_spread) return 0;
    const sector = if (largest == rgb.red)
        (rgb.green - rgb.blue) / spread
    else if (largest == rgb.green)
        (rgb.blue - rgb.red) / spread + 2
    else
        (rgb.red - rgb.green) / spread + 4;
    return Color.wrapHue(sector * 60);
}

/// Red, green and blue with hue `degrees`, the smallest at 0 and the largest at `spread`.
pub fn channels(degrees: f64, spread: f64) [3]f64 {
    const sector = Color.wrapHue(degrees) / 60;
    const second = spread * (1 - @abs(@mod(sector, 2) - 1));
    return switch (@as(u3, @intFromFloat(@min(@floor(sector), 5)))) {
        0 => .{ spread, second, 0 },
        1 => .{ second, spread, 0 },
        2 => .{ 0, spread, second },
        3 => .{ 0, second, spread },
        4 => .{ second, 0, spread },
        else => .{ spread, 0, second },
    };
}

/// The largest and smallest of the three channels.
pub fn extremes(rgb: Rgb) struct { largest: f64, smallest: f64 } {
    return .{
        .largest = @max(rgb.red, rgb.green, rgb.blue),
        .smallest = @min(rgb.red, rgb.green, rgb.blue),
    };
}
