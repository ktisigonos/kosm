//! kitty's "Window layout" options. Field names are kitty's option names.

const kosm = @import("kosm");
const values = @import("../values.zig");

/// Reuse the last OS window size and maximized state for new instances. null: kitty's default, `yes`.
remember_window_size: ?bool = null,
/// The width of a new OS window, in pixels or cells. null: kitty's default, `640`.
initial_window_width: ?values.WindowSize = null,
/// The height of a new OS window, in pixels or cells. null: kitty's default, `400`.
initial_window_height: ?values.WindowSize = null,
/// Reuse the last OS window position for new instances. null: kitty's default, `no`.
remember_window_position: ?bool = null,
/// The enabled window layouts. null: kitty's default, `*`.
enabled_layouts: ?[]const values.Layout = null,
/// The width step, in cells, when resizing a window in a layout with `start_resizing_window`. null: kitty's default, `2`.
window_resize_step_cells: ?u32 = null,
/// The height step, in lines, when resizing a window in a layout with `start_resizing_window`. null: kitty's default, `2`.
window_resize_step_lines: ?u32 = null,
/// The width of window borders. null: kitty's default, `0.5pt`.
window_border_width: ?values.Length = null,
/// Draw only the minimum borders needed. null: kitty's default, `yes`.
draw_minimal_borders: ?bool = null,
/// The corner radius of window borders. null: kitty's default, `0`.
window_border_radius: ?values.Length = null,
/// Draw borders around a window even when there is only a single window visible. null: kitty's default, `no`.
draw_window_borders_for_single_window: ?bool = null,
/// The window margin (in pts) (blank area outside the border). null: kitty's default, `0`.
window_margin_width: ?values.Edges = null,
/// The window margin to use when only a single window is visible (in pts). null: kitty's default, `-1`.
single_window_margin_width: ?values.Edges = null,
/// Count the gap between neighbouring windows once instead of as the sum of both margins. null: kitty's default, `no`.
collapse_window_margins: ?bool = null,
/// The window padding (in pts) (blank area between the text and the window border). null: kitty's default, `0`.
window_padding_width: ?values.Edges = null,
/// The window padding to use when only a single window is visible (in pts). null: kitty's default, `-1`.
single_window_padding_width: ?values.Edges = null,
/// Where the cell area sits when the window size is not a multiple of the cell size. null: kitty's default, `center`.
placement_strategy: ?values.Position = null,
/// How the padding left when the window size is not a multiple of the cell size is filled. null: kitty's default, `background`.
padding_fill_strategy: ?enum {
    background,
    neighboring_cell,

    pub const underscored = true;
} = null,
/// The color for the border of the active window. null: kitty's default, `#00ff00`.
active_border_color: ?values.ColorOrNone = null,
/// The color for the border of inactive windows. null: kitty's default, `#cccccc`.
inactive_border_color: ?kosm.Color = null,
/// The color for the border of inactive windows in which a bell has occurred. null: kitty's default, `#ff5a00`.
bell_border_color: ?kosm.Color = null,
/// Fade the content in inactive windows by the specified amount. null: kitty's default, `1.0`.
inactive_text_alpha: ?f64 = null,
/// Hide the window decorations (title-bar and window borders) with `yes`. null: kitty's default, `no`.
hide_window_decorations: ?enum { no, yes, titlebar_only, titlebar_and_corners } = null,
/// Path to a logo image. null: kitty's default, `none`.
window_logo_path: ?[]const u8 = null,
/// Where to position the window logo in the window. null: kitty's default, `bottom-right`.
window_logo_position: ?values.Position = null,
/// The amount the logo should be faded into the background. null: kitty's default, `0.5`.
window_logo_alpha: ?f64 = null,
/// The percentage (0-100] of the window size to which the logo should scale. null: kitty's default, `0`.
window_logo_scale: ?values.LogoScale = null,
/// How long to wait, in seconds, before redrawing during a live resize of an OS window. null: kitty's default, `0.1 0.5`.
resize_debounce_time: ?values.ResizeDebounce = null,
/// Resize the OS window in steps as large as the cells, instead of with the usual pixel accuracy. null: kitty's default, `no`.
resize_in_steps: ?bool = null,
/// The list of characters for visual window selection. null: kitty's default.
visual_window_select_characters: ?[]const u8 = null,
/// Ask for confirmation when closing an OS window or a tab with at least this number of kitty windows in it by window manager (e.g. null: kitty's default, `-1`.
confirm_os_window_close: ?values.ConfirmClose = null,
/// Control dragging window borders to resize kitty windows. null: kitty's default, `2`.
window_drag_tolerance: ?f64 = null,
/// Control the position of the window title bar relative to the window content. null: kitty's default, `top`.
window_title_bar: ?enum { top, bottom } = null,
/// The minimum number of visible windows in a tab before window title bars are shown. null: kitty's default, `0`.
window_title_bar_min_windows: ?u32 = null,
/// A template to render the window title bar text. null: kitty's default.
window_title_template: ?[]const u8 = null,
/// Template to use for the active window title bar. null: kitty's default, `none`.
active_window_title_template: ?[]const u8 = null,
/// Foreground color for the active window title bar. null: kitty's default, `none`.
window_title_bar_active_foreground: ?values.ColorOrNone = null,
/// Background color for the active window title bar. null: kitty's default, `none`.
window_title_bar_active_background: ?values.ColorOrNone = null,
/// Foreground color for inactive window title bars. null: kitty's default, `none`.
window_title_bar_inactive_foreground: ?values.ColorOrNone = null,
/// Background color for inactive window title bars. null: kitty's default, `none`.
window_title_bar_inactive_background: ?values.ColorOrNone = null,
/// Horizontal alignment of the text in window title bars. null: kitty's default, `center`.
window_title_bar_align: ?enum { left, center, right } = null,

/// One-line lists kitty separates with commas instead of spaces.
pub const comma_separated = [_][]const u8{"enabled_layouts"};
