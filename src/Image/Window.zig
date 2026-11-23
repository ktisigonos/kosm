//! A translucent window over the image, as `Image.readableAlpha` checks its text.

const Color = @import("../Color.zig");

/// The window's background, drawn over the image at the alpha being checked; its own alpha
/// is ignored.
background: Color,
/// The text's color.
foreground: Color,
/// How far the blur behind the window spreads, as a Gaussian's standard deviation in screen
/// pixels. Default: 0, no blur.
blur: f64 = 0,
