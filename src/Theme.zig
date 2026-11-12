//! What every app's `from` receives: the resolved palette, the mode, the roles, the code
//! colors, the variations, the alpha of backgrounds and the kosmos' names.

const Theme = @This();

const std = @import("std");
const Color = @import("Color.zig");
const Palette = @import("Palette.zig");
const Variations = @import("Variations.zig");

/// Every hue filled in.
palette: Palette.Resolved,
/// Dark or light; the background and foreground roles follow it.
mode: Mode,
/// The colors apps give meaning to (background, accent, error, ...). Assign one to recolor
/// every app; `Roles.from` works them out again after a palette or mode change.
roles: Roles,
/// Colors for highlighting code. `Code.from` works them out again after a role changes.
code: Code,
/// Shared transforms. Tweak them here once, for every module built from this theme.
variations: Variations,
/// Alpha of every app's background, 0 (clear) to 1 (opaque): terminals, the browser and
/// editors follow it, so one value makes the whole desktop translucent. Default: 1.
background_alpha: f64 = 1,
/// The name programs show for the kosmos ("Krystallos"), in theme lists and pickers.
/// null: the name kosm applies the kosmos under (`krystallos`, `krystallos.dark`).
name: ?[]const u8 = null,
/// How the files a program picks by name are named. Default: `.shared`, `kosm.<ext>` for
/// every kosmos.
files: Files = .shared,

/// The single global fact modules use to choose backgrounds and foregrounds.
pub const Mode = enum { dark, light };

/// The colors apps give meaning to, in libadwaita's names.
pub const Roles = @import("Theme/Roles.zig");
/// Colors for highlighting code, in tree-sitter's capture names.
pub const Code = @import("Theme/Code.zig");

/// How an app names the files a program picks by name (KDE's color schemes, Blender's presets).
/// Files a program must include by path are always `kosm`.
pub const Files = enum {
    /// `kosm.<ext>`, the same file whatever kosmos is applied.
    shared,
    /// `<kosmos>.<ext>`, named as kosm applies the kosmos (`krystallos.dark.colors`), so each
    /// kosmos applied keeps its own file beside the others.
    per_kosmos,
};

/// Resolves the palette and fills every role, code color and variation's default for `mode`.
/// Contrast picks choose between the palette's black and white, and shadows mix toward its black.
pub fn from(palette: Palette, mode: Mode) Theme {
    const resolved = palette.resolve();
    var variations = Variations.from(mode);
    variations.contrast.on.contrast.?.dark = resolved.black;
    variations.contrast.on.contrast.?.light = resolved.white;
    variations.contrast.on_muted.contrast.?.dark = resolved.black;
    variations.contrast.on_muted.contrast.?.light = resolved.white;
    variations.surface.shadow.mix.?.toward = resolved.black;
    const roles: Roles = .from(resolved, mode);
    return .{
        .palette = resolved,
        .mode = mode,
        .roles = roles,
        .code = .from(resolved, roles, variations),
        .variations = variations,
    };
}

/// `color` with its alpha scaled by `background_alpha`: what an app's `from` gives the color it
/// uses as its background. Colors an app derives from that one keep the alpha.
pub fn asBackground(theme: Theme, color: Color) Color {
    var background = color;
    background.alpha *= theme.background_alpha;
    return background;
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

test "backgrounds are opaque unless the theme's alpha is lowered, and only alpha changes" {
    var theme = from(test_palette, .dark);
    try testing.expectEqual(theme.palette.black, theme.asBackground(theme.palette.black));
    theme.background_alpha = 0.5;
    const background = theme.asBackground(theme.palette.black);
    try testing.expectEqual(0.5, background.alpha);
    try testing.expectEqual(theme.palette.black.lightness, background.lightness);
    try testing.expectEqual(1, theme.palette.black.alpha);
    // A palette color that already carries alpha keeps it, scaled.
    var glass = theme.palette.black;
    glass.alpha = 0.5;
    try testing.expectEqual(0.25, theme.asBackground(glass).alpha);
}

test "roles default from the palette and the mode flips background and foreground" {
    const dark = from(test_palette, .dark);
    try testing.expectEqual(dark.palette.black, dark.roles.background);
    try testing.expectEqual(dark.palette.white, dark.roles.foreground);
    try testing.expectEqual(dark.palette.cyan, dark.roles.accent);
    try testing.expectEqual(dark.palette.blue, dark.roles.secondary);
    try testing.expectEqual(dark.palette.green, dark.roles.success);
    try testing.expectEqual(dark.palette.yellow, dark.roles.warning);
    try testing.expectEqual(dark.palette.red, dark.roles.@"error");

    const light = from(test_palette, .light);
    try testing.expectEqual(light.palette.white, light.roles.background);
    try testing.expectEqual(light.palette.black, light.roles.foreground);
    try testing.expectEqual(dark.roles.accent, light.roles.accent);
}

test "code colors default from the palette and the foreground" {
    const theme = from(test_palette, .light);
    const code = theme.code;
    const foreground = theme.palette.black;
    try testing.expectEqual(theme.variations.emphasis.muted.apply(foreground), code.comment);
    try testing.expectEqual(theme.palette.purple, code.keyword);
    try testing.expectEqual(theme.palette.green, code.string);
    try testing.expectEqual(theme.palette.orange, code.number);
    try testing.expectEqual(theme.palette.orange, code.constant);
    try testing.expectEqual(theme.palette.blue, code.function);
    try testing.expectEqual(theme.palette.yellow, code.type);
    try testing.expectEqual(foreground, code.variable);
    try testing.expectEqual(foreground, code.property);
    try testing.expectEqual(foreground, code.operator);
    try testing.expectEqual(foreground, code.punctuation);
    try testing.expectEqual(theme.palette.red, code.tag);
}

test "an assigned role wins and reaches the code colors worked out again from it" {
    var theme = from(test_palette, .dark);
    const pink: Color = .{ .lightness = 0.7, .chroma = 0.15, .hue = 350 };
    theme.roles.accent = pink;
    theme.roles.foreground = pink;
    try testing.expectEqual(pink, theme.roles.accent);
    try testing.expectEqual(theme.palette.white, theme.code.variable);
    theme.code = .from(theme.palette, theme.roles, theme.variations);
    try testing.expectEqual(pink, theme.code.variable);
    try testing.expectEqual(theme.variations.emphasis.muted.apply(pink), theme.code.comment);
}

test "roles worked out again follow a changed palette and mode" {
    var theme = from(test_palette, .dark);
    var palette = test_palette;
    palette.cyan = .{ .lightness = 0.6, .chroma = 0.1, .hue = 220 };
    theme.palette = palette.resolve();
    theme.mode = .light;
    theme.roles = .from(theme.palette, theme.mode);
    try testing.expectEqual(palette.cyan.?, theme.roles.accent);
    try testing.expectEqual(theme.palette.white, theme.roles.background);
}
