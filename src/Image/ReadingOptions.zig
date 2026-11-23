//! How text on a window over an image is judged readable. Sizes are in screen pixels,
//! contrast is the WCAG 2 ratio (1..21), lightness OKLCH's (0..1).

const ReadingOptions = @This();

const std = @import("std");

/// Width of the screen the image covers, in pixels, which scales the sizes below to the
/// image. Default: 2560.
screen_width: f64 = 2560,
/// Height of a line of text, in screen pixels: texture smaller than this hurts reading, larger
/// shapes do not. Default: 16.
text_size: f64 = 16,
/// The contrast text must keep against the window's background over the image. Default: 4.5
/// (WCAG's AA for body text).
minimum_contrast: f64 = 4.5,
/// The share of the image allowed to break a limit, so a few stray pixels decide nothing.
/// Default: 0.05.
worst_share: f64 = 0.05,
/// How much the lightness behind text may vary within a line's height (its standard
/// deviation) before the texture hurts reading. Default: 0.02.
maximum_texture: f64 = 0.02,

/// Image pixels per screen pixel, for an image `width` pixels wide.
pub fn scale(options: ReadingOptions, width: usize) f64 {
    return @as(f64, @floatFromInt(width)) / options.screen_width;
}

/// `size` screen pixels in the pixels of an image `width` wide, whole and at least 1.
pub fn pixels(options: ReadingOptions, width: usize, size: f64) usize {
    return @intFromFloat(@max(1, @round(size * options.scale(width))));
}

/// Half a line of text's height, in the pixels of an image `width` wide.
pub fn textRadius(options: ReadingOptions, width: usize) usize {
    return options.pixels(width, options.text_size / 2);
}
