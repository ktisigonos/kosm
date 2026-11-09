//! Hyprland's `input.virtualkeyboard` options. Field names are Hyprland's option names.

/// Unify key down states and modifier states with other keyboards. null: Hyprland's default, `only_non_ime`.
share_states: ?enum(i64) { disable = 0, enable = 1, only_non_ime = 2 } = null,
/// Release all pressed keys by virtual keyboard on close. null: Hyprland's default, `false`.
release_pressed_on_close: ?bool = null,
