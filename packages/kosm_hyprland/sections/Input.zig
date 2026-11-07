//! Hyprland's `input` options. Field names are Hyprland's option names (D27).

const values = @import("../values.zig");

/// Appropriate XKB keymap parameter. null: Hyprland's default, empty.
kb_model: ?[]const u8 = null,
/// Appropriate XKB keymap parameter. null: Hyprland's default, `us`.
kb_layout: ?[]const u8 = null,
/// Appropriate XKB keymap parameter. null: Hyprland's default, empty.
kb_variant: ?[]const u8 = null,
/// Appropriate XKB keymap parameter. null: Hyprland's default, empty.
kb_options: ?[]const u8 = null,
/// Appropriate XKB keymap parameter. null: Hyprland's default, empty.
kb_rules: ?[]const u8 = null,
/// Appropriate XKB keymap file. null: Hyprland's default, empty.
kb_file: ?[]const u8 = null,
/// Engage numlock by default. null: Hyprland's default, `false`.
numlock_by_default: ?bool = null,
/// Determines how keybinds act when multiple layouts are used. null: Hyprland's default, `false`.
resolve_binds_by_sym: ?bool = null,
/// The repeat rate for held-down keys, in repeats per second. 0..200. null: Hyprland's default, `25`.
repeat_rate: ?i64 = null,
/// Delay before a held-down key is repeated, in milliseconds. 0..2000. null: Hyprland's default, `600`.
repeat_delay: ?i64 = null,
/// Sets the mouse input sensitivity. Value is clamped to the range -1.0 to 1.0. null: Hyprland's default, `0`.
sensitivity: ?f64 = null,
/// Sets the cursor acceleration profile; `.{ .custom = ... }` is a curve of points. null: Hyprland's default, the device's own.
accel_profile: ?values.AccelProfile = null,
/// Force no cursor acceleration. null: Hyprland's default, `false`.
force_no_accel: ?bool = null,
/// Sets the rotation of a device in degrees clockwise. Value is clamped to the range 0 to 359. 0..359. null: Hyprland's default, `0`.
rotation: ?i64 = null,
/// Switches RMB and LMB. null: Hyprland's default, `false`.
left_handed: ?bool = null,
/// Sets the scroll acceleration curve, when `accel_profile` is `.custom`. null: Hyprland's default, none.
scroll_points: ?values.AccelCurve = null,
/// Sets the scroll method. [2fg/edge/on_button_down/no_scroll]. null: Hyprland's default, empty.
scroll_method: ?enum { @"2fg", edge, on_button_down, no_scroll } = null,
/// Sets the scroll button. 0 means default. 0..300. null: Hyprland's default, `0`.
scroll_button: ?i64 = null,
/// If the scroll button lock is enabled, the button does not need to be held down. null: Hyprland's default, `false`.
scroll_button_lock: ?bool = null,
/// Multiplier added to scroll movement for external mice. null: Hyprland's default, `1`.
scroll_factor: ?f64 = null,
/// Inverts scrolling direction. null: Hyprland's default, `false`.
natural_scroll: ?bool = null,
/// Specify if and how cursor movement should affect window focus. null: Hyprland's default, `follow`.
follow_mouse: ?enum(i64) { disabled = 0, follow = 1, detached = 2, separate = 3 } = null,
/// The smallest distance in logical pixels the mouse needs to travel for the window under it to get focused. null: Hyprland's default, `0`.
follow_mouse_threshold: ?f64 = null,
/// If enabled, the click that changes window focus is not forwarded to the window. null: Hyprland's default, `false`.
swallow_focus_click: ?bool = null,
/// Controls the window focus behavior when a window is closed. null: Hyprland's default, `next`.
focus_on_close: ?enum(i64) { next = 0, cursor = 1, mru = 2 } = null,
/// If disabled, mouse focus won't switch to the hovered window unless the mouse crosses a window boundary when follow_mouse=1. null: Hyprland's default, `true`.
mouse_refocus: ?bool = null,
/// Focus changes to the window under the cursor when switching from tiled to floating and back, and with `floating_too` also from floating to floating. null: Hyprland's default, `enabled`.
float_switch_override_focus: ?enum(i64) {
    disabled = 0,
    enabled = 1,
    floating_too = 2,
    pub const numbered = true;
} = null,
/// If enabled, having only floating windows in the special workspace will not block focusing windows in the regular workspace. null: Hyprland's default, `false`.
special_fallthrough: ?bool = null,
/// How to handle axis events around a focused window. null: Hyprland's default, `send`.
off_window_axis_events: ?enum(i64) { ignore = 0, send = 1, clamp = 2, warp = 3 } = null,
/// Emulates discrete scrolling from high resolution scrolling events. null: Hyprland's default, `non_standard`.
emulate_discrete_scroll: ?enum(i64) { disable = 0, non_standard = 1, force_all = 2 } = null,
/// Shrinks the inactive window hitboxes used for focus detection by the specified number of pixels. This creates a dead zone in gaps between windows where moving the cursor will not change focus. Works only with follow_mouse = 1. 0..300. null: Hyprland's default, `0`.
follow_mouse_shrink: ?i64 = null,
touchpad: Touchpad = .{},
touchdevice: Touchdevice = .{},
virtualkeyboard: Virtualkeyboard = .{},
tablet: Tablet = .{},
tablettool: Tablettool = .{},

/// Hyprland's `input.touchpad` options.
pub const Touchpad = @import("input/Touchpad.zig");
/// Hyprland's `input.touchdevice` options.
pub const Touchdevice = @import("input/Touchdevice.zig");
/// Hyprland's `input.virtualkeyboard` options.
pub const Virtualkeyboard = @import("input/Virtualkeyboard.zig");
/// Hyprland's `input.tablet` options.
pub const Tablet = @import("input/Tablet.zig");
/// Hyprland's `input.tablettool` options.
pub const Tablettool = @import("input/Tablettool.zig");
