//! Hyprland's `decoration.blur.glass` options. Field names are Hyprland's option names.

/// Maximum refraction displacement for glass blur types in pixels. null: Hyprland's default, `20`.
refraction: ?f64 = null,
/// Pattern size for glass blur types in pixels. null: Hyprland's default, `40`.
size: ?f64 = null,
/// Strength of the glass relief shading. null: Hyprland's default, `1`.
roughness: ?f64 = null,
