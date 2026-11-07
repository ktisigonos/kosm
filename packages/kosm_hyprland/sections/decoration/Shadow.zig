//! Hyprland's `decoration.shadow` options. Field names are Hyprland's option names (D27).

const values = @import("../../values.zig");

/// Enable drop shadows on windows. null: Hyprland's default, `true`.
enabled: ?bool = null,
/// Shadow range (size) in layout px. 0..100. null: Hyprland's default, `4`.
range: ?i64 = null,
/// In what power to render the falloff (more power, the faster the falloff). 1..4. null: Hyprland's default, `3`.
render_power: ?i64 = null,
/// Whether the shadow should be sharp or not. null: Hyprland's default, `false`.
sharp: ?bool = null,
/// Shadow's color. Alpha dictates shadow's opacity. null: Hyprland's default, `#1a1a1aee`.
color: ?values.Gradient = null,
/// Inactive shadow color. null: `color` through the app's `inactive` when that is set, else Hyprland's default (D23).
color_inactive: ?values.Gradient = null,
/// Shadow's rendering offset. null: Hyprland's default, `2`.
offset: ?values.Vec2 = null,
/// Shadow's scale. null: Hyprland's default, `1`.
scale: ?f64 = null,
