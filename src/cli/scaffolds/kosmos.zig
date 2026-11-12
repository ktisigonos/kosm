//! The scaffold_name kosmos, made by `kosm new kosmos scaffold_name`. Apply it with
//! `kosm apply scaffold_name`, or add `--diff` to see what it would change first.

const kosm = @import("kosm");
// Apps come from installed packages (`kosm list` shows them) or from your own apps/.
const kitty = @import("kosm_kitty");

/// Black and white are required; every hue left out is mixed from its wheel neighbours.
pub const palette: kosm.Palette = .{
    .black = kosm.hex("12161c"),
    .white = kosm.hex("d8dee9"),
    .red = kosm.hex("c2626b"),
    .yellow = kosm.hex("d9b56f"),
    .cyan = kosm.hex("6fb3c2"),
};

/// The apps this kosmos rices: one field per app. An optional app (`?kitty.App`) set to null
/// is skipped.
pub const Kosmos = struct {
    kitty: kitty.App,
};

/// The theme every app is built from. A variation tweaked here changes every app.
pub fn themeFor(mode: kosm.Theme.Mode) kosm.Theme {
    var theme = kosm.Theme.from(.{ .palette = palette, .mode = mode });
    theme.variations.state.hovered.lightness = 0.06;
    return theme;
}

/// Builds the apps from a theme, then tweaks single results: any field of any app can be
/// assigned after `from`. Variants call this with another theme and keep these tweaks.
pub fn from(theme: kosm.Theme) Kosmos {
    var result: Kosmos = .{ .kitty = kitty.from(theme) };
    result.kitty.fonts.font_size = 12;
    return result;
}

/// `kosm apply scaffold_name`. A kosmos may take one `Params` struct, whose fields become
/// flags (`--blur false`), and may return an error.
pub fn kosmos() Kosmos {
    return from(themeFor(.dark));
}

/// A variant: `kosm apply scaffold_name.light`.
pub fn light() Kosmos {
    return from(themeFor(.light));
}
