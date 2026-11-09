//! Hyprland's `gestures` options. Field names are Hyprland's option names.

/// In px, the distance of the touchpad gesture. 0..2000. null: Hyprland's default, `300`.
workspace_swipe_distance: ?i64 = null,
/// Enable workspace swiping from the edge of a touchscreen. null: Hyprland's default, `false`.
workspace_swipe_touch: ?bool = null,
/// Invert the direction (touchpad only). null: Hyprland's default, `true`.
workspace_swipe_invert: ?bool = null,
/// Invert the direction (touchscreen only). null: Hyprland's default, `false`.
workspace_swipe_touch_invert: ?bool = null,
/// Minimum speed in px per timepoint to force the change ignoring cancel_ratio. 0..200. null: Hyprland's default, `30`.
workspace_swipe_min_speed_to_force: ?i64 = null,
/// How much the swipe has to proceed in order to commence it. null: Hyprland's default, `0.5`.
workspace_swipe_cancel_ratio: ?f64 = null,
/// Whether a swipe right on the last workspace should create a new one. null: Hyprland's default, `true`.
workspace_swipe_create_new: ?bool = null,
/// If enabled, switching direction will be locked when you swipe past the direction_lock_threshold. null: Hyprland's default, `true`.
workspace_swipe_direction_lock: ?bool = null,
/// In px, the distance to swipe before direction lock activates. 0..200. null: Hyprland's default, `10`.
workspace_swipe_direction_lock_threshold: ?i64 = null,
/// If enabled, swiping will not clamp at the neighboring workspaces but continue to the further ones. null: Hyprland's default, `false`.
workspace_swipe_forever: ?bool = null,
/// If enabled, swiping will use the r prefix instead of the m prefix for finding workspaces. null: Hyprland's default, `false`.
workspace_swipe_use_r: ?bool = null,
/// Timeout for closing windows with the close gesture, in ms. 10..2000. null: Hyprland's default, `1000`.
close_max_timeout: ?i64 = null,
scrolling: Scrolling = .{},

/// Hyprland's `gestures.scrolling` options.
pub const Scrolling = @import("gestures/Scrolling.zig");
