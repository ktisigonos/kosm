//! What every module's `from` receives: the resolved palette, the mode and the variations (section 4).

const Theme = @This();

const std = @import("std");
const Color = @import("Color.zig");
const Palette = @import("Palette.zig");
const Variations = @import("Variations.zig");

/// Every hue filled in.
palette: Palette.Resolved,
/// Dark or light; modules pick their own background and foreground from it.
mode: Mode,
/// Shared transforms. Tweak them here once, for every module built from this theme.
variations: Variations,

/// The single global fact modules use to choose backgrounds and foregrounds.
pub const Mode = enum { dark, light };

/// Resolves the palette and fills every variation's default for `mode`. Contrast picks
/// choose between the palette's black and white, and shadows mix toward its black.
pub fn from(palette: Palette, mode: Mode) Theme {
    const resolved = palette.resolve();
    var variations = Variations.from(mode);
    variations.contrast.on.contrast.?.dark = resolved.black;
    variations.contrast.on.contrast.?.light = resolved.white;
    variations.contrast.on_muted.contrast.?.dark = resolved.black;
    variations.contrast.on_muted.contrast.?.light = resolved.white;
    variations.surface.shadow.mix.?.toward = resolved.black;
    return .{ .palette = resolved, .mode = mode, .variations = variations };
}

const testing = std.testing;

const test_palette: Palette = .{
    .black = .{ .lightness = 0.25, .chroma = 0.04, .hue = 250 },
    .white = .{ .lightness = 0.95, .chroma = 0.01, .hue = 250 },
    .cyan = .{ .lightness = 0.75, .chroma = 0.08, .hue = 200 },
};

test "contrast picks the palette's black or white" {
    const theme = from(test_palette, .dark);
    try testing.expectEqual(theme.palette.black, theme.variations.contrast.on.apply(theme.palette.white));
    try testing.expectEqual(theme.palette.white, theme.variations.contrast.on.apply(theme.palette.black));
    try testing.expectEqual(theme.palette.black, theme.variations.contrast.on.apply(theme.palette.cyan));
}

test "shadow mixes toward the palette's black" {
    const theme = from(test_palette, .light);
    const shadow = theme.variations.surface.shadow.apply(theme.palette.white);
    try testing.expectEqual(theme.palette.white.mix(theme.palette.black, 0.8).lightness, shadow.lightness);
    try testing.expectEqual(0.5, shadow.alpha);
}

test "a tweak on the theme reaches the composed variations read from it" {
    var theme = from(test_palette, .dark);
    theme.variations.state.inactive = .{ .chroma = -1 };
    const result = theme.variations.state.selectedInactive().apply(theme.palette.cyan);
    try testing.expectEqual(0.0, result.chroma);
}
