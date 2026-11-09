//! Hyprland's `input_capture` options. Field names are Hyprland's option names.

/// If enabled, modifiers are also captured and sent to the program. null: Hyprland's default, `false`.
capture_modifiers: ?bool = null,
/// If enabled, throw a wayland error when a invalid barrier is received. null: Hyprland's default, `true`.
enforce_barriers: ?bool = null,
