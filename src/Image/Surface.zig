//! What an image is like as a desktop's backdrop: how busy it is behind text, and how soft its
//! edges are. Kosm's own base turns these into gaps, rounding and the like.

const Surface = @This();

const std = @import("std");
const Plane = @import("Plane.zig");
const SurfaceOptions = @import("SurfaceOptions.zig");

/// How busy the image is at the size of text, 0..1: 0 at and below
/// `SurfaceOptions.calm_texture`, 1 at and above `busy_texture`.
detail: f64,
/// How soft the image's edges are, 0..1: 1 for blurry, organic pictures, 0 for crisp,
/// straight-edged ones (`SurfaceOptions.soft_hardness` and `hard_hardness`).
softness: f64,
/// The texture `detail` is measured from: the standard deviation of lightness within a line of
/// text's height, averaged over the image.
texture: f64,
/// The edge hardness `softness` is measured from, 0..1: how much of the image's edge energy
/// is lost to a slight blur (crisp edges), times how much of it runs in straight lines.
hardness: f64,

/// The largest standard deviation lightness (0..1) can have.
const max_deviation = 0.5;
/// The blur, in image pixels, that tells crisp edges from soft ones: a crisp edge loses most
/// of its energy to it, a soft one little.
const edge_blur = 1.5;
/// The square, in image pixels around a pixel, whose edges count toward its direction.
const direction_radius = 2;

/// Measures `lightness`, a plane of the image's OKLCH lightness.
pub fn from(allocator: std.mem.Allocator, lightness: Plane, options: SurfaceOptions) std.mem.Allocator.Error!Surface {
    const texture_value = try meanTexture(allocator, lightness, options);
    const hardness_value = try hardnessOf(allocator, lightness);
    return .{
        .detail = rise(texture_value, options.calm_texture, options.busy_texture),
        .softness = 1 - rise(hardness_value, options.soft_hardness, options.hard_hardness),
        .texture = texture_value,
        .hardness = hardness_value,
    };
}

/// 0 at and below `low`, 1 at and above `high`, straight between.
fn rise(value: f64, low: f64, high: f64) f64 {
    if (high <= low) return if (value >= high) 1 else 0;
    return std.math.clamp((value - low) / (high - low), 0, 1);
}

/// The lightness texture `options.worst_share` of the plane is above, at the size of text.
pub fn worstTexture(allocator: std.mem.Allocator, lightness: Plane, options: SurfaceOptions) std.mem.Allocator.Error!f64 {
    const deviation = try lightness.localDeviation(allocator, textRadius(lightness, options));
    defer allocator.free(deviation.values);
    return Plane.upperValue(deviation.values, options.worst_share, max_deviation);
}

/// The plane's average texture at the size of text.
fn meanTexture(allocator: std.mem.Allocator, lightness: Plane, options: SurfaceOptions) std.mem.Allocator.Error!f64 {
    const deviation = try lightness.localDeviation(allocator, textRadius(lightness, options));
    defer allocator.free(deviation.values);
    var sum: f64 = 0;
    for (deviation.values) |value| sum += value;
    return sum / @as(f64, @floatFromInt(deviation.values.len));
}

/// Half a line of text's height, in the plane's pixels.
fn textRadius(plane: Plane, options: SurfaceOptions) usize {
    const scale = @as(f64, @floatFromInt(plane.width)) / options.screen_width;
    return @intFromFloat(@max(1, @round(options.text_size * scale / 2)));
}

/// Gradients of a plane: its change to the right and downward, 0 on the last column and row.
const Gradients = struct {
    right: Plane,
    down: Plane,

    fn from(allocator: std.mem.Allocator, plane: Plane) std.mem.Allocator.Error!Gradients {
        const right: Plane = .{ .values = try allocator.alloc(f32, plane.values.len), .width = plane.width };
        const down: Plane = .{ .values = try allocator.alloc(f32, plane.values.len), .width = plane.width };
        const rows = plane.height();
        for (0..rows) |row| for (0..plane.width) |column| {
            const index = row * plane.width + column;
            right.values[index] = if (column + 1 < plane.width) plane.values[index + 1] - plane.values[index] else 0;
            down.values[index] = if (row + 1 < rows) plane.values[index + plane.width] - plane.values[index] else 0;
        };
        return .{ .right = right, .down = down };
    }

    fn free(gradients: Gradients, allocator: std.mem.Allocator) void {
        allocator.free(gradients.right.values);
        allocator.free(gradients.down.values);
    }

    fn energy(gradients: Gradients) f64 {
        var sum: f64 = 0;
        for (gradients.right.values, gradients.down.values) |right, down| sum += right * right + down * down;
        return sum;
    }
};

/// How crisp and straight the plane's edges are, 0..1.
fn hardnessOf(allocator: std.mem.Allocator, lightness: Plane) std.mem.Allocator.Error!f64 {
    const gradients = try Gradients.from(allocator, lightness);
    defer gradients.free(allocator);
    const energy = gradients.energy();
    if (energy == 0) return 0;

    const blurred = try lightness.clone(allocator);
    defer allocator.free(blurred.values);
    try blurred.blur(allocator, edge_blur);
    const blurred_gradients = try Gradients.from(allocator, blurred);
    defer blurred_gradients.free(allocator);
    const crispness = std.math.clamp(1 - blurred_gradients.energy() / energy, 0, 1);
    return crispness * try straightness(allocator, gradients);
}

/// How much the edges near each pixel share one direction, 0..1 (the structure tensor's
/// coherence), averaged with each pixel weighted by its edge energy.
fn straightness(allocator: std.mem.Allocator, gradients: Gradients) std.mem.Allocator.Error!f64 {
    const width = gradients.right.width;
    const length = gradients.right.values.len;
    const tensor = [3]Plane{
        .{ .values = try allocator.alloc(f32, length), .width = width },
        .{ .values = try allocator.alloc(f32, length), .width = width },
        .{ .values = try allocator.alloc(f32, length), .width = width },
    };
    defer for (tensor) |plane| allocator.free(plane.values);
    for (gradients.right.values, gradients.down.values, 0..) |right, down, index| {
        tensor[0].values[index] = right * right;
        tensor[1].values[index] = down * down;
        tensor[2].values[index] = right * down;
    }
    const scratch = try allocator.alloc(f32, @max(width, gradients.right.height()));
    defer allocator.free(scratch);
    for (tensor) |plane| plane.boxBlur(scratch, direction_radius);

    var weighted: f64 = 0;
    var total: f64 = 0;
    for (tensor[0].values, tensor[1].values, tensor[2].values) |across, along, both| {
        const weight: f64 = across + along;
        if (weight <= 0) continue;
        const difference: f64 = across - along;
        const product: f64 = both;
        weighted += @sqrt(difference * difference + 4 * product * product);
        total += weight;
    }
    return if (total == 0) 0 else weighted / total;
}

const testing = std.testing;

fn planeOf(values: []f32, width: usize) Plane {
    return .{ .values = values, .width = width };
}

test "a flat image is calm and soft" {
    var values: [64 * 64]f32 = @splat(0.4);
    const surface = try from(testing.allocator, planeOf(&values, 64), .{ .screen_width = 64 });
    try testing.expectEqual(0, surface.detail);
    try testing.expectEqual(1, surface.softness);
}

test "noise is busy, a smooth gradient is calm" {
    var noise: [64 * 64]f32 = undefined;
    var random: std.Random.DefaultPrng = .init(7);
    for (&noise) |*value| value.* = random.random().float(f32);
    const busy = try from(testing.allocator, planeOf(&noise, 64), .{ .screen_width = 64 });
    try testing.expectEqual(1, busy.detail);

    var gradient: [64 * 64]f32 = undefined;
    for (&gradient, 0..) |*value, index| value.* = 0.3 + @as(f32, @floatFromInt(index % 64)) / 640;
    const calm = try from(testing.allocator, planeOf(&gradient, 64), .{ .screen_width = 64 });
    try testing.expectEqual(0, calm.detail);
    try testing.expect(calm.softness > 0.9);
}

test "hard straight stripes are hard, noise is less so, blurred stripes are softer still" {
    var stripes: [64 * 64]f32 = undefined;
    for (&stripes, 0..) |*value, index| value.* = if (index % 64 / 8 % 2 == 0) 0.2 else 0.8;
    const stripes_hardness = try hardnessOf(testing.allocator, planeOf(&stripes, 64));

    var noise: [64 * 64]f32 = undefined;
    var random: std.Random.DefaultPrng = .init(7);
    for (&noise) |*value| value.* = random.random().float(f32);
    const noise_hardness = try hardnessOf(testing.allocator, planeOf(&noise, 64));

    try planeOf(&stripes, 64).blur(testing.allocator, 4);
    const blurred_hardness = try hardnessOf(testing.allocator, planeOf(&stripes, 64));

    try testing.expect(stripes_hardness > 0.6);
    try testing.expect(noise_hardness < stripes_hardness);
    try testing.expect(blurred_hardness < 0.3);
}
