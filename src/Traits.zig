//! What a source of colors is like (an image, or whatever else a package takes colors from),
//! as plain values every source gives alike. Measures are 0..1. They only describe: whoever
//! reads them decides what they mean for its values.

const Color = @import("Color.zig");

/// How busy the source is at the size of text: 0 calm, 1 dense.
detail: f64 = 0,
/// How soft its edges are: 0 crisp and straight (geometric art), 1 soft and organic.
softness: f64 = 0,
/// How much it glows: bright highlights blooming into darker surroundings, as neon does.
glow: f64 = 0,
/// The color of what glows; null when nothing does.
glow_color: ?Color = null,
/// How much of it is a few solid colors in large areas: 1 for a flat color or poster art.
flatness: f64 = 0,
/// How out of focus it is: 0 sharp, 1 blurred.
blurriness: f64 = 0,
/// How light it is on average: 0 black, 1 white.
lightness: f64 = 0,
/// How far apart its darkest and lightest parts are.
contrast: f64 = 0,
/// How colorful it is: 0 gray.
colorfulness: f64 = 0,
/// Which way its hues lean: 0 cold (blue), 0.5 neutral or gray, 1 warm (orange).
warmth: f64 = 0.5,
/// How much of it lies near each wheel hue, 0..1 each; grays count toward none.
hues: Hues = .{},
/// How opaque a window must be over it for its text to read, at each blur.
readability: Readability = .{},

/// The share of a source near each wheel hue.
pub const Hues = @import("Traits/Hues.zig");
/// How opaque a window over the source must be for its text to read, by blur.
pub const Readability = @import("Traits/Readability.zig");
