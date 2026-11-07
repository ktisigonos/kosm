//! Hyprland's `decoration` options. Field names are Hyprland's option names (D27).

/// Rounded corners' radius (in layout px). 0..100. null: Hyprland's default, `0`.
rounding: ?i64 = null,
/// Rounding power of corners (2 is a circle). null: Hyprland's default, `2`.
rounding_power: ?f64 = null,
/// Opacity of active windows. null: Hyprland's default, `1`.
active_opacity: ?f64 = null,
/// Opacity of inactive windows. null: Hyprland's default, `1`.
inactive_opacity: ?f64 = null,
/// Opacity of fullscreen windows. null: Hyprland's default, `1`.
fullscreen_opacity: ?f64 = null,
shadow: Shadow = .{},
glow: Glow = .{},
/// Enables dimming of parents of modal windows. null: Hyprland's default, `true`.
dim_modal: ?bool = null,
/// Enables dimming of inactive windows. null: Hyprland's default, `false`.
dim_inactive: ?bool = null,
/// How much inactive windows should be dimmed. null: Hyprland's default, `0.5`.
dim_strength: ?f64 = null,
/// How much to dim the rest of the screen by when a special workspace is open. null: Hyprland's default, `0.2`.
dim_special: ?f64 = null,
/// How much the dimaround window rule should dim by. null: Hyprland's default, `0.4`.
dim_around: ?f64 = null,
/// A path to a custom shader to be applied at the end of rendering. null: Hyprland's default, empty.
screen_shader: ?[]const u8 = null,
/// Whether the border should be treated as a part of the window. null: Hyprland's default, `true`.
border_part_of_window: ?bool = null,
blur: Blur = .{},
motion_blur: MotionBlur = .{},
wobble: Wobble = .{},

/// Hyprland's `decoration.shadow` options.
pub const Shadow = @import("decoration/Shadow.zig");
/// Hyprland's `decoration.glow` options.
pub const Glow = @import("decoration/Glow.zig");
/// Hyprland's `decoration.blur` options.
pub const Blur = @import("decoration/Blur.zig");
/// Hyprland's `decoration.motion_blur` options.
pub const MotionBlur = @import("decoration/MotionBlur.zig");
/// Hyprland's `decoration.wobble` options.
pub const Wobble = @import("decoration/Wobble.zig");
