//! Hyprland's `input.touchdevice` options. Field names are Hyprland's option names (D27).

/// Transform the input from touchdevices. 0..6. null: Hyprland's default, `0`.
transform: ?i64 = null,
/// The monitor to bind touch devices. null: Hyprland's default, `[[Auto]]`.
output: ?[]const u8 = null,
/// Whether input is enabled for touch devices. null: Hyprland's default, `true`.
enabled: ?bool = null,
