//! Hyprland's `decoration.blur.water` options. Field names are Hyprland's option names.

/// Maximum refraction displacement and injection strength for water blur in pixels. null: Hyprland's default, `32`.
strength: ?f64 = null,
/// Pointer radius for water blur in pixels. null: Hyprland's default, `20`.
radius: ?f64 = null,
/// Propagation speed for water blur. null: Hyprland's default, `0.76`.
speed: ?f64 = null,
/// Decay damping for water blur. null: Hyprland's default, `0.95`.
damping: ?f64 = null,
/// Maximum water blur animation duration in seconds. null: Hyprland's default, `12`.
duration: ?f64 = null,
