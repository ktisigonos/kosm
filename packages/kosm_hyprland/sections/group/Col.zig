//! Hyprland's `group.col` options. Field names are Hyprland's option names.

const values = @import("../../values.zig");

/// Active group border color. null: Hyprland's default, `#ffff0066`.
border_active: ?values.Gradient = null,
/// Inactive group border color. null: `border_active` through the app's `inactive` when that is set, else Hyprland's default.
border_inactive: ?values.Gradient = null,
/// Inactive locked group border color. null: `border_locked_active` through the app's `inactive` when that is set, else Hyprland's default.
border_locked_inactive: ?values.Gradient = null,
/// Active locked group border color. null: Hyprland's default, `#77550066`.
border_locked_active: ?values.Gradient = null,
