//! Hyprland's `layout` options. Field names are Hyprland's option names (D27).

const values = @import("../values.zig");

/// If specified, whenever only a single window is open, it will be coerced into the specified aspect ratio. null: Hyprland's default, `2, 0, 0`.
single_window_aspect_ratio: ?values.Vec2 = null,
/// Minimum distance for single_window_aspect_ratio to take effect. null: Hyprland's default, `0.1`.
single_window_aspect_ratio_tolerance: ?f64 = null,
