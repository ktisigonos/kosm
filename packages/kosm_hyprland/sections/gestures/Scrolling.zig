//! Hyprland's `gestures.scrolling` options. Field names are Hyprland's option names.

/// When releasing the scroll move gesture, whether it shoud try to snap to the grid. null: Hyprland's default, `true`.
move_snap_to_grid: ?bool = null,
/// When releasing the scroll move gesture, whether it shoud snap the cursor to the newly focused window. null: Hyprland's default, `true`.
move_snap_cursor: ?bool = null,
