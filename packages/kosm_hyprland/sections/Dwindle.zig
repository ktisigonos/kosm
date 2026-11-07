//! Hyprland's `dwindle` options. Field names are Hyprland's option names (D27).

/// Force a split direction for new windows. null: Hyprland's default, `follow_mouse`.
force_split: ?enum(i64) { follow_mouse = 0, left = 1, right = 2 } = null,
/// If enabled, the split will not change regardless of what happens to the container. null: Hyprland's default, `false`.
preserve_split: ?bool = null,
/// If enabled, allows a more precise control over the window split direction based on the cursor's position. null: Hyprland's default, `false`.
smart_split: ?bool = null,
/// If enabled, resizing direction will be determined by the mouse's position on the window. null: Hyprland's default, `true`.
smart_resizing: ?bool = null,
/// If enabled, makes the preselect direction persist. null: Hyprland's default, `false`.
permanent_direction_override: ?bool = null,
/// Specifies the scale factor of windows on the special workspace. null: Hyprland's default, `1`.
special_scale_factor: ?f64 = null,
/// Specifies the auto-split width multiplier. null: Hyprland's default, `1`.
split_width_multiplier: ?f64 = null,
/// Whether to prefer the active window or the mouse position for splits. null: Hyprland's default, `true`.
use_active_for_splits: ?bool = null,
/// The default split ratio on window open. null: Hyprland's default, `1`.
default_split_ratio: ?f64 = null,
/// Specifies which window will receive the split ratio. null: Hyprland's default, `directional`.
split_bias: ?enum(i64) { directional = 0, current = 1 } = null,
/// If enabled, bindm movewindow will drop the window more precisely depending on where your mouse is. null: Hyprland's default, `false`.
precise_mouse_move: ?bool = null,
