//! Hyprland's `input.touchdevice` options. Field names are Hyprland's option names (D27).

const values = @import("../../values.zig");

/// Transform the input from touchdevices. null: Hyprland's default, `normal`.
transform: ?values.Transform = null,
/// The monitor to bind touch devices. null: Hyprland's default, `[[Auto]]`.
output: ?[]const u8 = null,
/// Whether input is enabled for touch devices. null: Hyprland's default, `true`.
enabled: ?bool = null,
