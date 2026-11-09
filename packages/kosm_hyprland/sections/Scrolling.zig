//! Hyprland's `scrolling` options. Field names are Hyprland's option names.

/// When enabled, a single column on a workspace will always span the entire screen. null: Hyprland's default, `true`.
fullscreen_on_one_column: ?bool = null,
/// The default width of a column. null: Hyprland's default, `0.5`.
column_width: ?f64 = null,
/// When a column is focused, what method should be used to bring it into view. null: Hyprland's default, `fit`.
focus_fit_method: ?enum(i64) { center = 0, fit = 1 } = null,
/// Whether focusing a window moves the scrolling tape: never, also always on a mouse click (`click`), or only when focus moves (`soft`). null: Hyprland's default, `click`.
follow_focus: ?enum(i64) {
    disabled = 0,
    click = 1,
    soft = 2,
    pub const numbered = true;
} = null,
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
