//! kitty's "Terminal bell" options. Field names are kitty's option names (D27).

const values = @import("../values.zig");

/// The audio bell. null: kitty's default, `yes`.
enable_audio_bell: ?bool = null,
/// The visual bell duration (in seconds). null: kitty's default, `0.0`.
visual_bell_duration: ?values.Timing = null,
/// The color used by visual bell. null: kitty's default, `none`.
visual_bell_color: ?values.ColorOrNone = null,
/// Request window attention on bell. null: kitty's default, `yes`.
window_alert_on_bell: ?bool = null,
/// Some text or a Unicode symbol to show on the tab if a window in the tab that does not have focus has a bell. null: kitty's default.
bell_on_tab: ?[]const u8 = null,
/// Program to run when a bell occurs. null: kitty's default, `none`.
command_on_bell: ?[]const u8 = null,
/// Show a badge on kitty's dock icon when a bell occurs and kitty is not the active application (macOS only). null: kitty's default, `yes`.
macos_dock_badge_on_bell: ?bool = null,
/// Path to a sound file to play as the bell sound. null: kitty's default, `none`.
bell_path: ?[]const u8 = null,
/// The XDG Sound Theme kitty will use to play the bell sound. null: kitty's default, `__custom`.
linux_bell_theme: ?[]const u8 = null,
