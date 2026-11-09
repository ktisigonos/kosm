//! A color in naive CMYK over gamma-encoded sRGB (no print profile), as ricing tools use it.
//! Channels are not clamped, so colors outside sRGB survive the trip.

const Cmyk = @This();

const std = @import("std");
const Rgb = @import("Rgb.zig");
const hue_circle = @import("hue_circle.zig");

/// Cyan ink, 0..1 within sRGB.
cyan: f64,
/// Magenta ink, 0..1 within sRGB.
magenta: f64,
/// Yellow ink, 0..1 within sRGB.
yellow: f64,
/// Black ink: 0 is full brightness, 1 is black.
key: f64,
/// Opacity, 0..1.
alpha: f64 = 1,

/// Converts from sRGB. Black is key 1 with no other ink, since the inks are undefined there.
pub fn fromRgb(rgb: Rgb) Cmyk {
    const largest = hue_circle.extremes(rgb).largest;
    if (largest == 0) return .{ .cyan = 0, .magenta = 0, .yellow = 0, .key = 1, .alpha = rgb.alpha };
    return .{
        .cyan = (largest - rgb.red) / largest,
        .magenta = (largest - rgb.green) / largest,
        .yellow = (largest - rgb.blue) / largest,
        .key = 1 - largest,
        .alpha = rgb.alpha,
    };
}

/// Converts to sRGB without clipping.
pub fn toRgb(cmyk: Cmyk) Rgb {
    const brightness = 1 - cmyk.key;
    return .{
        .red = (1 - cmyk.cyan) * brightness,
        .green = (1 - cmyk.magenta) * brightness,
        .blue = (1 - cmyk.yellow) * brightness,
        .alpha = cmyk.alpha,
    };
}

const testing = std.testing;

fn expectRgb(expected: Rgb, actual: Rgb) !void {
    try testing.expectApproxEqAbs(expected.red, actual.red, 1e-12);
    try testing.expectApproxEqAbs(expected.green, actual.green, 1e-12);
    try testing.expectApproxEqAbs(expected.blue, actual.blue, 1e-12);
    try testing.expectEqual(expected.alpha, actual.alpha);
}

test "known CMYK values" {
    const olive = fromRgb(.{ .red = 0.5, .green = 0.5, .blue = 0 });
    try testing.expectApproxEqAbs(0.0, olive.cyan, 1e-12);
    try testing.expectApproxEqAbs(0.0, olive.magenta, 1e-12);
    try testing.expectApproxEqAbs(1.0, olive.yellow, 1e-12);
    try testing.expectApproxEqAbs(0.5, olive.key, 1e-12);
}

test "sRGB survives a round trip through CMYK, in and out of gamut" {
    const samples = [_]Rgb{
        .{ .red = 0.2, .green = 0.4, .blue = 0.9 },
        .{ .red = 0.9, .green = 0.1, .blue = 0.3, .alpha = 0.5 },
        .{ .red = 1.4, .green = 0.5, .blue = -0.2 },
        .{ .red = -0.1, .green = -0.3, .blue = -0.2 },
        .{ .red = 1, .green = 1, .blue = 1 },
    };
    for (samples) |sample| try expectRgb(sample, fromRgb(sample).toRgb());
}

test "black is key 1 with no other ink" {
    const black = fromRgb(.{ .red = 0, .green = 0, .blue = 0 });
    try testing.expectEqual(Cmyk{ .cyan = 0, .magenta = 0, .yellow = 0, .key = 1 }, black);
    try expectRgb(.{ .red = 0, .green = 0, .blue = 0 }, black.toRgb());
}
