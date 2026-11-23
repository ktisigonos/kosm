//! How opaque a window over a source must be for its text to read, measured with the colors
//! the source itself gives, at each of `blur_spreads`.

const Readability = @This();

const std = @import("std");

/// The blurs the alphas are measured at: how far the blur behind the window spreads, as a
/// Gaussian's standard deviation in screen pixels. 0 is no blur.
pub const blur_spreads = [_]f64{ 0, 4, 8, 16, 32 };

/// The lowest background alpha (0..1) at which text reads, one per `blur_spreads`. Default:
/// 1 everywhere, opaque.
alphas: [blur_spreads.len]f64 = @splat(1),

/// The lowest readable alpha with the blur spreading `spread` screen pixels: read between the
/// measured spreads, and the last one's beyond it.
pub fn alphaAt(readability: Readability, spread: f64) f64 {
    if (spread <= blur_spreads[0]) return readability.alphas[0];
    for (blur_spreads[1..], 1..) |upper, index| {
        if (spread > upper) continue;
        const lower = blur_spreads[index - 1];
        const fraction = (spread - lower) / (upper - lower);
        return std.math.lerp(readability.alphas[index - 1], readability.alphas[index], fraction);
    }
    return readability.alphas[blur_spreads.len - 1];
}

const testing = std.testing;

test "the alpha is read between the measured spreads and held beyond them" {
    const readability: Readability = .{ .alphas = .{ 1, 0.8, 0.6, 0.4, 0.2 } };
    try testing.expectEqual(1, readability.alphaAt(-1));
    try testing.expectEqual(0.8, readability.alphaAt(4));
    try testing.expectApproxEqAbs(0.7, readability.alphaAt(6), 1e-12);
    try testing.expectApproxEqAbs(0.3, readability.alphaAt(24), 1e-12);
    try testing.expectEqual(0.2, readability.alphaAt(100));
}
