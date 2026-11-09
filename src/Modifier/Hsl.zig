//! Deltas added to a color in HSL, converted from and back to OKLCH.
//! Absolute and not clamped: a lightness past 1 is kept, and clips only when printed as bytes.

const Hsl = @This();

const Color = @import("../Color.zig");

/// Added to the hue, in degrees. The result wraps into 0..360.
hue: f64 = 0,
/// Added to saturation, 0..1 within sRGB.
saturation: f64 = 0,
/// Added to HSL lightness, 0..1 within sRGB.
lightness: f64 = 0,

/// Applies the deltas to `color`, keeping its alpha.
pub fn apply(delta: Hsl, color: Color) Color {
    var hsl = Color.Hsl.fromRgb(color.toRgb());
    hsl.hue = Color.wrapHue(hsl.hue + delta.hue);
    hsl.saturation += delta.saturation;
    hsl.lightness += delta.lightness;
    return Color.fromRgb(hsl.toRgb());
}
