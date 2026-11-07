//! Hyprland's `debug` options. Field names are Hyprland's option names (D27).

/// Print the debug performance overlay. null: Hyprland's default, `false`.
overlay: ?bool = null,
/// Flash damaged areas. null: Hyprland's default, `false`.
damage_blink: ?bool = null,
/// Enable OpenGL debugging and error checking. null: Hyprland's default, `false`.
gl_debugging: ?bool = null,
/// Disable logging to a file. null: Hyprland's default, `true`.
disable_logs: ?bool = null,
/// Disables time logging. null: Hyprland's default, `true`.
disable_time: ?bool = null,
/// Redraw only the needed bits of the display. null: Hyprland's default, `full`.
damage_tracking: ?enum(i64) { disable = 0, monitor = 1, full = 2 } = null,
/// Enables logging to stdout. null: Hyprland's default, `false`.
enable_stdout_logs: ?bool = null,
/// Set to 1 and then back to 0 to crash Hyprland. 0..1. null: Hyprland's default, `0`.
manual_crash: ?i64 = null,
/// If true, do not display config file parsing errors. null: Hyprland's default, `false`.
suppress_errors: ?bool = null,
/// Disables verification of the scale factors. null: Hyprland's default, `false`.
disable_scale_checks: ?bool = null,
/// Limits the number of displayed config file parsing errors. 0..20. null: Hyprland's default, `5`.
error_limit: ?i64 = null,
/// Sets the position of the error bar. null: Hyprland's default, `top`.
error_position: ?enum(i64) { top = 0, bottom = 1 } = null,
/// Enables colors in the stdout logs. null: Hyprland's default, `true`.
colored_stdout_logs: ?bool = null,
/// Enables logging the damage. null: Hyprland's default, `false`.
log_damage: ?bool = null,
/// Enables render pass debugging. null: Hyprland's default, `false`.
pass: ?bool = null,
/// Claims support for all cm proto features (requires restart). null: Hyprland's default, `false`.
full_cm_proto: ?bool = null,
/// Special case for DS with unmodified buffer. null: Hyprland's default, `true`.
ds_handle_same_buffer: ?bool = null,
/// Special case for DS with unmodified buffer unlocks fifo. null: Hyprland's default, `true`.
ds_handle_same_buffer_fifo: ?bool = null,
/// Render solitary window with empty damage. null: Hyprland's default, `false`.
render_solitary_wo_damage: ?bool = null,
/// Controls the VFR status of Hyprland. Do not turn off unless debugging. null: Hyprland's default, `true`.
vfr: ?bool = null,
/// Allow buffer invalidation. null: Hyprland's default, `enable`.
invalidate_buffers: ?enum(i64) { disable = 0, enable = 1 } = null,
/// Allow fp16 buffer invalidation. null: Hyprland's default, `enable`.
invalidate_fp16: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
