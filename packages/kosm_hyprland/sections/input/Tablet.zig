//! Hyprland's `input.tablet` options. Field names are Hyprland's option names (D27).

const values = @import("../../values.zig");

/// Whether input is enabled for tablets. null: Hyprland's default, `true`.
enabled: ?bool = null,
/// Transform the input from tablets. null: Hyprland's default, `normal`.
transform: ?values.Transform = null,
/// The monitor to bind tablets. null: Hyprland's default, empty.
output: ?[]const u8 = null,
/// Position of the mapped region in monitor layout. null: Hyprland's default, `2`.
region_position: ?values.Vec2 = null,
/// Whether to treat the region_position as an absolute position in monitor layout. null: Hyprland's default, `false`.
absolute_region_position: ?bool = null,
/// Size of the mapped region. null: Hyprland's default, `2`.
region_size: ?values.Vec2 = null,
/// Whether the input should be relative. null: Hyprland's default, `false`.
relative_input: ?bool = null,
/// If enabled, the tablet will be rotated 180 degrees. null: Hyprland's default, `false`.
left_handed: ?bool = null,
/// Size of tablet's active area in mm. null: Hyprland's default, `2`.
active_area_size: ?values.Vec2 = null,
/// Position of the active area in mm. null: Hyprland's default, `2`.
active_area_position: ?values.Vec2 = null,
