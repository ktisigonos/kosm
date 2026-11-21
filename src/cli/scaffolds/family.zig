//! The scaffold_name variation family, made by `kosm new family scaffold_name`. A base holds it
//! beside the theme, `scaffold_name.from(theme.mode)`, hands it to the apps reading it, and a
//! kosmos tweaks it there once for all of them: `family.soft.lightness = 0.1`.

const kosm = @import("kosm");

/// Glows for highlighted elements, applied to any color with `family.soft.apply(color)`.
pub const Family = struct {
    /// A soft glow. Default: a little lighter in dark mode, darker in light mode.
    soft: kosm.Modifier = .{},
    /// A strong glow. Default: lighter and more saturated in dark mode, darker in light mode.
    strong: kosm.Modifier = .{},
};

/// The family's modifiers for `mode`.
pub fn from(mode: kosm.Theme.Mode) Family {
    return switch (mode) {
        .dark => .{ .soft = .{ .lightness = 0.05 }, .strong = .{ .lightness = 0.12, .chroma = 0.03 } },
        .light => .{ .soft = .{ .lightness = -0.05 }, .strong = .{ .lightness = -0.12, .chroma = 0.03 } },
    };
}
