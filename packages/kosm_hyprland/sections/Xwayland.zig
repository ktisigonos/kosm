//! Hyprland's `xwayland` options. Field names are Hyprland's option names.

/// Allow running applications using X11. null: Hyprland's default, `true`.
enabled: ?bool = null,
/// Uses the nearest neighbor filtering for xwayland apps, making them pixelated rather than blurry. null: Hyprland's default, `true`.
use_nearest_neighbor: ?bool = null,
/// Forces a scale of 1 on xwayland windows on scaled displays. null: Hyprland's default, `false`.
force_zero_scaling: ?bool = null,
/// Create the abstract Unix domain socket for XWayland. null: Hyprland's default, `false`.
create_abstract_socket: ?bool = null,
