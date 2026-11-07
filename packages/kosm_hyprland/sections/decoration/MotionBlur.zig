//! Hyprland's `decoration.motion_blur` options. Field names are Hyprland's option names (D27).

/// Enable motion blur for moving and resizing windows. null: Hyprland's default, `false`.
enabled: ?bool = null,
/// Amount of samples used for motion blur. 1..64. null: Hyprland's default, `7`.
samples: ?i64 = null,
