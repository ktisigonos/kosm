//! The raw measurements an image's traits are mixed from, each in its own units: texture,
//! edges, flat areas, focus, highlights and colors.

const Measurements = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const Plane = @import("Plane.zig");
const ReadingOptions = @import("ReadingOptions.zig");
const Analysis = @import("Analysis.zig");
const Palette = @import("../Palette.zig");

/// The standard deviation of lightness within a line of text's height, averaged over the
/// image, 0..0.5.
texture: f64,
/// How much of the image's edge energy a slight blur takes away, 0..1: high for crisp edges.
crispness: f64,
/// How much the edges near each pixel share one direction, 0..1, weighted by edge energy.
straightness: f64,
/// The share of the image, 0..1, lying in large areas of almost one lightness.
flat_share: f64,
/// The share of the pixels, 0..1, falling into the few most common colors.
color_concentration: f64,
/// How abruptly the image's edges change, 0..1: an edge's steepness against the lightness it
/// spans nearby, weighted by its steepness; low out of focus. An image without edges gives 0.
edge_sharpness: f64,
/// How much lighter the brightest pixels are than the middle one, in lightness, 0..1.
highlight_lift: f64,
/// How light the surroundings of the brightest pixels stay, 0 (dark right away, as around
/// sharp text) to 1 (as light as them, as in a bloom).
halo: f64,
/// The brightest pixels' average chroma.
highlight_chroma: f64,
/// The color of the brightest pixels: the average of the colorful ones' most common hue, or
/// of all of them when none is colorful.
highlight_color: Color,
/// The pixels' average lightness, 0..1.
average_lightness: f64,
/// The lightness between the darkest and lightest few percent of the image, 0..1.
lightness_spread: f64,
/// The pixels' average chroma.
average_chroma: f64,
/// Which way the image's hues lean, weighted by chroma: 1 all toward orange, -1 all toward
/// its opposite, a sky blue, 0 balanced or gray.
warm_lean: f64,

const hue_count = @typeInfo(Palette.Hue).@"enum".field_names.len;

/// The largest standard deviation lightness (0..1) can have.
const max_deviation = 0.5;
/// The blur, in image pixels, that tells crisp edges from soft ones: a crisp edge loses most
/// of its energy to it, a soft one little.
const edge_blur = 1.5;
/// The square, in image pixels around a pixel, whose edges count toward its direction.
const direction_radius = 2;
/// The standard deviation of lightness within a line of text's height below which a pixel lies
/// in a flat area.
const flat_deviation = 0.01;
/// The square, in image pixels around an edge, whose lightness range its steepness is set
/// against, and the range below which there is no edge.
const sharpness_radius = 2;
const minimum_edge = 0.04;
/// The share of the image counted as its brightest pixels.
const highlight_share = 0.02;
/// The share of the image whose colorful pixels give the highlight color, and the chroma that
/// counts as colorful.
const highlight_color_share = 0.05;
const highlight_color_chroma = 0.04;
/// How far, in screen pixels, around the brightest pixels their surroundings reach.
const halo_radius = 12;
/// The lightness and the middle lightness's percentiles the spread runs between.
const spread_share = 0.05;
/// Colors are counted in OKLab cells this wide, and the concentration is the share of the
/// fullest few.
const color_cell = 0.05;
const color_cell_count = 4;
/// The hue warmth leans toward, in degrees: orange.
const warm_hue = 55;

/// Measures `pixels`, the image's colors, and `lightness`, a larger copy's lightness.
pub fn from(allocator: std.mem.Allocator, pixels: []const Color, lightness: Plane, options: ReadingOptions) std.mem.Allocator.Error!Measurements {
    std.debug.assert(pixels.len > 0);
    const gradients = try Gradients.from(allocator, lightness);
    defer gradients.free(allocator);
    const highlights = try Highlights.from(allocator, lightness, options);
    const colors = Colors.from(pixels);
    return .{
        .texture = try meanTexture(allocator, lightness, options),
        .crispness = try crispnessOf(allocator, lightness, gradients),
        .straightness = try straightnessOf(allocator, gradients),
        .flat_share = try flatShare(allocator, lightness, options),
        .color_concentration = try colorConcentration(allocator, pixels),
        .edge_sharpness = try edgeSharpness(allocator, lightness, gradients),
        .highlight_lift = highlights.lift,
        .halo = highlights.halo,
        .highlight_chroma = colors.highlight_chroma,
        .highlight_color = colors.highlight_color,
        .average_lightness = colors.average_lightness,
        .lightness_spread = highlights.spread,
        .average_chroma = colors.average_chroma,
        .warm_lean = colors.warm_lean,
    };
}

/// The plane's average texture at the size of text.
fn meanTexture(allocator: std.mem.Allocator, lightness: Plane, options: ReadingOptions) std.mem.Allocator.Error!f64 {
    const deviation = try lightness.localDeviation(allocator, options.textRadius(lightness.width));
    defer allocator.free(deviation.values);
    return mean(deviation.values);
}

/// The lightness texture `options.worst_share` of the plane is above, at the size of text.
pub fn worstTexture(allocator: std.mem.Allocator, lightness: Plane, options: ReadingOptions) std.mem.Allocator.Error!f64 {
    const deviation = try lightness.localDeviation(allocator, options.textRadius(lightness.width));
    defer allocator.free(deviation.values);
    return Plane.upperValue(deviation.values, options.worst_share, max_deviation);
}

fn mean(values: []const f32) f64 {
    var sum: f64 = 0;
    for (values) |value| sum += value;
    return sum / @as(f64, @floatFromInt(values.len));
}

fn flatShare(allocator: std.mem.Allocator, lightness: Plane, options: ReadingOptions) std.mem.Allocator.Error!f64 {
    const deviation = try lightness.localDeviation(allocator, options.textRadius(lightness.width));
    defer allocator.free(deviation.values);
    var flat: usize = 0;
    for (deviation.values) |value| {
        if (value < flat_deviation) flat += 1;
    }
    return @as(f64, @floatFromInt(flat)) / @as(f64, @floatFromInt(deviation.values.len));
}

fn colorConcentration(allocator: std.mem.Allocator, pixels: []const Color) std.mem.Allocator.Error!f64 {
    var counts: std.AutoHashMapUnmanaged([3]i32, usize) = .empty;
    defer counts.deinit(allocator);
    for (pixels) |pixel| {
        const hue = std.math.degreesToRadians(pixel.hue);
        const cell = [3]i32{
            @intFromFloat(@floor(pixel.lightness / color_cell)),
            @intFromFloat(@floor(pixel.chroma * @cos(hue) / color_cell)),
            @intFromFloat(@floor(pixel.chroma * @sin(hue) / color_cell)),
        };
        const entry = try counts.getOrPutValue(allocator, cell, 0);
        entry.value_ptr.* += 1;
    }
    var fullest: [color_cell_count]usize = @splat(0);
    var iterator = counts.valueIterator();
    while (iterator.next()) |count| {
        var carried = count.*;
        for (&fullest) |*slot| {
            if (carried > slot.*) std.mem.swap(usize, &carried, slot);
        }
    }
    var sum: usize = 0;
    for (fullest) |count| sum += count;
    return @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(pixels.len));
}

fn edgeSharpness(allocator: std.mem.Allocator, lightness: Plane, gradients: Gradients) std.mem.Allocator.Error!f64 {
    const highest = try lightness.clone(allocator);
    defer allocator.free(highest.values);
    const lowest = try lightness.clone(allocator);
    defer allocator.free(lowest.values);
    const scratch = try allocator.alloc(f32, @max(lightness.width, lightness.height()));
    defer allocator.free(scratch);
    highest.extremes(scratch, sharpness_radius, .highest);
    lowest.extremes(scratch, sharpness_radius, .lowest);
    var weighted: f64 = 0;
    var total: f64 = 0;
    for (gradients.right.values, gradients.down.values, highest.values, lowest.values) |right, down, high, low| {
        const range = high - low;
        if (range < minimum_edge) continue;
        const steepness: f64 = @sqrt(right * right + down * down);
        weighted += steepness * @min(1, steepness / range);
        total += steepness;
    }
    return if (total == 0) 0 else weighted / total;
}

/// The image's brightest pixels against the rest, from its lightness.
const Highlights = struct {
    lift: f64,
    halo: f64,
    spread: f64,

    fn from(allocator: std.mem.Allocator, lightness: Plane, options: ReadingOptions) std.mem.Allocator.Error!Highlights {
        // `upperValue` gives its bucket's top, which the bucket's own pixels are below.
        const threshold = Plane.upperValue(lightness.values, highlight_share, 1) - Plane.bucket_width;
        const middle = Plane.upperValue(lightness.values, 0.5, 1);
        const spread = Plane.upperValue(lightness.values, spread_share, 1) - Plane.upperValue(lightness.values, 1 - spread_share, 1);
        const lift = threshold - middle;
        return .{
            .lift = @max(0, lift),
            .halo = if (lift <= 0) 0 else try haloOf(allocator, lightness, threshold, middle, options),
            .spread = @max(0, spread),
        };
    }

    /// The average lightness near the pixels at and above `threshold`, from `middle` (0) to
    /// `threshold` (1).
    fn haloOf(allocator: std.mem.Allocator, lightness: Plane, threshold: f32, middle: f32, options: ReadingOptions) std.mem.Allocator.Error!f64 {
        const near: Plane = .{ .values = try allocator.alloc(f32, lightness.values.len), .width = lightness.width };
        defer allocator.free(near.values);
        for (near.values, lightness.values) |*mask, value| mask.* = if (value >= threshold) 1 else 0;
        const scratch = try allocator.alloc(f32, @max(near.width, near.height()));
        defer allocator.free(scratch);
        near.boxBlur(scratch, options.pixels(lightness.width, halo_radius));
        var sum: f64 = 0;
        var count: f64 = 0;
        for (near.values, lightness.values) |closeness, value| {
            if (closeness <= 0 or value >= threshold) continue;
            sum += std.math.clamp((value - middle) / (threshold - middle), 0, 1);
            count += 1;
        }
        return if (count == 0) 0 else sum / count;
    }
};

/// What the image's colors average to, overall and among its brightest.
const Colors = struct {
    average_lightness: f64,
    average_chroma: f64,
    warm_lean: f64,
    highlight_chroma: f64,
    highlight_color: Color,

    fn from(pixels: []const Color) Colors {
        var lightness_total: f64 = 0;
        var chroma_total: f64 = 0;
        var lean_total: f64 = 0;
        var by_lightness: [lightness_bins]usize = @splat(0);
        for (pixels) |pixel| {
            lightness_total += pixel.lightness;
            chroma_total += pixel.chroma;
            lean_total += pixel.chroma * @cos(std.math.degreesToRadians(pixel.hue - warm_hue));
            by_lightness[binOf(pixel.lightness)] += 1;
        }
        const threshold = brightestBin(&by_lightness, pixels.len, highlight_share);
        var highlight: Sum = .{};
        for (pixels) |pixel| {
            if (binOf(pixel.lightness) >= threshold) highlight.add(pixel);
        }
        const color_threshold = brightestBin(&by_lightness, pixels.len, highlight_color_share);
        const references = Analysis.referenceHues();
        var by_hue: [hue_count]Sum = @splat(.{});
        for (pixels) |pixel| {
            if (binOf(pixel.lightness) < color_threshold or pixel.chroma < highlight_color_chroma) continue;
            by_hue[Analysis.nearestPosition(&references, pixel.hue)].add(pixel);
        }
        var fullest = &by_hue[0];
        for (&by_hue) |*candidate| {
            if (candidate.chroma_total > fullest.chroma_total) fullest = candidate;
        }
        const count: f64 = @floatFromInt(pixels.len);
        return .{
            .average_lightness = lightness_total / count,
            .average_chroma = chroma_total / count,
            .warm_lean = if (chroma_total == 0) 0 else lean_total / chroma_total,
            .highlight_chroma = highlight.chroma_total / @as(f64, @floatFromInt(highlight.count)),
            .highlight_color = if (fullest.count > 0) fullest.mean() else highlight.mean(),
        };
    }

    const lightness_bins = 256;

    fn binOf(lightness: f64) usize {
        return @min(lightness_bins - 1, @as(usize, @intFromFloat(@max(0, lightness) * lightness_bins)));
    }

    /// The lowest bin holding the brightest `share` of the pixels, at least one.
    fn brightestBin(counts: *const [lightness_bins]usize, total: usize, share: f64) usize {
        const wanted = @max(1, @as(usize, @intFromFloat(@ceil(share * @as(f64, @floatFromInt(total))))));
        var seen: usize = 0;
        var bin: usize = lightness_bins;
        while (bin > 0) {
            bin -= 1;
            seen += counts[bin];
            if (seen >= wanted) break;
        }
        return bin;
    }

    /// Some colors summed in OKLab, for their mean.
    const Sum = struct {
        count: usize = 0,
        lightness: f64 = 0,
        green_red: f64 = 0,
        blue_yellow: f64 = 0,
        chroma_total: f64 = 0,

        fn add(sum: *Sum, color: Color) void {
            const hue = std.math.degreesToRadians(color.hue);
            sum.count += 1;
            sum.lightness += color.lightness;
            sum.green_red += color.chroma * @cos(hue);
            sum.blue_yellow += color.chroma * @sin(hue);
            sum.chroma_total += color.chroma;
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
};

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

fn crispnessOf(allocator: std.mem.Allocator, lightness: Plane, gradients: Gradients) std.mem.Allocator.Error!f64 {
    const energy = gradients.energy();
    if (energy == 0) return 0;
    const blurred = try lightness.clone(allocator);
    defer allocator.free(blurred.values);
    try blurred.blur(allocator, edge_blur);
    const blurred_gradients = try Gradients.from(allocator, blurred);
    defer blurred_gradients.free(allocator);
    return std.math.clamp(1 - blurred_gradients.energy() / energy, 0, 1);
}

/// The structure tensor's coherence, averaged with each pixel weighted by its edge energy.
fn straightnessOf(allocator: std.mem.Allocator, gradients: Gradients) std.mem.Allocator.Error!f64 {
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

fn gray(lightness: f64) Color {
    return .{ .lightness = lightness, .chroma = 0, .hue = 0 };
}

fn measure(values: []f32, width: usize) !Measurements {
    const pixels: [16]Color = @splat(gray(0.5));
    return from(testing.allocator, &pixels, .{ .values = values, .width = width }, .{ .screen_width = @floatFromInt(width) });
}

test "a flat image is calm, flat and has no edges" {
    var values: [64 * 64]f32 = @splat(0.4);
    const flat = try measure(&values, 64);
    try testing.expectEqual(0, flat.texture);
    try testing.expectEqual(0, flat.crispness);
    try testing.expectEqual(1, flat.flat_share);
    try testing.expectEqual(0, flat.highlight_lift);
}

test "noise is textured and fine, a smooth gradient is calm" {
    var noise: [64 * 64]f32 = undefined;
    var random: std.Random.DefaultPrng = .init(7);
    for (&noise) |*value| value.* = random.random().float(f32);
    const busy = try measure(&noise, 64);
    try testing.expect(busy.texture > 0.2);
    try testing.expect(busy.flat_share < 0.01);
    try testing.expect(busy.edge_sharpness > 0.5);

    var gradient: [64 * 64]f32 = undefined;
    for (&gradient, 0..) |*value, index| value.* = 0.3 + @as(f32, @floatFromInt(index % 64)) / 640;
    const calm = try measure(&gradient, 64);
    try testing.expect(calm.texture < 0.01);
}

test "straight hard stripes are crisp and straight, blurred ones lose crispness and fine detail" {
    var stripes: [64 * 64]f32 = undefined;
    for (&stripes, 0..) |*value, index| value.* = if (index % 64 / 8 % 2 == 0) 0.2 else 0.8;
    const hard = try measure(&stripes, 64);
    var noise: [64 * 64]f32 = undefined;
    var random: std.Random.DefaultPrng = .init(7);
    for (&noise) |*value| value.* = random.random().float(f32);
    const noisy = try measure(&noise, 64);
    try (Plane{ .values = &stripes, .width = 64 }).blur(testing.allocator, 4);
    const soft = try measure(&stripes, 64);

    try testing.expect(hard.crispness > 0.6 and hard.straightness > 0.9);
    try testing.expect(noisy.straightness < hard.straightness);
    try testing.expect(soft.crispness < 0.3);
    try testing.expect(soft.edge_sharpness < hard.edge_sharpness / 2);
}

/// A dark 64-pixel square with a bright 12-pixel square in its middle, with a halo around it
/// fading over `fade` pixels, none when 0.
fn spotlight(values: *[64 * 64]f32, fade: f32) void {
    for (values, 0..) |*value, index| {
        const column: f32 = @floatFromInt(index % 64);
        const row: f32 = @floatFromInt(index / 64);
        const distance = @max(@max(@abs(column - 31.5) - 6, @abs(row - 31.5) - 6), 0);
        value.* = if (distance == 0) 0.9 else if (fade == 0) 0.1 else 0.1 + 0.6 * @max(0, 1 - distance / fade);
    }
}

test "bright spots lift above the rest, with a halo when they bloom" {
    var sharp: [64 * 64]f32 = undefined;
    spotlight(&sharp, 0);
    var bloom: [64 * 64]f32 = undefined;
    spotlight(&bloom, 24);
    const crisp = try measure(&sharp, 64);
    const glowing = try measure(&bloom, 64);
    try testing.expect(crisp.highlight_lift > 0.7);
    try testing.expect(crisp.halo < 0.05);
    try testing.expect(glowing.halo > 0.3);
}

test "colors give their average, lean and brightest color" {
    const warm: Color = .{ .lightness = 0.4, .chroma = 0.1, .hue = warm_hue };
    const bright: Color = .{ .lightness = 0.9, .chroma = 0.2, .hue = 330 };
    var pixels: [100]Color = @splat(warm);
    for (pixels[0..6]) |*pixel| pixel.* = bright;
    const colors = Colors.from(&pixels);
    try testing.expectApproxEqAbs(0.43, colors.average_lightness, 1e-9);
    try testing.expect(colors.warm_lean > 0.5);
    try testing.expectApproxEqAbs(330, colors.highlight_color.hue, 1e-6);
    try testing.expectApproxEqAbs(0.2, colors.highlight_chroma, 1e-9);
}

test "a few solid colors concentrate, noise does not" {
    var solid: [64]Color = undefined;
    for (&solid, 0..) |*pixel, index| pixel.* = if (index < 32) gray(0.2) else gray(0.8);
    try testing.expectEqual(1, try colorConcentration(testing.allocator, &solid));
    var noise: [400]Color = undefined;
    var random: std.Random.DefaultPrng = .init(3);
    for (&noise) |*pixel| pixel.* = .{ .lightness = random.random().float(f64), .chroma = 0.2 * random.random().float(f64), .hue = 360 * random.random().float(f64) };
    try testing.expect(try colorConcentration(testing.allocator, &noise) < 0.3);
}
