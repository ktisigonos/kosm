//! How `Image.traits` measures an image: how text is judged readable, and the contributors
//! each trait is mixed from. A contributor rises from 0 at its `low` to 1 at its `high`, and a
//! trait is its contributors' average by weight; weight 0 leaves one out.

const Contributor = @import("Contributor.zig");
const ReadingOptions = @import("ReadingOptions.zig");

/// How text on a window over the image is judged readable, for `Traits.readability`.
reading: ReadingOptions = .{},
detail: Detail = .{},
softness: Softness = .{},
glow: Glow = .{},
flatness: Flatness = .{},
blurriness: Blurriness = .{},
lightness: Lightness = .{},
contrast: Contrast = .{},
colorfulness: Colorfulness = .{},
warmth: Warmth = .{},

/// `Traits.detail`.
pub const Detail = struct {
    /// The standard deviation of lightness within a line of text's height, averaged. Default:
    /// 0.01 (a misty landscape) to 0.06 (a dense city).
    texture: Contributor = .{ .weight = 1, .low = 0.01, .high = 0.06 },
};

/// `Traits.softness`.
pub const Softness = struct {
    /// How much of the edges' energy a slight blur takes away, 0..1; softer as it falls.
    /// Default: 1 at 0.6, 0 at 0.9.
    crispness: Contributor = .{ .weight = 1, .low = 0.9, .high = 0.6 },
    /// How much nearby edges share a direction, 0..1; softer as it falls. Default: 1 at 0.6,
    /// 0 at 0.85.
    straightness: Contributor = .{ .weight = 1, .low = 0.85, .high = 0.6 },
};

/// `Traits.glow`.
pub const Glow = struct {
    /// How much lighter the brightest 2% are than the middle lightness. Default: 0.2 to 0.6.
    highlight_lift: Contributor = .{ .weight = 1, .low = 0.2, .high = 0.5 },
    /// How light the brightest parts' surroundings stay, 0 (dark right away) to 1 (as light).
    /// Default: 0.15 to 0.45, weighing 1.5: it tells a bloom from sharp highlights.
    halo: Contributor = .{ .weight = 1.5, .low = 0.15, .high = 0.45 },
    /// The brightest parts' chroma: white light glows less than neon. Default: 0.02 to 0.1,
    /// weighing 1.5.
    highlight_chroma: Contributor = .{ .weight = 1.5, .low = 0.02, .high = 0.1 },
};

/// `Traits.flatness`.
pub const Flatness = struct {
    /// The share of the image whose lightness barely varies within a line of text's height.
    /// Default: 0.2 to 0.8.
    flat_share: Contributor = .{ .weight = 1, .low = 0.2, .high = 0.8 },
    /// The share of the pixels in its four most common colors. Default: 0.2 to 0.7.
    color_concentration: Contributor = .{ .weight = 1, .low = 0.2, .high = 0.7 },
};

/// `Traits.blurriness`.
pub const Blurriness = struct {
    /// How abruptly edges change against the lightness they span, 0..1; blurrier as it falls.
    /// Crisp pictures measure about 0.4 to 0.6. Default: 1 at 0.2, 0 at 0.5.
    edge_sharpness: Contributor = .{ .weight = 1, .low = 0.5, .high = 0.2 },
};

/// `Traits.lightness`.
pub const Lightness = struct {
    /// The average OKLCH lightness. Default: 0 to 1.
    average: Contributor = .{ .weight = 1, .low = 0, .high = 1 },
};

/// `Traits.contrast`.
pub const Contrast = struct {
    /// The lightness between the darkest and lightest 5%. Default: 0.1 to 0.8.
    spread: Contributor = .{ .weight = 1, .low = 0.1, .high = 0.8 },
};

/// `Traits.colorfulness`.
pub const Colorfulness = struct {
    /// The average OKLCH chroma. Default: 0.02 to 0.12.
    chroma: Contributor = .{ .weight = 1, .low = 0.02, .high = 0.12 },
};

/// `Traits.warmth`.
pub const Warmth = struct {
    /// Which way the hues lean, weighted by chroma, -1 (sky blue) to 1 (orange). Default: -1
    /// to 1.
    lean: Contributor = .{ .weight = 1, .low = -1, .high = 1 },
};
