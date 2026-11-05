//! kitty's "Scrollback" options. Field names are kitty's option names (D27).

const values = @import("../values.zig");

/// Number of lines of history to keep in memory for scrolling back. null: kitty's default, `2000`.
scrollback_lines: ?i64 = null,
/// Control when the scrollbar is displayed. null: kitty's default, `scrolled`.
scrollbar: ?enum { scrolled, always, never, hovered, scrolled_and_hovered, scrolled_or_hovered } = null,
/// If disabled, the scrollbar will not be controllable via the mouse and all mouse events will pass through the scrollbar. null: kitty's default, `yes`.
scrollbar_interactive: ?bool = null,
/// Clicking the scrollbar track jumps there instead of moving one screen at a time. null: kitty's default, `yes`.
scrollbar_jump_on_click: ?bool = null,
/// The width of the scroll bar in units of cell width. null: kitty's default, `0.5`.
scrollbar_width: ?f64 = null,
/// The width of the scroll bar when the mouse is hovering over it, in units of cell width. null: kitty's default, `1`.
scrollbar_hover_width: ?f64 = null,
/// The opacity of the scrollbar handle, 0 being fully transparent and 1 being full opaque. null: kitty's default, `0.5`.
scrollbar_handle_opacity: ?f64 = null,
/// The radius (curvature) of the scrollbar handle in units of cell width. null: kitty's default, `0.3`.
scrollbar_radius: ?f64 = null,
/// The gap between the scrollbar and the window edge in units of cell width. null: kitty's default, `0.1`.
scrollbar_gap: ?f64 = null,
/// The minimum height of the scrollbar handle in units of cell height. null: kitty's default, `1`.
scrollbar_min_handle_height: ?f64 = null,
/// The extra area around the handle to allow easier grabbing of the scollbar in units of cell width. null: kitty's default, `0.25`.
scrollbar_hitbox_expansion: ?f64 = null,
/// The opacity of the scrollbar track, 0 being fully transparent and 1 being full opaque. null: kitty's default, `0`.
scrollbar_track_opacity: ?f64 = null,
/// The opacity of the scrollbar track when the mouse is over the scrollbar, 0 being fully transparent and 1 being full opaque. null: kitty's default, `0.1`.
scrollbar_track_hover_opacity: ?f64 = null,
/// The color of the scrollbar handle. null: kitty's default, `foreground`.
scrollbar_handle_color: ?values.ScrollbarColor = null,
/// The color of the scrollbar track. null: kitty's default, `foreground`.
scrollbar_track_color: ?values.ScrollbarColor = null,
/// When a program uses the OSC 9;4 escape sequence to report progress, draw a progress bar in the specified position of the window. null: kitty's default, `top`.
progress_bar: ?enum { left, right, top, bottom, hidden } = null,
/// Program with which to view scrollback in a new window. null: kitty's default.
scrollback_pager: ?[]const u8 = null,
/// Separate scrollback history size (in MB), used only for browsing the scrollback buffer with pager. null: kitty's default, `0`.
scrollback_pager_history_size: ?f64 = null,
/// Fill new space with lines from the scrollback buffer after enlarging a window. null: kitty's default, `no`.
scrollback_fill_enlarged_window: ?bool = null,
/// Multiplier for the number of lines scrolled by the mouse wheel. null: kitty's default, `5.0`.
wheel_scroll_multiplier: ?f64 = null,
/// The minimum number of lines scrolled by the mouse wheel. null: kitty's default, `1`.
wheel_scroll_min_lines: ?i64 = null,
/// Multiplier for the number of lines scrolled by a touchpad. null: kitty's default, `1.0`.
touch_scroll_multiplier: ?f64 = null,
/// Enable per-pixel scrolling, in the kitty scrollback buffer, when using high precision input devices (for example touchpads). null: kitty's default, `yes`.
pixel_scroll: ?bool = null,
/// The amount of friction to apply to slow down momentum (inertial) scrolling. null: kitty's default, `0.96`.
momentum_scroll: ?f64 = null,
