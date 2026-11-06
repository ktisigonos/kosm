//! Kyanos, ported from Ricer's Kyanos.toml. kosm init wrote this file; it is yours to edit (D84).

const kosm = @import("kosm");
const kitty = @import("kosm_kitty");
const zen = @import("kosm_zen");
const nvim = @import("kosm_nvim");

pub const kyanos_palette: kosm.Palette = .{
    .black = kosm.hex("041c2680"),
    .white = kosm.hex("a3c5cc"),
    .red = kosm.hex("80333c"),
    .green = kosm.hex("338051"),
    .yellow = kosm.hex("668033"),
    .blue = kosm.hex("267180"),
    .magenta = kosm.hex("436496"),
    .cyan = kosm.hex("268078"),
};

/// Ricer's highlight (HSV value +10) and inactive (value -15).
pub fn kyanosTheme(palette: kosm.Palette) kosm.Theme {
    var theme = kosm.Theme.from(palette, .dark);
    theme.variations.lightness.bright = .{ .hsv = .{ .value = 0.10 } };
    theme.variations.emphasis.muted = .{ .hsv = .{ .value = -0.15 } };
    return theme;
}

pub const Kyanos = struct {
    kitty: kitty.App,
    zen: zen.App,
    nvim: nvim.App,
};

pub fn kosmos() Kyanos {
    const theme = kyanosTheme(kyanos_palette);
    const palette = theme.palette;
    const bright = theme.variations.lightness.bright;
    const foreground_highlight = bright.apply(palette.white);
    const background_highlight = bright.apply(palette.black);
    const inactive_foreground = theme.variations.emphasis.muted.apply(palette.white);

    var result: Kyanos = .{ .kitty = kitty.from(theme), .zen = zen.from(theme), .nvim = nvim.from(theme) };

    const terminal = &result.kitty;
    terminal.fonts.font_family = .{ .family = "Maple Mono Normal NFP" };
    terminal.fonts.font_size = 13;
    terminal.fonts.disable_ligatures = .never;
    terminal.advanced.editor = "nvim";
    terminal.cursor.cursor_shape = .block;
    terminal.cursor.cursor_trail = 1;
    terminal.cursor.cursor_trail_start_threshold = .{ .horizontal = 0 };
    terminal.mouse.mouse_hide_wait = .{ .seconds = 0 };
    terminal.mouse.url_color = bright.apply(palette.cyan);
    terminal.mouse.url_style = .straight;
    terminal.mouse.open_url_with = "default";
    terminal.advanced.shell_integration = .{ .no_cursor = true };
    terminal.window.window_padding_width = .all(10);
    terminal.window.confirm_os_window_close = .{ .windows = 0 };
    terminal.colors.selection_foreground = .{ .color = foreground_highlight };
    terminal.colors.selection_background = .{ .color = background_highlight };

    const browser = &result.zen;
    browser.accent = foreground_highlight;
    browser.button = palette.black;
    browser.button_hovered = background_highlight;
    browser.border = bright.apply(palette.blue);
    browser.containers = .{
        .blue = palette.blue,
        .turquoise = palette.cyan,
        .green = palette.green,
        .yellow = palette.yellow,
        .orange = bright.apply(palette.yellow),
        .red = palette.red,
        .pink = bright.apply(palette.magenta),
        .purple = palette.magenta,
    };

    const editor = &result.nvim;
    editor.transparent = true;
    editor.format.color = .hex_upper;
    editor.base16 = .{
        .base00 = palette.black,
        .base01 = background_highlight,
        .base02 = background_highlight,
        .base03 = inactive_foreground,
        .base04 = inactive_foreground,
        .base05 = palette.white,
        .base06 = foreground_highlight,
        .base07 = foreground_highlight,
        .base08 = bright.apply(palette.red),
        .base09 = bright.apply(palette.blue),
        .base0A = bright.apply(palette.yellow),
        .base0B = bright.apply(palette.cyan),
        .base0C = bright.apply(palette.cyan),
        .base0D = bright.apply(palette.blue),
        .base0E = bright.apply(palette.magenta),
        .base0F = foreground_highlight,
    };
    return result;
}
