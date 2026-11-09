//! Deltas added to a color's gamma-encoded sRGB channels, converted from and back to OKLCH.
//! Absolute and not clamped: a channel past 1 is kept, and clips only when printed as bytes.

const Rgb = @This();

const Color = @import("../Color.zig");

/// Added to red, 0..1 within sRGB (`0.1` is about 25 of 255).
red: f64 = 0,
/// Added to green, 0..1 within sRGB.
green: f64 = 0,
/// Added to blue, 0..1 within sRGB.
blue: f64 = 0,

/// Applies the deltas to `color`, keeping its alpha.
pub fn apply(delta: Rgb, color: Color) Color {
    var rgb = color.toRgb();
    rgb.red += delta.red;
    rgb.green += delta.green;
    rgb.blue += delta.blue;
    return Color.fromRgb(rgb);
}
