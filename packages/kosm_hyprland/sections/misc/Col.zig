//! Hyprland's `misc.col` options. Field names are Hyprland's option names (D27).

const kosm = @import("kosm");

/// Changes the color of the splash text. null: Hyprland's default, `#ffffff55`.
splash: ?kosm.Color = null,
