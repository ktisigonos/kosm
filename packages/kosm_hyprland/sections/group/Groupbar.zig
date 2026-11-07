//! Hyprland's `group.groupbar` options. Field names are Hyprland's option names (D27).

const kosm = @import("kosm");
const values = @import("../../values.zig");

/// Enables groupbars. null: Hyprland's default, `true`.
enabled: ?bool = null,
/// Disable if contains single window. Considered only if enabled == true. null: Hyprland's default, `false`.
disable_when_only: ?bool = null,
/// Font used to display groupbar titles. null: Hyprland's default, empty.
font_family: ?[]const u8 = null,
/// Weight of the font used to display active groupbar titles. null: Hyprland's default.
font_weight_active: ?values.FontWeight = null,
/// Weight of the font used to display inactive groupbar titles. null: Hyprland's default.
font_weight_inactive: ?values.FontWeight = null,
/// Font size of groupbar title. 2..64. null: Hyprland's default, `8`.
font_size: ?i64 = null,
/// Enables gradients. null: Hyprland's default, `false`.
gradients: ?bool = null,
/// Height of the groupbar. 1..64. null: Hyprland's default, `14`.
height: ?i64 = null,
/// Height of the gap between the groupbar indicator and title. 0..64. null: Hyprland's default, `0`.
indicator_gap: ?i64 = null,
/// Height of the groupbar indicator. 0..64. null: Hyprland's default, `3`.
indicator_height: ?i64 = null,
/// Render the groupbar as a vertical stack. null: Hyprland's default, `false`.
stacked: ?bool = null,
/// Sets the decoration priority for groupbars. 0..6. null: Hyprland's default, `3`.
priority: ?i64 = null,
/// Whether to render titles in the group bar decoration. null: Hyprland's default, `true`.
render_titles: ?bool = null,
/// Whether scrolling in the groupbar changes group active window. null: Hyprland's default, `true`.
scrolling: ?bool = null,
/// Whether middle clicking the groupbar closes the clicked window. null: Hyprland's default, `true`.
middle_click_close: ?bool = null,
/// How much to round the groupbar. 0..40. null: Hyprland's default, `1`.
rounding: ?i64 = null,
/// Rounding power of groupbar corners (2 is a circle). null: Hyprland's default, `2`.
rounding_power: ?f64 = null,
/// How much to round the groupbar gradient. 0..40. null: Hyprland's default, `2`.
gradient_rounding: ?i64 = null,
/// Rounding power of groupbar gradient corners (2 is a circle). null: Hyprland's default, `2`.
gradient_rounding_power: ?f64 = null,
/// If yes, will only round at the groupbar edges. null: Hyprland's default, `true`.
round_only_edges: ?bool = null,
/// If yes, will only round at the groupbar gradient edges. null: Hyprland's default, `true`.
gradient_round_only_edges: ?bool = null,
/// Color for window titles in the groupbar. null: Hyprland's default, `#ffffffff`.
text_color: ?kosm.Color = null,
/// Color for inactive windows' titles in the groupbar. null: `text_color` through the app's `inactive` when that is set, else Hyprland's default (D23).
text_color_inactive: ?kosm.Color = null,
/// Color for the active window's title in a locked group. null: Hyprland's default.
text_color_locked_active: ?kosm.Color = null,
/// Color for inactive windows' titles in locked groups. null: `text_color_locked_active` through the app's `inactive` when that is set, else Hyprland's default (D23).
text_color_locked_inactive: ?kosm.Color = null,
col: Col = .{},
/// Gap between gradients and window. 0..20. null: Hyprland's default, `2`.
gaps_out: ?i64 = null,
/// Gap between gradients. 0..20. null: Hyprland's default, `2`.
gaps_in: ?i64 = null,
/// Keep an upper gap above gradient. null: Hyprland's default, `true`.
keep_upper_gap: ?bool = null,
/// Set an offset for a text. -20..20. null: Hyprland's default, `0`.
text_offset: ?i64 = null,
/// Set horizontal padding for a text. 0..22. null: Hyprland's default, `0`.
text_padding: ?i64 = null,
/// Enable background blur for groupbars. null: Hyprland's default, `false`.
blur: ?bool = null,

/// Hyprland's `group.groupbar.col` options.
pub const Col = @import("groupbar/Col.zig");
