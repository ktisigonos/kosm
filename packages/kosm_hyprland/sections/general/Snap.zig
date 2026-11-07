//! Hyprland's `general.snap` options. Field names are Hyprland's option names (D27).

/// Enable snapping for floating windows. null: Hyprland's default, `false`.
enabled: ?bool = null,
/// Minimum gap in pixels between windows before snapping. 0..100. null: Hyprland's default, `10`.
window_gap: ?i64 = null,
/// Minimum gap in pixels between window and monitor edges before snapping. 0..100. null: Hyprland's default, `10`.
monitor_gap: ?i64 = null,
/// If true, windows snap such that only one border's worth of space is between them. null: Hyprland's default, `false`.
border_overlap: ?bool = null,
/// If true, snapping will respect gaps between windows. null: Hyprland's default, `false`.
respect_gaps: ?bool = null,
