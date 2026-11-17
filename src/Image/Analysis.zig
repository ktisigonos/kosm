//! What an image's pixels say about its colors: its darkest and lightest colors, its average
//! lightness, and for each wheel hue the image's most common color near it and its share.

const Analysis = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const Palette = @import("../Palette.zig");
const Options = @import("Options.zig");

/// The color `Options.black_percentile` of the pixels are darker than.
black: Color,
/// The color `Options.white_percentile` of the pixels are darker than.
white: Color,
/// The pixels' average OKLCH lightness, 0..1.
average_lightness: f64,
/// Per wheel position, the most common color among the pixels nearest it; null when under
/// `Options.minimum_share` of the pixels are.
hues: [hue_count]?Color,
/// Per wheel position, the share of all pixels nearest it, 0..1.
shares: [hue_count]f64,

const hue_count = @typeInfo(Palette.Hue).@"enum".field_names.len;

/// Lightness steps the black and white percentiles are read from.
const lightness_bins = 256;
/// A hue's pixels are binned by lightness and chroma, and its color is the fullest bin's mean,
/// so it is a color the image shows rather than a washed-out average of all of them.
const hue_lightness_bins = 10;
const hue_chroma_bins = 8;
/// Chroma at and above which pixels share the last chroma bin.
const hue_chroma_range = 0.32;

/// The sum of some pixels in OKLab, for their mean.
const Sum = struct {
    count: usize = 0,
    lightness: f64 = 0,
    green_red: f64 = 0,
    blue_yellow: f64 = 0,

    fn add(sum: *Sum, color: Color) void {
        const hue_radians = std.math.degreesToRadians(color.hue);
        sum.count += 1;
        sum.lightness += color.lightness;
        sum.green_red += color.chroma * @cos(hue_radians);
        sum.blue_yellow += color.chroma * @sin(hue_radians);
    }

    fn mean(sum: Sum) Color {
        const count: f64 = @floatFromInt(sum.count);
        const green_red = sum.green_red / count;
        const blue_yellow = sum.blue_yellow / count;
        const chroma = std.math.hypot(green_red, blue_yellow);
        const hue = if (chroma < 1e-9) 0 else Color.wrapHue(std.math.radiansToDegrees(std.math.atan2(blue_yellow, green_red)));
        return .{ .lightness = sum.lightness / count, .chroma = chroma, .hue = hue };
    }
};

/// Analyses `pixels`, which must not be empty. Alpha is ignored.
pub fn from(pixels: []const Color, options: Options) Analysis {
    std.debug.assert(pixels.len > 0);
    const references = referenceHues();
    var by_lightness: [lightness_bins]Sum = @splat(.{});
    var by_hue: [hue_count][hue_lightness_bins * hue_chroma_bins]Sum = @splat(@splat(.{}));
    var lightness_total: f64 = 0;
    for (pixels) |pixel| {
        lightness_total += pixel.lightness;
        by_lightness[bin(pixel.lightness, 1, lightness_bins)].add(pixel);
        if (pixel.chroma < options.minimum_chroma) continue;
        const lightness_bin = bin(pixel.lightness, 1, hue_lightness_bins);
        const chroma_bin = bin(pixel.chroma, hue_chroma_range, hue_chroma_bins);
        by_hue[nearestPosition(&references, pixel.hue)][lightness_bin * hue_chroma_bins + chroma_bin].add(pixel);
    }

    const pixel_count: f64 = @floatFromInt(pixels.len);
    var analysis: Analysis = .{
        .black = percentile(&by_lightness, pixels.len, options.black_percentile),
        .white = percentile(&by_lightness, pixels.len, options.white_percentile),
        .average_lightness = lightness_total / pixel_count,
        .hues = undefined,
        .shares = undefined,
    };
    for (&by_hue, &analysis.hues, &analysis.shares) |*bins, *hue, *share| {
        var count: usize = 0;
        var fullest: *const Sum = &bins[0];
        for (bins) |*candidate| {
            count += candidate.count;
            if (candidate.count > fullest.count) fullest = candidate;
        }
        share.* = @as(f64, @floatFromInt(count)) / pixel_count;
        hue.* = if (count > 0 and share.* >= options.minimum_share) fullest.mean() else null;
    }
    return analysis;
}

/// The OKLCH hue each wheel position stands for: that of the fully saturated sRGB color at its
/// position, so red is `#ff0000`'s hue and yellow `#ffff00`'s.
pub fn referenceHues() [hue_count]f64 {
    var hues: [hue_count]f64 = undefined;
    for (&hues, 0..) |*hue, position| {
        const saturated: Color.Hsv = .{ .hue = @as(f64, @floatFromInt(position)) * 30, .saturation = 1, .value = 1 };
        hue.* = Color.fromRgb(saturated.toRgb()).hue;
    }
    return hues;
}

/// The wheel position whose reference hue is nearest `hue` around the circle.
pub fn nearestPosition(references: *const [hue_count]f64, hue: f64) usize {
    var nearest: usize = 0;
    var nearest_distance: f64 = std.math.inf(f64);
    for (references, 0..) |reference, position| {
        const distance = hueDistance(reference, hue);
        if (distance < nearest_distance) {
            nearest = position;
            nearest_distance = distance;
        }
    }
    return nearest;
}

/// The unsigned shortest turn between two hues, 0..180 degrees.
pub fn hueDistance(first: f64, second: f64) f64 {
    const difference = Color.wrapHue(second - first);
    return @min(difference, 360 - difference);
}

fn bin(value: f64, range: f64, count: usize) usize {
    const scaled = std.math.clamp(value / range, 0, 1) * @as(f64, @floatFromInt(count));
    return @min(@as(usize, @intFromFloat(scaled)), count - 1);
}

/// The mean color of the lightness bin holding the pixel `fraction` of the way from darkest to
/// lightest.
fn percentile(bins: *const [lightness_bins]Sum, pixel_count: usize, fraction: f64) Color {
    const target: usize = @intFromFloat(@floor(std.math.clamp(fraction, 0, 1) * @as(f64, @floatFromInt(pixel_count - 1))));
    var seen: usize = 0;
    for (bins) |sum| {
        seen += sum.count;
        if (seen > target) return sum.mean();
    }
    unreachable; // The bins hold all pixel_count pixels, and target < pixel_count.
}

const testing = std.testing;

fn gray(lightness: f64) Color {
    return .{ .lightness = lightness, .chroma = 0, .hue = 0 };
}

test "reference hues are those of the saturated sRGB colors" {
    const references = referenceHues();
    try testing.expectApproxEqAbs((try Color.parseHex("ff0000")).hue, references[0], 1e-9);
    try testing.expectApproxEqAbs((try Color.parseHex("0000ff")).hue, references[8], 1e-9);
}

test "one stray dark pixel does not decide black" {
    var pixels: [1000]Color = @splat(gray(0.4));
    pixels[0] = gray(0);
    for (pixels[500..]) |*pixel| pixel.* = gray(0.8);
    const analysis = from(&pixels, .{});
    try testing.expectApproxEqAbs(0.4, analysis.black.lightness, 1e-9);
    try testing.expectApproxEqAbs(0.8, analysis.white.lightness, 1e-9);
}

test "gray pixels set no hue" {
    var pixels: [100]Color = undefined;
    for (&pixels, 0..) |*pixel, index| pixel.* = .{ .lightness = @as(f64, @floatFromInt(index)) / 100, .chroma = 0.02, .hue = 140 };
    const analysis = from(&pixels, .{});
    for (analysis.hues) |hue| try testing.expectEqual(null, hue);
}

test "hues on both sides of 0 deg reach the position nearest them" {
    const references = referenceHues();
    const position = nearestPosition(&references, 0);
    try testing.expectEqual(position, nearestPosition(&references, 358));
    try testing.expectEqual(position, nearestPosition(&references, 2));
    try testing.expectEqual(position, nearestPosition(&references, references[position]));
    for (references, 0..) |reference, index| try testing.expectEqual(index, nearestPosition(&references, reference));
}

test "a hue under the minimum share is left out" {
    var pixels: [1000]Color = @splat(gray(0.5));
    const references = referenceHues();
    for (pixels[0..9]) |*pixel| pixel.* = .{ .lightness = 0.6, .chroma = 0.15, .hue = references[4] };
    for (pixels[9..29]) |*pixel| pixel.* = .{ .lightness = 0.6, .chroma = 0.15, .hue = references[8] };
    const analysis = from(&pixels, .{});
    try testing.expectEqual(null, analysis.hues[4]);
    try testing.expect(analysis.hues[8] != null);
    try testing.expectApproxEqAbs(0.02, analysis.shares[8], 1e-9);
}

test "a hue's most common color beats the average of its pixels" {
    var pixels: [100]Color = undefined;
    for (pixels[0..70]) |*pixel| pixel.* = .{ .lightness = 0.5, .chroma = 0.15, .hue = 140 };
    for (pixels[70..]) |*pixel| pixel.* = .{ .lightness = 0.9, .chroma = 0.05, .hue = 140 };
    const analysis = from(&pixels, .{});
    const references = referenceHues();
    const green = analysis.hues[nearestPosition(&references, 140)].?;
    try testing.expectApproxEqAbs(0.5, green.lightness, 1e-9);
    try testing.expectApproxEqAbs(0.15, green.chroma, 1e-9);
    try testing.expectApproxEqAbs(140, green.hue, 1e-9);
}
