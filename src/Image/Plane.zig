//! One value per pixel of an image, row by row: its lightness, or one of its color channels.

const Plane = @This();

const std = @import("std");

/// The values, row by row; `values.len` is a multiple of `width`.
values: []f32,
/// Pixels per row; never 0.
width: usize,

/// Box blurs approximating a Gaussian; three are within a few percent of it.
const box_count = 3;

/// Rows of the plane.
pub fn height(plane: Plane) usize {
    return plane.values.len / plane.width;
}

/// A copy of `plane` in `allocator`.
pub fn clone(plane: Plane, allocator: std.mem.Allocator) std.mem.Allocator.Error!Plane {
    return .{ .values = try allocator.dupe(f32, plane.values), .width = plane.width };
}

/// Blurs the plane in place like a Gaussian of standard deviation `sigma` pixels, with the
/// edge pixels repeated beyond the edges. A `sigma` under about 0.8 pixels changes nothing.
pub fn blur(plane: Plane, allocator: std.mem.Allocator, sigma: f64) std.mem.Allocator.Error!void {
    if (sigma <= 0) return;
    const scratch = try allocator.alloc(f32, @max(plane.width, plane.height()));
    defer allocator.free(scratch);
    for (gaussianBoxes(sigma)) |radius| plane.boxBlur(scratch, radius);
}

/// Averages every value with its neighbours up to `radius` pixels away, in a square, in place.
pub fn boxBlur(plane: Plane, scratch: []f32, radius: usize) void {
    if (radius == 0) return;
    const rows = plane.height();
    for (0..rows) |row| blurLine(plane.values, row * plane.width, 1, plane.width, scratch, radius);
    for (0..plane.width) |column| blurLine(plane.values, column, plane.width, rows, scratch, radius);
}

/// The radii of `box_count` box blurs whose sum approximates a Gaussian of `sigma` pixels.
fn gaussianBoxes(sigma: f64) [box_count]usize {
    const count: f64 = box_count;
    const ideal = @sqrt(12 * sigma * sigma / count + 1);
    var lower: i64 = @intFromFloat(@floor(ideal));
    if (@mod(lower, 2) == 0) lower -= 1;
    const lower_float: f64 = @floatFromInt(lower);
    const lower_count = @round((12 * sigma * sigma - count * lower_float * lower_float - 4 * count * lower_float - 3 * count) / (-4 * lower_float - 4));
    var radii: [box_count]usize = undefined;
    for (&radii, 0..) |*radius, index| {
        const size = if (@as(f64, @floatFromInt(index)) < lower_count) lower else lower + 2;
        radius.* = @intCast(@divFloor(@max(size, 1) - 1, 2));
    }
    return radii;
}

/// Box-blurs the `length` values at `start`, `start + stride`, ... with a running sum.
fn blurLine(values: []f32, start: usize, stride: usize, length: usize, scratch: []f32, radius: usize) void {
    const line = scratch[0..length];
    for (line, 0..) |*value, index| value.* = values[start + index * stride];
    const last = length - 1;
    const window: f32 = @floatFromInt(2 * radius + 1);
    var sum: f32 = 0;
    for (0..2 * radius + 1) |offset| sum += line[clampedIndex(offset, radius, last)];
    for (0..length) |index| {
        values[start + index * stride] = sum / window;
        sum += line[@min(index + radius + 1, last)];
        sum -= line[clampedIndex(index, radius, last)];
    }
}

/// `index - radius`, clamped to 0..last.
fn clampedIndex(index: usize, radius: usize, last: usize) usize {
    return @min(index -| radius, last);
}

/// The standard deviation of the values in the square of `radius` pixels around each pixel:
/// how much the plane varies at that scale.
pub fn localDeviation(plane: Plane, allocator: std.mem.Allocator, radius: usize) std.mem.Allocator.Error!Plane {
    const mean = try plane.clone(allocator);
    defer allocator.free(mean.values);
    const squares: Plane = .{ .values = try allocator.alloc(f32, plane.values.len), .width = plane.width };
    for (squares.values, plane.values) |*square, value| square.* = value * value;
    const scratch = try allocator.alloc(f32, @max(plane.width, plane.height()));
    defer allocator.free(scratch);
    mean.boxBlur(scratch, radius);
    squares.boxBlur(scratch, radius);
    for (squares.values, mean.values) |*deviation, average| deviation.* = @sqrt(@max(0, deviation.* - average * average));
    return squares;
}

/// Buckets `upperValue` sorts values into; its answer is within (max / buckets) of exact.
const buckets = 4096;

/// The value that `share` (0..1) of the values are above, for values in 0..`max`; larger
/// values count as `max`.
pub fn upperValue(values: []const f32, share: f64, max: f32) f32 {
    var counts: [buckets]usize = @splat(0);
    for (values) |value| counts[bucketOf(value, max)] += 1;
    const allowed: usize = @intFromFloat(@floor(std.math.clamp(share, 0, 1) * @as(f64, @floatFromInt(values.len))));
    var above: usize = 0;
    var bucket: usize = buckets;
    while (bucket > 0) {
        bucket -= 1;
        above += counts[bucket];
        if (above > allowed) break;
    }
    return @as(f32, @floatFromInt(bucket + 1)) * max / buckets;
}

fn bucketOf(value: f32, max: f32) usize {
    const scaled = std.math.clamp(value / max, 0, 1) * buckets;
    return @min(@as(usize, @intFromFloat(scaled)), buckets - 1);
}

const testing = std.testing;

test "a blur keeps a flat plane flat and its edges repeated" {
    var values: [12]f32 = @splat(0.5);
    const plane: Plane = .{ .values = &values, .width = 4 };
    try plane.blur(testing.allocator, 3);
    for (values) |value| try testing.expectApproxEqAbs(0.5, value, 1e-6);
}

test "a blur spreads a step and keeps its average" {
    var values: [64]f32 = undefined;
    for (&values, 0..) |*value, index| value.* = if (index % 16 < 8) 0 else 1;
    const plane: Plane = .{ .values = &values, .width = 16 };
    try plane.blur(testing.allocator, 2);
    try testing.expect(values[7] > 0.2 and values[7] < 0.5);
    try testing.expect(values[8] > 0.5 and values[8] < 0.8);
    try testing.expectApproxEqAbs(0, values[0], 0.05);
    var sum: f32 = 0;
    for (values[0..16]) |value| sum += value;
    try testing.expectApproxEqAbs(8, sum, 0.3);
}

test "the boxes of a Gaussian grow with sigma and vanish below a pixel" {
    try testing.expectEqual([_]usize{ 0, 0, 0 }, gaussianBoxes(0.5));
    const small = gaussianBoxes(2);
    const large = gaussianBoxes(10);
    try testing.expect(small[0] >= 1 and large[0] > small[0]);
}

test "local deviation is zero on flat ground and high on a checkerboard" {
    var values: [64]f32 = undefined;
    for (&values, 0..) |*value, index| value.* = if ((index % 8 + index / 8) % 2 == 0) 0 else 1;
    const checkers = try (Plane{ .values = &values, .width = 8 }).localDeviation(testing.allocator, 1);
    defer testing.allocator.free(checkers.values);
    try testing.expect(checkers.values[27] > 0.45);
    var flat_values: [64]f32 = @splat(0.3);
    const flat = try (Plane{ .values = &flat_values, .width = 8 }).localDeviation(testing.allocator, 1);
    defer testing.allocator.free(flat.values);
    try testing.expectApproxEqAbs(0, flat.values[27], 1e-3);
}

test "the upper value is what the given share lies above" {
    var values: [100]f32 = undefined;
    for (&values, 0..) |*value, index| value.* = @as(f32, @floatFromInt(index)) / 100;
    try testing.expectApproxEqAbs(0.94, upperValue(&values, 0.05, 1), 0.002);
    try testing.expectApproxEqAbs(0.99, upperValue(&values, 0, 1), 0.01);
    try testing.expectApproxEqAbs(1, upperValue(&.{ 3, 4 }, 0, 1), 1e-6);
}
