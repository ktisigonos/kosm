//! Deltas added to a color in naive CMYK, converted from and back to OKLCH (D68).
//! Absolute and not clamped: ink past 0..1 is kept, and clips only when printed as bytes (D48).

const Cmyk = @This();

const Color = @import("../Color.zig");

/// Added to cyan ink, 0..1 within sRGB.
cyan: f64 = 0,
/// Added to magenta ink, 0..1 within sRGB.
magenta: f64 = 0,
/// Added to yellow ink, 0..1 within sRGB.
yellow: f64 = 0,
/// Added to black ink, 0..1 within sRGB. Positive darkens.
key: f64 = 0,

/// Applies the deltas to `color`, keeping its alpha.
pub fn apply(delta: Cmyk, color: Color) Color {
    var cmyk = Color.Cmyk.fromRgb(color.toRgb());
    cmyk.cyan += delta.cyan;
    cmyk.magenta += delta.magenta;
    cmyk.yellow += delta.yellow;
    cmyk.key += delta.key;
    return Color.fromRgb(cmyk.toRgb());
}
