//! Hyprland's `quirks` options. Field names are Hyprland's option names.

/// Prefer HDR mode. null: Hyprland's default, `disable`.
prefer_hdr: ?enum(i64) { disable = 0, enable = 1, gamescope_only = 2 } = null,
/// Do not report dmabuf formats which cannot be imported into KMS. null: Hyprland's default, `false`.
skip_non_kms_dmabuf_formats: ?bool = null,
