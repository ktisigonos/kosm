//! Hyprland's `decoration.blur.acrylic` options. Field names are Hyprland's option names (D27).

const kosm = @import("kosm");

/// Maximum acrylic lens displacement in pixels. null: Hyprland's default, `24`.
refraction: ?f64 = null,
/// Width of the curved acrylic edge in pixels. null: Hyprland's default, `48`.
bulb: ?f64 = null,
/// Amount of sharp backdrop transmitted through the acrylic surface. null: Hyprland's default, `0.82`.
clarity: ?f64 = null,
/// Relative chromatic separation in the acrylic lens. null: Hyprland's default, `0.025`.
aberration: ?f64 = null,
/// Acrylic tint color. Alpha controls optical absorption. null: Hyprland's default, `#eef5ff14`.
tint: ?kosm.Color = null,
