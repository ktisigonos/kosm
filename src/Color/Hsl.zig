//! A color in HSL over gamma-encoded sRGB, as CSS `hsl()` uses it. Channels are not clamped,
//! so colors outside sRGB survive the trip.

const Hsl = @This();

const std = @import("std");
const Rgb = @import("Rgb.zig");
const hue_circle = @import("hue_circle.zig");

/// Hue in degrees, 0..360.
hue: f64,
/// 0 is gray, 1 is fully saturated within sRGB.
saturation: f64,
/// The midpoint of the largest and smallest sRGB channel: 0 is black, 1 is white.
lightness: f64,
/// Opacity, 0..1.
alpha: f64 = 1,

/// Converts from sRGB. Saturation is 0 where it is undefined (a lightness of exactly 0 or 1
/// with differing channels, only possible outside sRGB).
pub fn fromRgb(rgb: Rgb) Hsl {
    const range = hue_circle.extremes(rgb);
    const spread = range.largest - range.smallest;
    const lightness = (range.largest + range.smallest) / 2;
    const room = 1 - @abs(2 * lightness - 1);
    return .{
        .hue = hue_circle.hue(rgb, range.largest, spread),
        .saturation = if (room == 0) 0 else spread / room,
        .lightness = lightness,
        .alpha = rgb.alpha,
    };
}

/// Converts to sRGB without clipping.
pub fn toRgb(hsl: Hsl) Rgb {
    const spread = (1 - @abs(2 * hsl.lightness - 1)) * hsl.saturation;
    const smallest = hsl.lightness - spread / 2;
    const channels = hue_circle.channels(hsl.hue, spread);
    return .{ .red = channels[0] + smallest, .green = channels[1] + smallest, .blue = channels[2] + smallest, .alpha = hsl.alpha };
}

const testing = std.testing;

fn expectRgb(expected: Rgb, actual: Rgb) !void {
    try testing.expectApproxEqAbs(expected.red, actual.red, 1e-12);
    try testing.expectApproxEqAbs(expected.green, actual.green, 1e-12);
    try testing.expectApproxEqAbs(expected.blue, actual.blue, 1e-12);
    try testing.expectEqual(expected.alpha, actual.alpha);
}

test "known HSL values" {
    const teal = fromRgb(.{ .red = 0, .green = 0.5, .blue = 0.5 });
    try testing.expectApproxEqAbs(180.0, teal.hue, 1e-12);
    try testing.expectApproxEqAbs(1.0, teal.saturation, 1e-12);
    try testing.expectApproxEqAbs(0.25, teal.lightness, 1e-12);
}

test "sRGB survives a round trip through HSL, in and out of gamut" {
    const samples = [_]Rgb{
        .{ .red = 0.2, .green = 0.4, .blue = 0.9 },
        .{ .red = 0.9, .green = 0.1, .blue = 0.3, .alpha = 0.5 },
        .{ .red = 0.95, .green = 0.9, .blue = 0.99 },
        .{ .red = 1.4, .green = 0.5, .blue = -0.2 },
        .{ .red = 1.6, .green = 1.2, .blue = 1.3 },
        .{ .red = 0, .green = 0, .blue = 0 },
        .{ .red = 1, .green = 1, .blue = 1 },
    };
    for (samples) |sample| try expectRgb(sample, fromRgb(sample).toRgb());
}

test "a gray has hue and saturation 0, and an undefined saturation is 0, not NaN" {
    const gray = fromRgb(.{ .red = 0.3, .green = 0.3, .blue = 0.3 });
    try testing.expectEqual(0.0, gray.hue);
    try testing.expectEqual(0.0, gray.saturation);
    const edge = fromRgb(.{ .red = 1.2, .green = 1, .blue = 0.8 });
    try testing.expectEqual(1.0, edge.lightness);
    try testing.expectEqual(0.0, edge.saturation);
}
