//! Kyanos, ported from Ricer's Kyanos.toml and Hyprland's defs.lua. kosm init wrote this file; it
//! is yours to edit (D84).

const kosm = @import("kosm");
const kitty = @import("kosm_kitty");
const ghostty = @import("kosm_ghostty");
const hyprland = @import("kosm_hyprland");
const zen = @import("kosm_zen");
const nvim = @import("kosm_nvim");

pub const kyanos_palette: kosm.Palette = .{
    .black = kosm.hex("041c26"),
    .white = kosm.hex("a3c5cc"),
    .red = kosm.hex("80333c"),
    .green = kosm.hex("338051"),
    .yellow = kosm.hex("668033"),
    .blue = kosm.hex("267180"),
    .magenta = kosm.hex("436496"),
    .cyan = kosm.hex("268078"),
};

/// The background is black at this alpha, so the terminals' opacity is 0.5 (D101).
pub const background_alpha: f64 = @as(f64, 0x80) / 255;

pub const font = "Maple Mono Normal NFP";
pub const font_size = 13;

/// Ricer's highlight (HSV value +10) and inactive (value -15).
pub fn kyanosTheme(palette: kosm.Palette) kosm.Theme {
    var theme = kosm.Theme.from(palette, .dark);
    theme.variations.lightness.bright = .{ .hsv = .{ .value = 0.10 } };
    theme.variations.emphasis.muted = .{ .hsv = .{ .value = -0.15 } };
    return theme;
}

pub const Kyanos = struct {
    kitty: kitty.App,
    ghostty: ghostty.App,
    hyprland: hyprland.App,
    zen: zen.App,
    nvim: nvim.App,
};

/// The colors every app shares.
const Colors = struct {
    palette: kosm.Palette.Resolved,
    bright: kosm.Modifier,
    background: kosm.Color,
    foreground_highlight: kosm.Color,
    background_highlight: kosm.Color,
    inactive_foreground: kosm.Color,

    fn from(theme: kosm.Theme) Colors {
        const palette = theme.palette;
        const bright = theme.variations.lightness.bright;
        var background = palette.black;
        background.alpha = background_alpha;
        return .{
            .palette = palette,
            .bright = bright,
            .background = background,
            .foreground_highlight = bright.apply(palette.white),
            .background_highlight = bright.apply(palette.black),
            .inactive_foreground = theme.variations.emphasis.muted.apply(palette.white),
        };
    }
};

pub fn kosmos() Kyanos {
    const theme = kyanosTheme(kyanos_palette);
    const colors: Colors = .from(theme);
    return .{
        .kitty = terminal(theme, colors),
        .ghostty = otherTerminal(theme, colors),
        .hyprland = compositor(colors),
        .zen = browser(theme, colors),
        .nvim = editor(theme, colors),
    };
}

fn terminal(theme: kosm.Theme, colors: Colors) kitty.App {
    var app = kitty.from(theme);
    app.colors.background = colors.background;
    app.fonts.font_family = .{ .family = font };
    app.fonts.font_size = font_size;
    app.fonts.disable_ligatures = .never;
    app.advanced.editor = "nvim";
    app.cursor.cursor_shape = .block;
    app.cursor.cursor_trail = 1;
    app.cursor.cursor_trail_start_threshold = .{ .horizontal = 0 };
    app.mouse.mouse_hide_wait = .{ .seconds = 0 };
    app.mouse.url_color = colors.bright.apply(colors.palette.cyan);
    app.mouse.url_style = .straight;
    app.mouse.open_url_with = "default";
    app.advanced.shell_integration = .{ .no_cursor = true };
    app.window.window_padding_width = .all(10);
    app.window.confirm_os_window_close = .{ .windows = 0 };
    app.colors.selection_foreground = .{ .color = colors.foreground_highlight };
    app.colors.selection_background = .{ .color = colors.background_highlight };
    return app;
}

fn otherTerminal(theme: kosm.Theme, colors: Colors) ghostty.App {
    var app = ghostty.from(theme);
    app.background = colors.background;
    app.font_family = &.{ font, "Cascadia Code NF", "Adwaita Mono" };
    app.font_family_bold = &.{font};
    app.font_family_italic = &.{font};
    app.font_family_bold_italic = &.{font};
    app.font_size = font_size;
    app.cursor_color = .{ .color = kosm.hex("ffffff") };
    app.selection_foreground = .{ .color = colors.foreground_highlight };
    app.selection_background = .{ .color = colors.background_highlight };
    return app;
}

/// Every `hl.config` value defs.lua feeds. Built without `from`, so nothing else is written.
fn compositor(colors: Colors) hyprland.App {
    const palette = colors.palette;
    const active = colors.bright.apply(palette.blue);
    const inactive = colors.bright.apply(palette.cyan);
    const active_border: hyprland.values.Gradient = .from(&.{ active, active });
    const inactive_border: hyprland.values.Gradient = .from(&.{ inactive, inactive });
    var app: hyprland.App = .{};

    app.general.border_size = 1;
    app.general.gaps_in = .all(5);
    app.general.gaps_out = .all(10);
    app.general.col = .{
        .active_border = active_border,
        .inactive_border = inactive_border,
        .nogroup_border_active = active_border,
        .nogroup_border = inactive_border,
    };

    const decoration = &app.decoration;
    decoration.rounding = 10;
    decoration.rounding_power = 2;
    decoration.active_opacity = 1;
    decoration.inactive_opacity = 1;
    decoration.dim_inactive = false;
    decoration.dim_strength = 0.2;
    decoration.dim_special = 0.2;
    decoration.dim_around = 0.4;
    decoration.shadow = .{
        .enabled = true,
        .sharp = false,
        .range = 10,
        .render_power = 4,
        .scale = 1,
        .color = .solid(active),
        .color_inactive = .solid(inactive),
        .offset = .{ .x = 0, .y = 0 },
    };
    decoration.glow = .{
        .enabled = true,
        .range = 20,
        .render_power = 4,
        .color = .solid(active),
        .color_inactive = .solid(inactive),
    };
    decoration.blur = .{
        .enabled = true,
        .popups = true,
        .input_methods = true,
        .special = false,
        .ignore_opacity = true,
        .popups_ignorealpha = 1,
        .input_methods_ignorealpha = 1,
        .new_optimizations = true,
        .xray = true,
        .variant = .frost,
        .size = 20,
        .passes = 4,
        .noise = 0.02,
        .contrast = 1,
        .brightness = 0.6,
        .vibrancy = 1,
        .vibrancy_darkness = 0,
        .glass = .{ .refraction = 20, .size = 300, .roughness = 0.5 },
        .ripple = .{ .strength = 32, .radius = 400, .width = 64, .duration = 0.45 },
        .drops = .{ .speed = 3 },
        .water = .{ .strength = 32, .radius = 10, .speed = 0.76, .damping = 0.95, .duration = 12 },
        .fluid_jar = .{
            .color = kosm.hex("1f5a66cc"),
            .speed = 5,
            .fill_amount = 0.5,
            .mass = 5.4,
            .precision = 1,
            .turbulence = 1.2,
            .distortion = 8,
        },
        .heat_shimmer = .{ .speed = 1 },
        .acrylic = .{ .refraction = 24, .bulb = 48, .clarity = 0.05, .aberration = 0.025, .tint = kosm.hex("eef5ff14") },
        .aurora = .{ .speed = 1, .intensity = 1, .color1 = kosm.hex("2e8799aa"), .color2 = kosm.hex("4d1f66aa") },
        .haze = .{ .intensity = 1, .iridescence = 1 },
    };
    decoration.motion_blur = .{ .enabled = true, .samples = 7 };
    decoration.wobble = .{
        .enabled = false,
        .mesh = 10,
        .stiffness = 1000,
        .damping = 50,
        .mass = 1,
        .intensity = 0.5,
        .value_epsilon = 0.25,
        .velocity_epsilon = 2,
    };

    app.misc.font_family = font;
    app.misc.splash_font_family = font;
    app.misc.col.splash = palette.white;
    app.misc.background_color = palette.black;
    app.misc.animate_manual_resizes = true;
    app.misc.animate_mouse_windowdragging = true;

    app.animations.enabled = true;
    app.animations.workspace_wraparound = false;

    app.extra = &.{.{ .path = "plugin.dynamic_cursors.rotate.length", .value = .{ .integer = cursor_size } }};
    return app;
}

const cursor_size = 24;

fn browser(theme: kosm.Theme, colors: Colors) zen.App {
    const palette = colors.palette;
    const bright = colors.bright;
    var app = zen.from(theme);
    app.background = colors.background;
    app.accent = colors.foreground_highlight;
    app.button = colors.background;
    app.button_hovered = bright.apply(colors.background);
    app.border = bright.apply(palette.blue);
    app.containers = .{
        .blue = palette.blue,
        .turquoise = palette.cyan,
        .green = palette.green,
        .yellow = palette.yellow,
        .orange = bright.apply(palette.yellow),
        .red = palette.red,
        .pink = bright.apply(palette.magenta),
        .purple = palette.magenta,
    };
    if (app.profile) |*profile| {
        const prefs = &profile.prefs.zen;
        prefs.theme.accent_color = kosm.hex("080808");
        prefs.theme.gradient.value = false;
        prefs.view.grey_out_inactive_windows = false;
        // Zen takes alpha in its color prefs, so pages sit on the translucent background.
        profile.format.color = .hex8;
        profile.prefs.browser.display.background_color = colors.background;
    }
    return app;
}

fn editor(theme: kosm.Theme, colors: Colors) nvim.App {
    const palette = colors.palette;
    const bright = colors.bright;
    var app = nvim.from(theme);
    app.transparent = true;
    app.format.color = .hex_upper;
    app.base16 = .{
        .base00 = palette.black,
        .base01 = colors.background_highlight,
        .base02 = colors.background_highlight,
        .base03 = colors.inactive_foreground,
        .base04 = colors.inactive_foreground,
        .base05 = palette.white,
        .base06 = colors.foreground_highlight,
        .base07 = colors.foreground_highlight,
        .base08 = bright.apply(palette.red),
        .base09 = bright.apply(palette.blue),
        .base0A = bright.apply(palette.yellow),
        .base0B = bright.apply(palette.cyan),
        .base0C = bright.apply(palette.cyan),
        .base0D = bright.apply(palette.blue),
        .base0E = bright.apply(palette.magenta),
        .base0F = colors.foreground_highlight,
    };
    return app;
}
