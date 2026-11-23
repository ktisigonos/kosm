//! Whether text on a translucent window stays readable over an image: the window's background
//! is blended over the blurred image as a compositor does, in gamma-encoded sRGB.

const std = @import("std");
const Color = @import("../Color.zig");
const Plane = @import("Plane.zig");
const Surface = @import("Surface.zig");
const SurfaceOptions = @import("SurfaceOptions.zig");
const Window = @import("Window.zig");

/// The step the alphas are first tried in, from opaque down.
const coarse_step = 0.05;
/// Halvings of the last coarse step; 5 leave under 0.002.
const fine_steps = 5;
/// Alphas are rounded up to this, so small changes in the image do not churn configs.
const alpha_precision = 100;

/// The lowest alpha (0..1, rounded up to hundredths) at which the window's text stays readable
/// over the image: enough contrast, and little enough texture behind it, everywhere but
/// `options.worst_share` of the image. `pixels` (`width` per row) give its colors;
/// `lightness` is a larger copy's lightness, for its texture. 1 if only an opaque window is.
pub fn readableAlpha(allocator: std.mem.Allocator, pixels: []const Color, width: usize, lightness: Plane, window: Window, options: SurfaceOptions) std.mem.Allocator.Error!f64 {
    const contrast_alpha = try contrastAlpha(allocator, pixels, width, window, options);
    const texture_alpha = try textureAlpha(allocator, lightness, window, options);
    const alpha = @max(contrast_alpha, texture_alpha);
    return @max(0, @ceil(alpha * alpha_precision - 1e-9) / alpha_precision);
}

/// The lowest alpha at which the texture left behind the window is at most
/// `options.maximum_texture`; the window's alpha scales what shows through.
fn textureAlpha(allocator: std.mem.Allocator, lightness: Plane, window: Window, options: SurfaceOptions) std.mem.Allocator.Error!f64 {
    const blurred = try lightness.clone(allocator);
    defer allocator.free(blurred.values);
    try blurred.blur(allocator, window.blur * scaleOf(lightness.width, options));
    const behind = try Surface.worstTexture(allocator, blurred, options);
    if (behind <= options.maximum_texture) return 0;
    return std.math.clamp(1 - options.maximum_texture / behind, 0, 1);
}

fn scaleOf(width: usize, options: SurfaceOptions) f64 {
    return @as(f64, @floatFromInt(width)) / options.screen_width;
}

/// The image's gamma-encoded channels, blurred, and the window's colors, for blending.
const Backdrop = struct {
    channels: [3]Plane,
    background: [3]f32,
    foreground_luminance: f64,
    table: *const LinearTable,

    fn from(allocator: std.mem.Allocator, pixels: []const Color, width: usize, window: Window, options: SurfaceOptions, table: *const LinearTable) std.mem.Allocator.Error!Backdrop {
        var channels: [3]Plane = undefined;
        for (&channels) |*channel| channel.* = .{ .values = try allocator.alloc(f32, pixels.len), .width = width };
        for (pixels, 0..) |pixel, index| {
            const rgb = pixel.toRgb();
            channels[0].values[index] = clip(rgb.red);
            channels[1].values[index] = clip(rgb.green);
            channels[2].values[index] = clip(rgb.blue);
        }
        for (channels) |channel| try channel.blur(allocator, window.blur * scaleOf(width, options));
        const background = window.background.toRgb();
        return .{
            .channels = channels,
            .background = .{ clip(background.red), clip(background.green), clip(background.blue) },
            .foreground_luminance = window.foreground.luminance(),
            .table = table,
        };
    }

    fn free(backdrop: Backdrop, allocator: std.mem.Allocator) void {
        for (backdrop.channels) |channel| allocator.free(channel.values);
    }

    /// Whether at most `options.worst_share` of the image lacks the contrast at `alpha`.
    fn reads(backdrop: Backdrop, alpha: f64, options: SurfaceOptions) bool {
        const opacity: f32 = @floatCast(alpha);
        const count = backdrop.channels[0].values.len;
        const allowed = options.worst_share * @as(f64, @floatFromInt(count));
        var failing: f64 = 0;
        for (0..count) |index| {
            var luminance: f64 = 0;
            for (backdrop.channels, backdrop.background, luminance_weights) |channel, background, weight| {
                const blended = opacity * background + (1 - opacity) * channel.values[index];
                luminance += weight * backdrop.table.linear(blended);
            }
            const lighter = @max(luminance, backdrop.foreground_luminance);
            const darker = @min(luminance, backdrop.foreground_luminance);
            if ((lighter + 0.05) / (darker + 0.05) < options.minimum_contrast) failing += 1;
        }
        return failing <= allowed;
    }
};

/// WCAG 2's weights of linear red, green and blue in luminance.
const luminance_weights = [3]f64{ 0.2126, 0.7152, 0.0722 };

/// The lowest alpha at which the text keeps `options.minimum_contrast`, found from opaque
/// down, so an alpha passing below a failing one is not taken.
fn contrastAlpha(allocator: std.mem.Allocator, pixels: []const Color, width: usize, window: Window, options: SurfaceOptions) std.mem.Allocator.Error!f64 {
    const table: LinearTable = .init();
    const backdrop: Backdrop = try .from(allocator, pixels, width, window, options, &table);
    defer backdrop.free(allocator);
    if (!backdrop.reads(1, options)) return 1;
    var passing: f64 = 1;
    while (passing > 0) {
        const next = @max(0, passing - coarse_step);
        if (!backdrop.reads(next, options)) break;
        passing = next;
    } else return 0;
    var failing = @max(0, passing - coarse_step);
    for (0..fine_steps) |_| {
        const middle = (passing + failing) / 2;
        if (backdrop.reads(middle, options)) passing = middle else failing = middle;
    }
    return passing;
}

fn clip(channel: f64) f32 {
    return @floatCast(std.math.clamp(channel, 0, 1));
}

/// sRGB's gamma-encoded channel (0..1) to linear, from a table, for speed.
const LinearTable = struct {
    values: [size + 1]f32,

    const size = 1024;

    fn init() LinearTable {
        var table: LinearTable = undefined;
        for (&table.values, 0..) |*value, index| {
            const channel = @as(f64, @floatFromInt(index)) / size;
            value.* = @floatCast(if (channel <= 0.04045) channel / 12.92 else std.math.pow(f64, (channel + 0.055) / 1.055, 2.4));
        }
        return table;
    }

    fn linear(table: *const LinearTable, channel: f32) f64 {
        const position = std.math.clamp(channel, 0, 1) * size;
        const index: usize = @min(@as(usize, @intFromFloat(position)), size - 1);
        const fraction = position - @as(f32, @floatFromInt(index));
        return std.math.lerp(table.values[index], table.values[index + 1], fraction);
    }
};

const testing = std.testing;

fn gray(lightness: f64) Color {
    return .{ .lightness = lightness, .chroma = 0, .hue = 0 };
}

fn flatLightness(values: []f32, value: f32, width: usize) Plane {
    @memset(values, value);
    return .{ .values = values, .width = width };
}

const dark_window: Window = .{ .background = gray(0.15), .foreground = gray(0.95) };

test "a dark window over a dark, calm image needs no opacity" {
    const pixels: [64]Color = @splat(gray(0.2));
    var lightness: [256]f32 = undefined;
    const alpha = try readableAlpha(testing.allocator, &pixels, 8, flatLightness(&lightness, 0.2, 16), dark_window, .{ .screen_width = 16 });
    try testing.expectEqual(0, alpha);
}

test "a dark window over a bright image needs opacity, but less than opaque" {
    const pixels: [64]Color = @splat(gray(0.9));
    var lightness: [256]f32 = undefined;
    const alpha = try readableAlpha(testing.allocator, &pixels, 8, flatLightness(&lightness, 0.9, 16), dark_window, .{ .screen_width = 16 });
    try testing.expect(alpha > 0.3 and alpha < 1);
}

test "the contrast alpha is the lowest that reads, to within a hundredth" {
    const pixels: [64]Color = @splat(gray(0.9));
    const table: LinearTable = .init();
    const backdrop: Backdrop = try .from(testing.allocator, &pixels, 8, dark_window, .{}, &table);
    defer backdrop.free(testing.allocator);
    var lightness: [256]f32 = undefined;
    const alpha = try readableAlpha(testing.allocator, &pixels, 8, flatLightness(&lightness, 0.9, 16), dark_window, .{ .screen_width = 16 });
    try testing.expect(backdrop.reads(alpha, .{}));
    try testing.expect(!backdrop.reads(alpha - 0.02, .{}));
}

test "busy texture needs opacity, and blur takes it away" {
    const pixels: [64]Color = @splat(gray(0.2));
    var lightness: [64 * 64]f32 = undefined;
    for (&lightness, 0..) |*value, index| value.* = if ((index % 64 / 2 + index / 128) % 2 == 0) 0.1 else 0.3;
    const plane: Plane = .{ .values = &lightness, .width = 64 };
    const options: SurfaceOptions = .{ .screen_width = 64, .text_size = 8 };
    const sharp = try readableAlpha(testing.allocator, &pixels, 8, plane, dark_window, options);
    var blurred_window = dark_window;
    blurred_window.blur = 8;
    const blurred = try readableAlpha(testing.allocator, &pixels, 8, plane, blurred_window, options);
    try testing.expect(sharp > 0.5);
    try testing.expect(blurred < 0.1);
}

test "a window whose own colors lack contrast must be opaque" {
    const pixels: [64]Color = @splat(gray(0.5));
    var lightness: [256]f32 = undefined;
    const window: Window = .{ .background = gray(0.5), .foreground = gray(0.55) };
    try testing.expectEqual(1, try readableAlpha(testing.allocator, &pixels, 8, flatLightness(&lightness, 0.5, 16), window, .{ .screen_width = 16 }));
}

test "the linear table matches the sRGB curve" {
    const table: LinearTable = .init();
    try testing.expectApproxEqAbs(0, table.linear(0), 1e-6);
    try testing.expectApproxEqAbs(1, table.linear(1), 1e-6);
    try testing.expectApproxEqAbs(0.2140, table.linear(0.5), 1e-3);
}
