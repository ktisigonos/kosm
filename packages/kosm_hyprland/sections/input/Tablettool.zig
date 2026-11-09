//! Hyprland's `input.tablettool` options. Field names are Hyprland's option names.

/// The eraser button on the tool: the hardware's own behavior, or a button event (see `eraser_button_override`). null: Hyprland's default, `default`.
eraser_button_mode: ?enum(i64) {
    default = 0,
    button = 1,
    pub const numbered = true;
} = null,
/// Set a button to be button event when eraser_button_mode is set to 1. Has to be an int, cannot be a string. Must be a valid button (e.g. BTN_STYLUS) excluding fake buttons (e.g. BTN_TOOL_*) and keys (KEY_*). Check wev if you have any doubts regarding the ID. 0 means default. null: Hyprland's default, `0`.
eraser_button_override: ?i64 = null,
/// Set the minimum pressure range for the tool, a negative number will set the default minimum pressure value. This is usually 0.0. null: Hyprland's default, `-1.0`.
pressure_range_min: ?f64 = null,
/// Set the maximum pressure range for the tool, a negative number will set the default maximum pressure value. This is usually 1.0. null: Hyprland's default, `-1.0`.
pressure_range_max: ?f64 = null,
