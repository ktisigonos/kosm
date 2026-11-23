//! How `Image.surface` and `Image.readableAlpha` measure an image as a desktop's backdrop.
//! Sizes are in screen pixels, lightness is OKLCH's (0..1), contrast is the WCAG 2 ratio
//! (1..21).

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
/// The image's average texture (as for `maximum_texture`) at and below which `Surface.detail`
/// is 0. Default: 0.01, a misty landscape.
calm_texture: f64 = 0.01,
/// The average texture at and above which `Surface.detail` is 1. Default: 0.06, a dense
/// city or wireframe.
busy_texture: f64 = 0.06,
/// Edge hardness (0..1: how much of the image's edges are crisp and straight) at and below
/// which `Surface.softness` is 1. Photos and paintings measure about 0.45 to 0.6. Default:
/// 0.45.
soft_hardness: f64 = 0.45,
/// Edge hardness at and above which `Surface.softness` is 0. Default: 0.75, geometric art.
hard_hardness: f64 = 0.75,
