//! Hyprland's `input.touchpad` options. Field names are Hyprland's option names.

/// Disable the touchpad while typing. null: Hyprland's default, `true`.
disable_while_typing: ?bool = null,
/// Inverts scrolling direction. null: Hyprland's default, `false`.
natural_scroll: ?bool = null,
/// Multiplier applied to the amount of scroll movement. null: Hyprland's default, `1`.
scroll_factor: ?f64 = null,
/// Sending LMB and RMB simultaneously will be interpreted as a middle click. null: Hyprland's default, `false`.
middle_button_emulation: ?bool = null,
/// Sets the tap button mapping for touchpad button emulation. [lrm/lmr]. null: Hyprland's default, empty.
tap_button_map: ?enum { lrm, lmr } = null,
/// Button presses with 1, 2, or 3 fingers will be mapped to LMB, RMB, and MMB respectively. null: Hyprland's default, `false`.
clickfinger_behavior: ?bool = null,
/// Tapping on the touchpad with 1, 2, or 3 fingers will send LMB, RMB, and MMB respectively. null: Hyprland's default, `true`.
tap_to_click: ?bool = null,
/// Lifting the finger off while dragging does not drop the dragged item: until a timeout, or until the next tap (`sticky`). null: Hyprland's default, `disabled`.
drag_lock: ?enum(i64) {
    disabled = 0,
    timeout = 1,
    sticky = 2,
    pub const numbered = true;
} = null,
/// Sets the tap and drag mode for the touchpad. null: Hyprland's default, `true`.
tap_and_drag: ?bool = null,
/// Inverts the horizontal movement of the touchpad. null: Hyprland's default, `false`.
flip_x: ?bool = null,
/// Inverts the vertical movement of the touchpad. null: Hyprland's default, `false`.
flip_y: ?bool = null,
/// Whether to use 3 or 4 finger drag. null: Hyprland's default, `disable`.
drag_3fg: ?enum(i64) { disable = 0, @"3_finger" = 1, @"4_finger" = 2 } = null,
