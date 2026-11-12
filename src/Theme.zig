//! What every app's `from` receives: the resolved palette, the mode, the roles, the code
//! colors, the variations, the alpha of backgrounds and the kosmos' names.
//!
//! `from` works everything out from an `Input`, in order: palette, roles, code colors. To
//! change something later, change `input` and call the update of its level, which redoes that
//! level and every one after it. Assigning a finished value directly wins but flows nowhere.

const Theme = @This();

const std = @import("std");
const Color = @import("Color.zig");
const Palette = @import("Palette.zig");
const Variations = @import("Variations.zig");

/// What the theme was built from. Change it, then call `updatePalette`, `updateRoles` or
/// `updateCode` to work out that level and every one after it again.
input: Input,
/// Every hue filled in.
palette: Palette.Resolved,
/// Dark or light; the background and foreground roles and the variations follow it. To
/// change it, build a new theme with `from`.
mode: Mode,
/// The colors apps give meaning to (background, accent, link, error, ...).
roles: Roles,
/// Colors for highlighting code.
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

/// What a theme is built from: the palette, the mode and the kosmos' own roles and code colors.
pub const Input = @import("Theme/Input.zig");
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

/// Works out the palette, every role and code color `input` leaves null, and every
/// variation's default for its mode. Contrast picks choose between the palette's black and
/// white, and shadows mix toward its black.
pub fn from(input: Input) Theme {
    var theme: Theme = .{
        .input = input,
        .palette = undefined,
        .mode = input.mode,
        .roles = undefined,
        .code = undefined,
        .variations = .from(input.mode),
    };
    theme.updatePalette();
    return theme;
}

/// Resolves `input.palette` again, points the variations' contrast picks and shadow at its
/// black and white, then updates the roles and code colors.
pub fn updatePalette(theme: *Theme) void {
    const palette = theme.input.palette.resolve();
    theme.palette = palette;
    theme.variations.contrast.on.contrast.?.dark = palette.black;
    theme.variations.contrast.on.contrast.?.light = palette.white;
    theme.variations.contrast.on_muted.contrast.?.dark = palette.black;
    theme.variations.contrast.on_muted.contrast.?.light = palette.white;
    theme.variations.surface.shadow.mix.?.toward = palette.black;
    theme.updateRoles();
}

/// Works out the roles again from `input.roles` and the palette, then updates the code colors.
pub fn updateRoles(theme: *Theme) void {
    theme.roles = .from(theme.palette, theme.mode, theme.input.roles);
    theme.updateCode();
}

/// Works out the code colors again from `input.code`, the palette, the roles and the variations.
pub fn updateCode(theme: *Theme) void {
    theme.code = .from(theme.palette, theme.roles, theme.variations, theme.input.code);
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

const test_pink: Color = .{ .lightness = 0.7, .chroma = 0.15, .hue = 350 };

test "contrast picks the palette's black or white" {
    const theme = from(.{ .palette = test_palette, .mode = .dark });
    try testing.expectEqual(theme.palette.black, theme.variations.contrast.on.apply(theme.palette.white));
    try testing.expectEqual(theme.palette.white, theme.variations.contrast.on.apply(theme.palette.black));
    try testing.expectEqual(theme.palette.black, theme.variations.contrast.on.apply(theme.palette.cyan));
}

test "shadow mixes toward the palette's black" {
    const theme = from(.{ .palette = test_palette, .mode = .light });
    const shadow = theme.variations.surface.shadow.apply(theme.palette.white);
    try testing.expectEqual(theme.palette.white.mix(theme.palette.black, 0.8).lightness, shadow.lightness);
    try testing.expectEqual(0.5, shadow.alpha);
}

test "a tweak on the theme reaches the composed variations read from it" {
    var theme = from(.{ .palette = test_palette, .mode = .dark });
    theme.variations.state.inactive = .{ .chroma = -1 };
    const result = theme.variations.state.selectedInactive().apply(theme.palette.cyan);
    try testing.expectEqual(0.0, result.chroma);
}

test "backgrounds are opaque unless the theme's alpha is lowered, and only alpha changes" {
    var theme = from(.{ .palette = test_palette, .mode = .dark });
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
    const dark = from(.{ .palette = test_palette, .mode = .dark });
    try testing.expectEqual(dark.palette.black, dark.roles.background);
    try testing.expectEqual(dark.palette.white, dark.roles.foreground);
    try testing.expectEqual(dark.palette.cyan, dark.roles.accent);
    try testing.expectEqual(dark.palette.blue, dark.roles.secondary);
    try testing.expectEqual(dark.palette.cyan, dark.roles.link);
    try testing.expectEqual(dark.palette.green, dark.roles.success);
    try testing.expectEqual(dark.palette.yellow, dark.roles.warning);
    try testing.expectEqual(dark.palette.red, dark.roles.@"error");

    const light = from(.{ .palette = test_palette, .mode = .light });
    try testing.expectEqual(light.palette.white, light.roles.background);
    try testing.expectEqual(light.palette.black, light.roles.foreground);
    try testing.expectEqual(dark.roles.accent, light.roles.accent);
}

test "code colors default from the palette and the foreground" {
    const theme = from(.{ .palette = test_palette, .mode = .light });
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

test "an overridden role wins and flows into the link and code colors" {
    const theme = from(.{
        .palette = test_palette,
        .mode = .dark,
        .roles = .{ .accent = test_pink, .foreground = test_pink },
    });
    try testing.expectEqual(test_pink, theme.roles.accent);
    try testing.expectEqual(test_pink, theme.roles.link);
    try testing.expectEqual(test_pink, theme.code.variable);
    try testing.expectEqual(theme.variations.emphasis.muted.apply(test_pink), theme.code.comment);
}

test "an overridden link wins over the accent" {
    const theme = from(.{ .palette = test_palette, .mode = .dark, .roles = .{ .link = test_pink } });
    try testing.expectEqual(test_pink, theme.roles.link);
    try testing.expectEqual(theme.palette.cyan, theme.roles.accent);
}

test "an overridden code color wins" {
    const theme = from(.{ .palette = test_palette, .mode = .dark, .code = .{ .comment = test_pink } });
    try testing.expectEqual(test_pink, theme.code.comment);
}

test "updating roles redoes the roles and code colors but keeps overrides" {
    var theme = from(.{ .palette = test_palette, .mode = .dark, .roles = .{ .warning = test_pink } });
    theme.input.roles.accent = theme.palette.blue;
    theme.input.roles.foreground = test_pink;
    theme.updateRoles();
    try testing.expectEqual(theme.palette.blue, theme.roles.accent);
    try testing.expectEqual(theme.palette.blue, theme.roles.link);
    try testing.expectEqual(test_pink, theme.roles.warning);
    try testing.expectEqual(test_pink, theme.code.variable);
}

test "updating the palette flows through roles and code colors and keeps variation tweaks" {
    var theme = from(.{ .palette = test_palette, .mode = .dark });
    theme.variations.state.hovered.lightness = 0.5;
    theme.input.palette.cyan = test_pink;
    theme.input.palette.white = test_pink;
    theme.updatePalette();
    try testing.expectEqual(test_pink, theme.roles.accent);
    try testing.expectEqual(test_pink, theme.roles.link);
    try testing.expectEqual(test_pink, theme.code.variable);
    try testing.expectEqual(test_pink, theme.variations.contrast.on.contrast.?.light);
    try testing.expectEqual(0.5, theme.variations.state.hovered.lightness);
}

test "updating code colors keeps roles assigned directly" {
    var theme = from(.{ .palette = test_palette, .mode = .dark });
    theme.roles.foreground = test_pink;
    theme.updateCode();
    try testing.expectEqual(test_pink, theme.code.variable);
}
