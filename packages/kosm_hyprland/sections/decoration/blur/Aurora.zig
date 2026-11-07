//! Hyprland's `decoration.blur.aurora` options. Field names are Hyprland's option names (D27).

const kosm = @import("kosm");

/// Animation speed for aurora blur. 0 freezes the animation. Enabling will increase GPU usage. null: Hyprland's default, `1`.
speed: ?f64 = null,
/// Strength of the aurora color contribution. null: Hyprland's default, `0.35`.
intensity: ?f64 = null,
/// First aurora curtain color. Alpha controls its contribution. null: Hyprland's default, `#f0a0ff29`.
color1: ?kosm.Color = null,
/// Second aurora curtain color. Alpha controls its contribution. null: Hyprland's default, `#4dffff7a`.
color2: ?kosm.Color = null,
