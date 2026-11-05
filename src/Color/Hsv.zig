//! A color in HSV (= HSB) over gamma-encoded sRGB. Channels are not clamped, so colors
//! outside sRGB survive the trip (D48).

const Hsv = @This();

const std = @import("std");
const Rgb = @import("Rgb.zig");
const hue_circle = @import("hue_circle.zig");

/// Hue in degrees, 0..360.
hue: f64,
/// 0 is gray, 1 is fully saturated within sRGB.
saturation: f64,
/// The largest sRGB channel: 0 is black, 1 is full brightness.
value: f64,
/// Opacity, 0..1.
alpha: f64 = 1,

/// Converts from sRGB. Saturation is 0 where it is undefined (a value of exactly 0).
pub fn fromRgb(rgb: Rgb) Hsv {
    const range = hue_circle.extremes(rgb);
    const spread = range.largest - range.smallest;
    return .{
        .hue = hue_circle.hue(rgb, range.largest, spread),
        .saturation = if (range.largest == 0) 0 else spread / range.largest,
        .value = range.largest,
        .alpha = rgb.alpha,
    };
}

/// Converts to sRGB without clipping.
pub fn toRgb(hsv: Hsv) Rgb {
    const spread = hsv.value * hsv.saturation;
    const smallest = hsv.value - spread;
    const channels = hue_circle.channels(hsv.hue, spread);
    return .{ .red = channels[0] + smallest, .green = channels[1] + smallest, .blue = channels[2] + smallest, .alpha = hsv.alpha };
}

const testing = std.testing;

fn expectRgb(expected: Rgb, actual: Rgb) !void {
    try testing.expectApproxEqAbs(expected.red, actual.red, 1e-12);
    try testing.expectApproxEqAbs(expected.green, actual.green, 1e-12);
    try testing.expectApproxEqAbs(expected.blue, actual.blue, 1e-12);
    try testing.expectEqual(expected.alpha, actual.alpha);
}

test "known HSV values" {
    const orange = fromRgb(.{ .red = 1, .green = 0.5, .blue = 0 });
    try testing.expectApproxEqAbs(30.0, orange.hue, 1e-12);
    try testing.expectEqual(1.0, orange.saturation);
    try testing.expectEqual(1.0, orange.value);
    const magenta_red = fromRgb(.{ .red = 1, .green = 0, .blue = 0.5 });
    try testing.expectApproxEqAbs(330.0, magenta_red.hue, 1e-12);
}

test "sRGB survives a round trip through HSV, in and out of gamut" {
    const samples = [_]Rgb{
        .{ .red = 0.2, .green = 0.4, .blue = 0.9 },
        .{ .red = 0.9, .green = 0.1, .blue = 0.3, .alpha = 0.5 },
        .{ .red = 0.5, .green = 0.9, .blue = 0.1 },
        .{ .red = 1.4, .green = 0.5, .blue = -0.2 },
        .{ .red = -0.1, .green = -0.3, .blue = -0.2 },
        .{ .red = 0, .green = 0, .blue = 0 },
        .{ .red = 1, .green = 1, .blue = 1 },
    };
    for (samples) |sample| try expectRgb(sample, fromRgb(sample).toRgb());
}

test "a gray has hue and saturation 0, and black keeps saturation defined" {
    const gray = fromRgb(.{ .red = 0.5, .green = 0.5, .blue = 0.5 });
    try testing.expectEqual(0.0, gray.hue);
    try testing.expectEqual(0.0, gray.saturation);
    const black = fromRgb(.{ .red = 0, .green = 0, .blue = 0 });
    try testing.expectEqual(0.0, black.saturation);
    try testing.expect(!std.math.isNan(black.toRgb().red));
}

test "hue wraps when converting back" {
    try expectRgb(.{ .red = 1, .green = 0, .blue = 0 }, (Hsv{ .hue = 360, .saturation = 1, .value = 1 }).toRgb());
    try expectRgb(.{ .red = 1, .green = 0.5, .blue = 0 }, (Hsv{ .hue = -330, .saturation = 1, .value = 1 }).toRgb());
}
