//! kitty's "Performance tuning" options. Field names are kitty's option names.

/// Delay between screen updates (in milliseconds). null: kitty's default, `10`.
repaint_delay: ?u32 = null,
/// Delay before input from the program running in the terminal is processed (in milliseconds). null: kitty's default, `3`.
input_delay: ?u32 = null,
/// Sync screen updates to the refresh rate of the monitor. null: kitty's default, `yes`.
sync_to_monitor: ?bool = null,
