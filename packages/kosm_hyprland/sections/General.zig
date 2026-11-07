//! Hyprland's `general` options. Field names are Hyprland's option names (D27).

const values = @import("../values.zig");

/// Size of the border around windows. 0..20. null: Hyprland's default, `1`.
border_size: ?i64 = null,
/// Gaps between windows. null: Hyprland's default, `5`.
gaps_in: ?values.CssGap = null,
/// Gaps between windows and monitor edges. null: Hyprland's default, `20`.
gaps_out: ?values.CssGap = null,
/// Gaps between windows and monitor edges for floating windows. null: Hyprland's default, `0`.
float_gaps: ?values.CssGap = null,
/// Gaps between workspaces. Stacks with gaps_out. 0..100. null: Hyprland's default, `0`.
gaps_workspaces: ?i64 = null,
col: Col = .{},
/// Which layout to use: a built-in one, or one written in Lua (`.{ .lua = "name" }`). null: Hyprland's default, `dwindle`.
layout: ?values.Layout = null,
/// If true, will not fall back to the next available window when moving focus in a direction where no window was found. null: Hyprland's default, `false`.
no_focus_fallback: ?bool = null,
/// Enables resizing windows by clicking and dragging on borders and gaps. null: Hyprland's default, `false`.
resize_on_border: ?bool = null,
/// Extends the area around the border where you can click and drag on, only used when general:resize_on_border is on. 0..100. null: Hyprland's default, `15`.
extend_border_grab_area: ?i64 = null,
/// Show a cursor icon when hovering over borders, only used when general:resize_on_border is on. null: Hyprland's default, `true`.
hover_icon_on_border: ?bool = null,
/// Master switch for allowing tearing to occur. null: Hyprland's default, `false`.
allow_tearing: ?bool = null,
/// Force floating windows to use a specific corner when being resized (1-4 going clockwise from top left, 0 to disable). null: Hyprland's default, `disable`.
resize_corner: ?enum(i64) { disable = 0, top_left = 1, top_right = 2, bottom_right = 3, bottom_left = 4 } = null,
snap: Snap = .{},
/// If true, parent windows of modals will not be interactive. null: Hyprland's default, `true`.
modal_parent_blocking: ?bool = null,
/// Overrides the system locale. null: Hyprland's default, empty.
locale: ?[]const u8 = null,

/// Hyprland's `general.col` options.
pub const Col = @import("general/Col.zig");
/// Hyprland's `general.snap` options.
pub const Snap = @import("general/Snap.zig");
