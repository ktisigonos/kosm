//! Hyprland's `group.groupbar.col` options. Field names are Hyprland's option names (D27).

const values = @import("../../../values.zig");

/// Active group border color. null: Hyprland's default, `#ffff0066`.
active: ?values.Gradient = null,
/// Inactive (out of focus) group border color. null: `active` through the app's `inactive` when that is set, else Hyprland's default (D23).
inactive: ?values.Gradient = null,
/// Active locked group border color. null: Hyprland's default, `#ff550066`.
locked_active: ?values.Gradient = null,
/// Inactive locked group border color. null: `locked_active` through the app's `inactive` when that is set, else Hyprland's default (D23).
locked_inactive: ?values.Gradient = null,
