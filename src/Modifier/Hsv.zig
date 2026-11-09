//! Deltas added to a color in HSV (= HSB), converted from and back to OKLCH.
//! Absolute and not clamped: a value past 1 is kept, and clips only when printed as bytes.

const Hsv = @This();

const Color = @import("../Color.zig");

/// Added to the hue, in degrees. The result wraps into 0..360.
hue: f64 = 0,
/// Added to saturation, 0..1 within sRGB. Ricer's `s+10` is `0.10`.
saturation: f64 = 0,
/// Added to value (brightness), 0..1 within sRGB. Ricer's `v+10` is `0.10`.
value: f64 = 0,

/// Applies the deltas to `color`, keeping its alpha.
pub fn apply(delta: Hsv, color: Color) Color {
    var hsv = Color.Hsv.fromRgb(color.toRgb());
    hsv.hue = Color.wrapHue(hsv.hue + delta.hue);
    hsv.saturation += delta.saturation;
    hsv.value += delta.value;
    return Color.fromRgb(hsv.toRgb());
}
