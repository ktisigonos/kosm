//! Hyprland's `decoration.glow` options. Field names are Hyprland's option names (D27).

const values = @import("../../values.zig");

/// Enable inner glow on windows. null: Hyprland's default, `false`.
enabled: ?bool = null,
/// Glow range (size) in layout px. 0..100. null: Hyprland's default, `10`.
range: ?i64 = null,
/// In what power to render the falloff (more power, the faster the falloff). 1..4. null: Hyprland's default, `3`.
render_power: ?i64 = null,
/// Glow's color. Alpha dictates glow's opacity. null: Hyprland's default, `#33ccffee`.
color: ?values.Gradient = null,
/// Inactive glow color. null: `color` through the app's `inactive` when that is set, else Hyprland's default (D23).
color_inactive: ?values.Gradient = null,
