//! Picks whichever of two colors reads better on top of the color, by WCAG 2 contrast ratio.

const Contrast = @This();

const Color = @import("../Color.zig");

/// The dark candidate. `Theme.from` sets it to the palette's black.
dark: Color = .{ .lightness = 0, .chroma = 0, .hue = 0 },
/// The light candidate. `Theme.from` sets it to the palette's white.
light: Color = .{ .lightness = 1, .chroma = 0, .hue = 0 },
/// How far the pick mixes back toward the original color: 0 is full contrast.
toward_original: f64 = 0,
