//! Hyprland's `master` options. Field names are Hyprland's option names.

/// Enable adding additional master windows in a horizontal split style. null: Hyprland's default, `false`.
allow_small_split: ?bool = null,
/// The scale of the special workspace windows. null: Hyprland's default, `1`.
special_scale_factor: ?f64 = null,
/// The size as a percentage of the master window. null: Hyprland's default, `0.55`.
mfact: ?f64 = null,
/// `master`: new window becomes master; `slave`: new windows are added to slave stack; `inherit`: inherit from focused window. null: Hyprland's default, `slave`.
new_status: ?enum { master, slave, inherit } = null,
/// Whether a newly open window should be on the top of the stack. null: Hyprland's default, `false`.
new_on_top: ?bool = null,
/// `before`, `after`: place new window relative to the focused window; `none`: place new window according to new_on_top. null: Hyprland's default, `none`.
new_on_active: ?enum { before, after, none } = null,
/// Default placement of the master area. null: Hyprland's default, `left`.
orientation: ?enum { left, right, top, bottom, center } = null,
/// When using orientation=center, make the master window centered only when at least this many slave windows are open. 0..10. null: Hyprland's default, `2`.
slave_count_for_center_master: ?i64 = null,
/// Set fallback for center master when slaves are less than slave_count_for_center_master. null: Hyprland's default, `left`.
center_master_fallback: ?enum { left, right, top, bottom } = null,
/// Centers the master window on monitor ignoring reserved areas. null: Hyprland's default, `false`.
center_ignores_reserved: ?bool = null,
/// If enabled, resizing direction will be determined by the mouse's position on the window. null: Hyprland's default, `true`.
smart_resizing: ?bool = null,
/// When enabled, dragging and dropping windows will put them at the cursor position. null: Hyprland's default, `true`.
drop_at_cursor: ?bool = null,
/// Whether to keep the master window in its configured position when there are no slave windows. null: Hyprland's default, `false`.
always_keep_position: ?bool = null,
/// When enabled, closing a window focuses the master window. null: Hyprland's default, `false`.
focus_master_on_close: ?bool = null,
