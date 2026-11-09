//! Hyprland's `decoration.blur` options. Field names are Hyprland's option names.

/// Enable window background blur. null: Hyprland's default, `true`.
enabled: ?bool = null,
/// Set the blur variant. Blur variants enhance regular blur, but may increase GPU and CPU usage, significantly so if they are animated. null: Hyprland's default, `kawase`.
variant: ?enum(i64) { kawase = 0, frost = 1, ripple = 2, drops = 3, water = 4, fluid_jar = 5, prism = 6, heat_shimmer = 7, acrylic = 8, aurora = 9, haze = 10 } = null,
/// Blur size (distance). 0..100. null: Hyprland's default, `8`.
size: ?i64 = null,
/// The amount of passes to perform. 0..10. null: Hyprland's default, `1`.
passes: ?i64 = null,
/// Make the blur layer ignore the opacity of the window. null: Hyprland's default, `true`.
ignore_opacity: ?bool = null,
/// Whether to enable further optimizations to the blur. null: Hyprland's default, `true`.
new_optimizations: ?bool = null,
/// If enabled, floating windows will ignore tiled windows in their blur. null: Hyprland's default, `false`.
xray: ?bool = null,
/// If enabled, blur strength will be proportional to pixel opacity. null: Hyprland's default, `false`.
proportional: ?bool = null,
/// How much noise to apply. null: Hyprland's default, `0.0117`.
noise: ?f64 = null,
/// Contrast modulation for blur. null: Hyprland's default, `0.8916`.
contrast: ?f64 = null,
/// Brightness modulation for blur. null: Hyprland's default, `1`.
brightness: ?f64 = null,
/// Increase saturation of blurred colors. null: Hyprland's default, `0.1696`.
vibrancy: ?f64 = null,
/// How strong the effect of vibrancy is on dark areas. null: Hyprland's default, `0`.
vibrancy_darkness: ?f64 = null,
/// Whether to blur behind the special workspace (note: expensive). null: Hyprland's default, `false`.
special: ?bool = null,
/// Whether to blur popups (e.g. right-click menus). null: Hyprland's default, `false`.
popups: ?bool = null,
/// Works like ignorealpha in layer rules. If pixel opacity is below set value, will not blur. null: Hyprland's default, `0.2`.
popups_ignorealpha: ?f64 = null,
/// Whether to blur input methods (e.g. fcitx5). null: Hyprland's default, `false`.
input_methods: ?bool = null,
/// Works like ignorealpha in layer rules. If pixel opacity is below set value, will not blur. null: Hyprland's default, `0.2`.
input_methods_ignorealpha: ?f64 = null,
glass: Glass = .{},
acrylic: Acrylic = .{},
drops: Drops = .{},
heat_shimmer: HeatShimmer = .{},
aurora: Aurora = .{},
haze: Haze = .{},
ripple: Ripple = .{},
water: Water = .{},
fluid_jar: FluidJar = .{},

/// Hyprland's `decoration.blur.glass` options.
pub const Glass = @import("blur/Glass.zig");
/// Hyprland's `decoration.blur.acrylic` options.
pub const Acrylic = @import("blur/Acrylic.zig");
/// Hyprland's `decoration.blur.drops` options.
pub const Drops = @import("blur/Drops.zig");
/// Hyprland's `decoration.blur.heat_shimmer` options.
pub const HeatShimmer = @import("blur/HeatShimmer.zig");
/// Hyprland's `decoration.blur.aurora` options.
pub const Aurora = @import("blur/Aurora.zig");
/// Hyprland's `decoration.blur.haze` options.
pub const Haze = @import("blur/Haze.zig");
/// Hyprland's `decoration.blur.ripple` options.
pub const Ripple = @import("blur/Ripple.zig");
/// Hyprland's `decoration.blur.water` options.
pub const Water = @import("blur/Water.zig");
/// Hyprland's `decoration.blur.fluid_jar` options.
pub const FluidJar = @import("blur/FluidJar.zig");
