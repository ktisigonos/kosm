//! Hyprland's `render` options. Field names are Hyprland's option names.

/// Enables direct scanout. null: Hyprland's default, `disable`.
direct_scanout: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
/// Whether to expand textures that have not yet resized to be larger. null: Hyprland's default, `true`.
expand_undersized_textures: ?bool = null,
/// Disable back buffer and bottom layer rendering. null: Hyprland's default, `false`.
xp_mode: ?bool = null,
/// Whether to enable a fade animation for CTM changes. null: Hyprland's default, `auto`.
ctm_animation: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
/// Enable Color Management pipelines (requires restart to fully take effect). null: Hyprland's default, `true`.
cm_enabled: ?bool = null,
/// Report content type to allow monitor profile autoswitch. null: Hyprland's default, `true`.
send_content_type: ?bool = null,
/// Auto-switch to hdr mode when fullscreen app is in hdr. null: Hyprland's default, `hdr`.
cm_auto_hdr: ?enum(i64) { disable = 0, hdr = 1, hdredid = 2 } = null,
/// Enable new render scheduling, which should improve FPS on underpowered devices. null: Hyprland's default, `false`.
new_render_scheduling: ?bool = null,
/// Submit eligible output commits asynchronously. null: Hyprland's default, `false`.
async_commit: ?bool = null,
/// Enable CM without shader. null: Hyprland's default, `ignore`.
non_shader_cm: ?enum(i64) { disable = 0, always = 1, ondemand = 2, ignore = 3 } = null,
/// Default transfer function for displaying SDR apps. null: Hyprland's default, `default`.
cm_sdr_eotf: ?enum { default, auto, srgb, gamma22, gamma22force } = null,
/// Enable commit timing proto. Requires restart. null: Hyprland's default, `true`.
commit_timing_enabled: ?bool = null,
/// Enable sending VCGT ramps to KMS with ICC profiles. null: Hyprland's default, `true`.
icc_vcgt_enabled: ?bool = null,
/// Use experimental blurred bg blending. null: Hyprland's default, `false`.
use_shader_blur_blend: ?bool = null,
/// Use experimental internal FP16 buffer. null: Hyprland's default, `auto`.
use_fp16: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
/// Keep umodified SDR frame copy for sreensharing. null: Hyprland's default, `auto`.
keep_unmodified_copy: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
/// Non_shader_cm interaction with ctm proto (hyprsunset and similar). null: Hyprland's default, `auto`.
non_shader_cm_interop: ?enum(i64) { disable = 0, enable = 1, auto = 2 } = null,
/// Internal workbuffer transfer function for fp16 in SDR mode. null: Hyprland's default, `monitor`.
fp16_sdr_tf: ?enum(i64) { monitor = 0, linear = 1 } = null,
/// Control fifo locking for not shown surfaces. always - use fifo lock for any surface, ignore_unfocused - ignore render_unfocused windows, never - skip locking invisible surfaces. null: Hyprland's default, `always`.
not_shown_fifo_lock: ?enum(i64) { always = 0, ignore_unfocused = 1, never = 2 } = null,
