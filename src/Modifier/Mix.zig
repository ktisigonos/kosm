//! Mixing toward a color in OKLCH (D15).

const Mix = @This();

const Color = @import("../Color.zig");

/// The color to mix toward.
toward: Color,
/// 0 keeps the color, 1 gives `toward`.
amount: f64,
