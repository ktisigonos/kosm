//! Hyprland's `decoration.blur.fluid_jar` options. Field names are Hyprland's option names.

const kosm = @import("kosm");

/// Fluid color for fluid jar blur. null: Hyprland's default, `#3399ffcc`.
color: ?kosm.Color = null,
/// Animation speed for fluid jar blur. null: Hyprland's default, `3.7`.
speed: ?f64 = null,
/// Fill amount for fluid jar blur. null: Hyprland's default, `0.5`.
fill_amount: ?f64 = null,
/// Inertial mass for fluid jar blur. null: Hyprland's default, `1.4`.
mass: ?f64 = null,
/// Fluid simulation precision multiplier. 2x is a good compromise. 4x is expensive. 8x is extreme and unnecessary. null: Hyprland's default, `2`.
precision: ?f64 = null,
/// Interior fluid turbulence multiplier. null: Hyprland's default, `1.2`.
turbulence: ?f64 = null,
/// Fluid refraction distortion multiplier. null: Hyprland's default, `8`.
distortion: ?f64 = null,
