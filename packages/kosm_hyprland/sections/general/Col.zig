//! Hyprland's `general.col` options. Field names are Hyprland's option names.

const values = @import("../../values.zig");

/// Border color for inactive windows. null: `active_border` through the app's `inactive` when that is set, else Hyprland's default.
inactive_border: ?values.Gradient = null,
/// Border color for the active window. null: Hyprland's default, `#ffffffff`.
active_border: ?values.Gradient = null,
/// Inactive border color for window that cannot be added to a group. null: `nogroup_border_active` through the app's `inactive` when that is set, else Hyprland's default.
nogroup_border: ?values.Gradient = null,
/// Active border color for window that cannot be added to a group. null: Hyprland's default, `#ff00ffff`.
nogroup_border_active: ?values.Gradient = null,
