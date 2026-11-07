//! Hyprland's `group` options. Field names are Hyprland's option names (D27).

/// Whether new windows in a group spawn after current or at group tail. null: Hyprland's default, `true`.
insert_after_current: ?bool = null,
/// Whether Hyprland should focus on the window that has just been moved out of the group. null: Hyprland's default, `true`.
focus_removed_window: ?bool = null,
/// Whether window groups can be dragged into other groups. null: Hyprland's default, `true`.
merge_groups_on_drag: ?bool = null,
/// Whether one group will be merged with another when dragged into its groupbar. null: Hyprland's default, `true`.
merge_groups_on_groupbar: ?bool = null,
col: Col = .{},
/// Automatically group new windows. null: Hyprland's default, `true`.
auto_group: ?bool = null,
/// Whether dragging a window into a unlocked group will merge them. null: Hyprland's default, `enabled`.
drag_into_group: ?enum(i64) { disabled = 0, enabled = 1, only_into_groupbar = 2 } = null,
/// Whether dragging a floating window into a tiled window groupbar will merge them. null: Hyprland's default, `false`.
merge_floated_into_tiled_on_groupbar: ?bool = null,
/// Whether using movetoworkspace[silent] will merge the window into the workspace's solitary unlocked group. null: Hyprland's default, `false`.
group_on_movetoworkspace: ?bool = null,
groupbar: Groupbar = .{},

/// Hyprland's `group.col` options.
pub const Col = @import("group/Col.zig");
/// Hyprland's `group.groupbar` options.
pub const Groupbar = @import("group/Groupbar.zig");
