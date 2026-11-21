//! How `Image.palette` and `Image.themeInput` take colors from an image. Lightness and chroma
//! are OKLCH (lightness 0..1), contrast is the WCAG 2 ratio (1..21).

const Mode = @import("../Theme.zig").Mode;

/// How colors are taken from the image. Default: `.readable`.
style: Style = .readable,
/// What the hues the image lacks become. Default: `.semantic`.
fill: Fill = .semantic,
/// With a fill making hues up, the lightness and chroma they get. Default: `.neighbours`.
tone: Tone = .neighbours,
/// With a fill making hues up, how far they turn from their own hue toward the accent's, 0..1:
/// 0 keeps their hue, 1 makes them the accent's hue. A little ties them to the image, as
/// hand-made themes tint their reds and greens. Default: 0.
tint: f64 = 0,
/// With a fill making hues up and an image with no hues at all, the chroma they get; their
/// lightness is halfway between black's and white's. Default: 0.12.
fallback_chroma: f64 = 0.12,
/// Dark or light. null: light when the image's average lightness is above `light_above`,
/// else dark.
mode: ?Mode = null,
/// With `mode` null, the average lightness above which the image gets a light theme.
/// Default: 0.6.
light_above: f64 = 0.6,
/// How the accent, secondary and tertiary roles are picked among the image's hues.
/// Default: `.vivid`.
accent_by: AccentBy = .vivid,
/// How far apart on the wheel the secondary role's hue is from the accent's, and the tertiary's
/// from both, in degrees. Default: 60.
secondary_distance: f64 = 60,
/// Black is the color this share of the image's pixels is darker than, so a few stray dark
/// pixels do not decide it. Default: 0.01.
black_percentile: f64 = 0.01,
/// White is the color this share of the image's pixels is darker than. Default: 0.99.
white_percentile: f64 = 0.99,
/// Pixels below this chroma count as gray and give no hue. Default: 0.03.
minimum_chroma: f64 = 0.03,
/// A hue is set only if at least this share of all pixels is nearest it; the others are
/// left out, to be mixed from their neighbours. Default: 0.01.
minimum_share: f64 = 0.01,
/// With a built-in style other than `.literal`, the contrast every hue keeps against the
/// background, reached by changing only its lightness. Default: 4.5.
minimum_contrast: f64 = 4.5,
/// With a style other than `.literal`, the contrast between black and white, reached by
/// moving them apart. Default: 7.
foreground_contrast: f64 = 7,
/// With `.vivid`, how much the hues' chroma is multiplied by, within sRGB. Default: 1.3.
vivid_chroma: f64 = 1.3,
/// With `.muted`, how much the hues' chroma is multiplied by. Default: 0.6.
muted_chroma: f64 = 0.6,

/// How colors are taken from the image.
pub const Style = union(enum) {
    /// The image's colors, made readable: each hue keeps its hue and chroma and moves in
    /// lightness until it reaches `minimum_contrast` against the background, and black and
    /// white move apart until they reach `foreground_contrast`.
    readable,
    /// The image's colors exactly.
    literal,
    /// Readable, with the hues' chroma raised by `vivid_chroma`.
    vivid,
    /// Readable, with the hues' chroma lowered by `muted_chroma`.
    muted,
    /// Code of its own, written in Zig or through a frontend: given each hue and the
    /// background, it returns the hue's final color, and nothing runs after it
    /// (`kosm.Image.readable` keeps a hue readable). Black and white move apart as for every
    /// style but `.literal`. A style module's `style(...)`, or `Function.of`.
    function: Function,

    /// Code of a palette style's own, with the fields it was given.
    pub const Function = @import("StyleFunction.zig");
};

/// What the hues the image lacks become. A made-up hue is the wheel position's reference hue
/// (that of the saturated sRGB color there), turned by `tint`, at the lightness and chroma
/// `tone` picks; the style then applies to it too. Made-up hues are never the accent.
pub const Fill = enum {
    /// Only the image's own hues are set; the rest are left to `Palette.resolve`, which mixes
    /// them from their neighbours, so a blue image gets a bluish red.
    extracted,
    /// The image's own hues, plus red, yellow and green made up when the image lacks them, so
    /// the error, warning and success roles they default to stay recognizable; the rest are
    /// left to mixing.
    semantic,
    /// Every hue the image lacks is made up.
    complete,
};

/// The lightness and chroma of made-up hues.
pub const Tone = enum {
    /// Those of the image's hues on either side on the wheel, mixed by wheel position, so each
    /// fits the colors around it.
    neighbours,
    /// The average of the image's hues, weighted by their share of the pixels, so every
    /// made-up hue looks alike.
    uniform,
};

/// How the image's hues score for the accent, secondary and tertiary roles.
pub const AccentBy = enum {
    /// A hue's share of the pixels times its chroma, so a small bright area can beat a large
    /// dull one.
    vivid,
    /// A hue's share of the pixels alone: the most common hue wins.
    dominant,
};
