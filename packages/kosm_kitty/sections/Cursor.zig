//! kitty's "Text cursor customization" options. Field names are kitty's option names.

const values = @import("../values.zig");

/// Default text cursor color; `none` renders it as reverse video. null: `colors.foreground`.
cursor: ?values.ColorOrNone = null,
/// The color of text under the cursor, or the cell's background color. null: `colors.background`.
cursor_text_color: ?values.ColorOrBackground = null,
/// The cursor shape can be one of `block`, `beam`, `underline`. null: kitty's default, `block`.
cursor_shape: ?enum { block, beam, underline } = null,
/// Defines the text cursor shape when the OS window is not focused. null: kitty's default, `hollow`.
cursor_shape_unfocused: ?enum { block, beam, underline, hollow, unchanged } = null,
/// The thickness of the beam cursor (in pts). null: kitty's default, `1.5`.
cursor_beam_thickness: ?f64 = null,
/// The thickness of the underline cursor (in pts). null: kitty's default, `2.0`.
cursor_underline_thickness: ?f64 = null,
/// The interval to blink the cursor (in seconds). null: kitty's default, `-1`.
cursor_blink_interval: ?values.Timing = null,
/// Stop blinking cursor after the specified number of seconds of keyboard inactivity. null: kitty's default, `15.0`.
cursor_stop_blinking_after: ?f64 = null,
/// Set this to a value larger than zero to enable a "cursor trail" animation. null: kitty's default, `0`.
cursor_trail: ?u32 = null,
/// Controls the decay times for the cursor trail effect when the `cursor_trail` is enabled. null: kitty's default, `0.1 0.4`.
cursor_trail_decay: ?values.TrailDecay = null,
/// Set the distance threshold for starting the cursor trail. null: kitty's default, `2`.
cursor_trail_start_threshold: ?values.TrailThreshold = null,
/// Set the color of the cursor trail when `cursor_trail` is enabled. null: kitty's default, `none`.
cursor_trail_color: ?values.ColorOrNone = null,
