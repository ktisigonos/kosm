//! Hyprland's `scrolling` options. Field names are Hyprland's option names (D27).

/// When enabled, a single column on a workspace will always span the entire screen. null: Hyprland's default, `true`.
fullscreen_on_one_column: ?bool = null,
/// The default width of a column. null: Hyprland's default, `0.5`.
column_width: ?f64 = null,
/// When a column is focused, what method should be used to bring it into view. null: Hyprland's default, `fit`.
focus_fit_method: ?enum(i64) { center = 0, fit = 1 } = null,
/// Behaviour of the scrolling tape when a window is in focus. 0: Focus doesn't cause tape move. 1: Focus may cause tape move, mouse click always moves the tape. 2: Focus may cause tape move. null: Hyprland's default, `1`.
follow_focus: ?i64 = null,
/// When a window is focused, require that at least a given fraction of it is visible for focus to follow. null: Hyprland's default, `0.4`.
follow_min_visible: ?f64 = null,
/// A comma-separated list of preconfigured widths for colresize +conf/-conf. null: Hyprland's default, `0.333, 0.5, 0.667, 1.0`.
explicit_column_widths: ?[]const u8 = null,
/// Direction in which new windows appear and the layout scrolls. null: Hyprland's default, `right`.
direction: ?enum { left, right, up, down } = null,
/// Determines if column focus wraps around. null: Hyprland's default, `true`.
wrap_focus: ?bool = null,
/// Determines if column movement wraps around. null: Hyprland's default, `true`.
wrap_swapcol: ?bool = null,
