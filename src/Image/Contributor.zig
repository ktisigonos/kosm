//! One measurement's part in a trait: how much it weighs against the trait's other parts, and
//! the values its part rises between.

const Contributor = @This();

const std = @import("std");

/// How much this part counts against the trait's others; 0 leaves it out.
weight: f64,
/// The measurement at which this part gives 0.
low: f64,
/// The measurement at which this part gives 1, straight between; below `low` for a part that
/// falls as the measurement grows.
high: f64,

/// The part `value` gives, 0..1.
pub fn amount(contributor: Contributor, value: f64) f64 {
    if (contributor.high == contributor.low) return if (value >= contributor.high) 1 else 0;
    return std.math.clamp((value - contributor.low) / (contributor.high - contributor.low), 0, 1);
}

/// The weighted average of the parts `values` give, 0..1; 0 when no part has weight.
pub fn mix(contributors: []const Contributor, values: []const f64) f64 {
    std.debug.assert(contributors.len == values.len);
    var sum: f64 = 0;
    var total: f64 = 0;
    for (contributors, values) |contributor, value| {
        const weight = @max(0, contributor.weight);
        sum += weight * contributor.amount(value);
        total += weight;
    }
    return if (total == 0) 0 else sum / total;
}

const testing = std.testing;

test "a part rises or falls between its values and is clamped" {
    const rising: Contributor = .{ .weight = 1, .low = 0.2, .high = 0.6 };
    try testing.expectEqual(0, rising.amount(0.1));
    try testing.expectApproxEqAbs(0.5, rising.amount(0.4), 1e-12);
    try testing.expectEqual(1, rising.amount(0.9));
    const falling: Contributor = .{ .weight = 1, .low = 0.6, .high = 0.2 };
    try testing.expectEqual(1, falling.amount(0.1));
    try testing.expectApproxEqAbs(0.25, falling.amount(0.5), 1e-12);
    const step: Contributor = .{ .weight = 1, .low = 0.3, .high = 0.3 };
    try testing.expectEqual(0, step.amount(0.29));
    try testing.expectEqual(1, step.amount(0.3));
}

test "parts mix by weight, and no weight gives 0" {
    const parts = [_]Contributor{ .{ .weight = 3, .low = 0, .high = 1 }, .{ .weight = 1, .low = 0, .high = 1 } };
    try testing.expectApproxEqAbs(0.75, mix(&parts, &.{ 1, 0 }), 1e-12);
    const weightless = [_]Contributor{.{ .weight = 0, .low = 0, .high = 1 }};
    try testing.expectEqual(0, mix(&weightless, &.{1}));
}
