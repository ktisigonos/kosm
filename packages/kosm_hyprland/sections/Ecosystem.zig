//! Hyprland's `ecosystem` options. Field names are Hyprland's option names.

/// Disable the popup that shows up when you update hyprland to a new version. null: Hyprland's default, `false`.
no_update_news: ?bool = null,
/// Disable the popup that shows up twice a year encouraging to donate. null: Hyprland's default, `false`.
no_donation_nag: ?bool = null,
/// Whether to enable permission control. null: Hyprland's default, `false`.
enforce_permissions: ?bool = null,
