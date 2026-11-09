//! Hyprland's `cursor` options. Field names are Hyprland's option names.

/// Don't render cursors. null: Hyprland's default, `false`.
invisible: ?bool = null,
/// Disables hardware cursors. null: Hyprland's default, `auto`.
no_hardware_cursors: ?enum(i64) {
    disabled = 0,
    enabled = 1,
    auto = 2,
    pub const numbered = true;
} = null,
/// Disables scheduling new frames on cursor movement for fullscreen apps with VRR enabled. null: Hyprland's default, `auto`.
no_break_fs_vrr: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
/// Minimum refresh rate for cursor movement when no_break_fs_vrr is active. 10..500. null: Hyprland's default, `24`.
min_refresh_rate: ?i64 = null,
/// The padding, in logical px, between screen edges and the cursor. 0..20. null: Hyprland's default, `0`.
hotspot_padding: ?i64 = null,
/// In seconds, after how many seconds of cursor's inactivity to hide it. Set to 0 for never. null: Hyprland's default, `0`.
inactive_timeout: ?f64 = null,
/// If true, will not warp the cursor in many cases. null: Hyprland's default, `false`.
no_warps: ?bool = null,
/// When a window is refocused, the cursor returns to its last position relative to that window. null: Hyprland's default, `false`.
persistent_warps: ?bool = null,
/// Move the cursor to the last focused window after changing the workspace. null: Hyprland's default, `disable`.
warp_on_change_workspace: ?enum(i64) { disable = 0, enable = 1, force = 2 } = null,
/// Move the cursor to the last focused window when focusing a different monitor. null: Hyprland's default, `same_as_warp_on_change_workspace`.
warp_on_monitor_change: ?enum(i64) { same_as_warp_on_change_workspace = -1, disable = 0, enable = 1, force = 2 } = null,
/// Move the cursor to the last focused window when toggling a special workspace. null: Hyprland's default, `disable`.
warp_on_toggle_special: ?enum(i64) { disable = 0, enable = 1, force = 2 } = null,
/// The name of a default monitor for the cursor to be set to on startup. null: Hyprland's default, empty.
default_monitor: ?[]const u8 = null,
/// The factor to zoom by around the cursor. 1 means no zoom. null: Hyprland's default, `1`.
zoom_factor: ?f64 = null,
/// Whether the zoom should follow the cursor rigidly or loosely. null: Hyprland's default, `false`.
zoom_rigid: ?bool = null,
/// If enabled, when zooming, no antialiasing will be used. null: Hyprland's default, `false`.
zoom_disable_aa: ?bool = null,
/// Detaches the camera from the mouse when zoomed in. null: Hyprland's default, `true`.
zoom_detached_camera: ?bool = null,
/// Whether to enable hyprcursor support. null: Hyprland's default, `true`.
enable_hyprcursor: ?bool = null,
/// Hides the cursor when you press any key until the mouse is moved. null: Hyprland's default, `false`.
hide_on_key_press: ?bool = null,
/// Hides the cursor when the last input was a touch input until a mouse input is done. null: Hyprland's default, `true`.
hide_on_touch: ?bool = null,
/// Hides the cursor when the last input was a tablet input until a mouse input is done. null: Hyprland's default, `false`.
hide_on_tablet: ?bool = null,
/// Makes HW cursors use a CPU buffer. null: Hyprland's default, `auto`.
use_cpu_buffer: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
/// Sync xcursor theme with gsettings. null: Hyprland's default, `true`.
sync_gsettings_theme: ?bool = null,
/// Warp the cursor back to where it was after using a non-mouse input to move it. null: Hyprland's default, `false`.
warp_back_after_non_mouse_input: ?bool = null,
