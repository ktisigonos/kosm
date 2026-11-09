//! kitty's "Color scheme" options. Field names are kitty's option names.

const kosm = @import("kosm");
const values = @import("../values.zig");

/// The foreground and background colors. null: kitty's default, `#dddddd`.
foreground: ?kosm.Color = null,
/// kitty's `background`. null: kitty's default, `#000000`.
background: ?kosm.Color = null,
/// The opacity of the background color, 0..1. null: the alpha of `colors.background`, written only when below 1, rounded to two decimals.
background_opacity: ?f64 = null,
/// Set to a positive value to enable background blur (blurring of the visuals behind a transparent window) on platforms that support it. null: kitty's default, `0`.
background_blur: ?i64 = null,
/// A space separated list of upto 7 colors, with opacity. null: kitty's default.
transparent_background_colors: ?[]const values.TransparentColor = null,
/// Allow changing `background_opacity` at runtime, by shortcut or remote control. null: kitty's default, `no`.
dynamic_background_opacity: ?bool = null,
/// Glob pattern matching one or more background images. null: kitty's default, `none`.
background_image: ?[]const u8 = null,
/// Whether to tile, scale or clamp the background image. null: kitty's default, `tiled`.
background_image_layout: ?enum { mirror_tiled, scaled, tiled, clamped, centered, cscaled } = null,
/// When background image is scaled, whether linear interpolation should be used. null: kitty's default, `no`.
background_image_linear: ?bool = null,
/// How much to tint the background image by the background color. null: kitty's default, `0.0`.
background_tint: ?f64 = null,
/// How much to tint the background image at the window gaps by the background color, after applying `background_tint`. null: kitty's default, `1.0`.
background_tint_gaps: ?f64 = null,
/// How much to dim text that has the DIM/FAINT attribute set. null: kitty's default, `0.4`.
dim_opacity: ?f64 = null,
/// The foreground and background colors for text selected with the mouse. null: kitty's default, `#000000`.
selection_foreground: ?values.ColorOrNone = null,
/// The background color of text selected with the mouse. null: kitty's default, `#fffacd`.
selection_background: ?values.ColorOrNone = null,
/// How to fill in any colors that are unset (set to `none`) in the 256-color palette. null: kitty's default, `fixed`.
palette_generate: ?enum { fixed, semantic, legacy } = null,
/// black null: kitty's default, `#000000`.
color0: ?kosm.Color = null,
/// Bright variant of `color0`. null: `color0` through the app's `bright` modifier.
color8: ?kosm.Color = null,
/// red null: kitty's default, `#cc0403`.
color1: ?kosm.Color = null,
/// Bright variant of `color1`. null: `color1` through the app's `bright` modifier.
color9: ?kosm.Color = null,
/// green null: kitty's default, `#19cb00`.
color2: ?kosm.Color = null,
/// Bright variant of `color2`. null: `color2` through the app's `bright` modifier.
color10: ?kosm.Color = null,
/// yellow null: kitty's default, `#cecb00`.
color3: ?kosm.Color = null,
/// Bright variant of `color3`. null: `color3` through the app's `bright` modifier.
color11: ?kosm.Color = null,
/// blue null: kitty's default, `#0d73cc`.
color4: ?kosm.Color = null,
/// Bright variant of `color4`. null: `color4` through the app's `bright` modifier.
color12: ?kosm.Color = null,
/// magenta null: kitty's default, `#cb1ed1`.
color5: ?kosm.Color = null,
/// Bright variant of `color5`. null: `color5` through the app's `bright` modifier.
color13: ?kosm.Color = null,
/// cyan null: kitty's default, `#0dcdcd`.
color6: ?kosm.Color = null,
/// Bright variant of `color6`. null: `color6` through the app's `bright` modifier.
color14: ?kosm.Color = null,
/// white null: kitty's default, `#dddddd`.
color7: ?kosm.Color = null,
/// Bright variant of `color7`. null: `color7` through the app's `bright` modifier.
color15: ?kosm.Color = null,
/// Color for marks of type 1 null: kitty's default, `black`.
mark1_foreground: ?kosm.Color = null,
/// Color for marks of type 1 (light steel blue) null: kitty's default, `#98d3cb`.
mark1_background: ?kosm.Color = null,
/// Color for marks of type 2 null: kitty's default, `black`.
mark2_foreground: ?kosm.Color = null,
/// Color for marks of type 2 (beige) null: kitty's default, `#f2dcd3`.
mark2_background: ?kosm.Color = null,
/// Color for marks of type 3 null: kitty's default, `black`.
mark3_foreground: ?kosm.Color = null,
/// Color for marks of type 3 (violet) null: kitty's default, `#f274bc`.
mark3_background: ?kosm.Color = null,
