//! Hyprland's `layers` options. Field names are Hyprland's option names.

/// If false, newly mapped layers are not allowed to render over existing covering fullscreen window. Note that fullscreen hides all pre-existing top layers regardless of this setting. null: Hyprland's default, `true`.
allow_new_top_layers_over_existing_fullscreen: ?bool = null,
/// If true, will make keyboard-interactive layers keep their focus on mouse move. null: Hyprland's default, `true`.
layers_hog_keyboard_focus: ?bool = null,
