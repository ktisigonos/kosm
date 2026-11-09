//! Hyprland's `decoration.wobble` options. Field names are Hyprland's option names.

/// Enable wobble deformation for moving and resizing windows. null: Hyprland's default, `false`.
enabled: ?bool = null,
/// Amount of wobble mesh vertices per edge. 2..32. null: Hyprland's default, `12`.
mesh: ?i64 = null,
/// Spring stiffness for wobble deformation. null: Hyprland's default, `200`.
stiffness: ?f64 = null,
/// Spring damping for wobble deformation. null: Hyprland's default, `12`.
damping: ?f64 = null,
/// Spring mass for wobble deformation. null: Hyprland's default, `1`.
mass: ?f64 = null,
/// Wobble deformation impulse multiplier. null: Hyprland's default, `0.2`.
intensity: ?f64 = null,
/// Position epsilon below which wobble is considered stable. null: Hyprland's default, `0.25`.
value_epsilon: ?f64 = null,
/// Velocity epsilon below which wobble is considered stable. null: Hyprland's default, `2`.
velocity_epsilon: ?f64 = null,
