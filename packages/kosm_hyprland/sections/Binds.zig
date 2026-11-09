//! Hyprland's `binds` options. Field names are Hyprland's option names.

/// If disabled, will not pass the mouse events to apps / dragging windows around if a keybind has been triggered. null: Hyprland's default, `false`.
pass_mouse_when_bound: ?bool = null,
/// In ms, how many ms to wait after a scroll event to allow passing another one for the binds. 0..2000. null: Hyprland's default, `300`.
scroll_event_delay: ?i64 = null,
/// An attempt to switch to the currently focused workspace will instead switch to the previous workspace. null: Hyprland's default, `disabled`.
workspace_back_and_forth: ?enum(i64) { disabled = 0, all_monitors = 1, per_monitor = 2 } = null,
/// If enabled, changing the active workspace will hide the special workspace on the monitor. null: Hyprland's default, `false`.
hide_special_on_workspace_change: ?bool = null,
/// If enabled, workspaces don't forget their previous workspace. null: Hyprland's default, `false`.
allow_workspace_cycles: ?bool = null,
/// Whether switching workspaces centers the cursor on the workspace or on its last active window. null: Hyprland's default, `last_window`.
workspace_center_on: ?enum(i64) {
    workspace = 0,
    last_window = 1,
    pub const numbered = true;
} = null,
/// How focuswindow/movewindow/etc with a direction pick a window: the most recently focused, or the longest shared edge. null: Hyprland's default, `history`.
focus_preferred_method: ?enum(i64) {
    history = 0,
    length = 1,
    pub const numbered = true;
} = null,
/// If enabled, dispatchers like moveintogroup, moveoutofgroup and movewindoworgroup will ignore lock per group. null: Hyprland's default, `false`.
ignore_group_lock: ?bool = null,
/// If enabled, when on a fullscreen window, movefocus will cycle fullscreen. null: Hyprland's default, `false`.
movefocus_cycles_fullscreen: ?bool = null,
/// If enabled, when in a grouped window, movefocus will cycle windows in the groups first. null: Hyprland's default, `false`.
movefocus_cycles_groupfirst: ?bool = null,
/// If enabled, apps that request keybinds to be disabled will not be able to do so. null: Hyprland's default, `false`.
disable_keybind_grabbing: ?bool = null,
/// If enabled, moving a window or focus over the edge of a monitor with a direction will move it to the next monitor. null: Hyprland's default, `true`.
window_direction_monitor_fallback: ?bool = null,
/// Allows fullscreen to pinned windows, and restore their pinned status afterwards. null: Hyprland's default, `false`.
allow_pin_fullscreen: ?bool = null,
/// If false, client requested FS will use default FS handler. null: Hyprland's default, `true`.
client_requested_fs_uses_layout_handler: ?bool = null,
/// Movement threshold in pixels for window dragging and c/g bind flags. 0 to disable. null: Hyprland's default, `0`.
drag_threshold: ?i64 = null,
/// If enabled, dragging a tiled or fullscreen window will center it on the cursor when it becomes floating. null: Hyprland's default, `true`.
drag_center_window: ?bool = null,
