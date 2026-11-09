//! Hyprland's `misc` options. Field names are Hyprland's option names.

const kosm = @import("kosm");

/// Disables the random Hyprland logo / anime girl background. :(. null: Hyprland's default, `false`.
disable_hyprland_logo: ?bool = null,
/// Disables the Hyprland splash rendering. null: Hyprland's default, `false`.
disable_splash_rendering: ?bool = null,
col: Col = .{},
/// Set the global default font to render the text. null: Hyprland's default, `Sans`.
font_family: ?[]const u8 = null,
/// Changes the font used to render the splash text. null: Hyprland's default, empty.
splash_font_family: ?[]const u8 = null,
/// Forces one of Hyprland's 3 default wallpapers, or a random one. null: Hyprland's default, `random`.
force_default_wallpaper: ?enum(i64) {
    random = -1,
    wall0 = 0,
    wall1 = 1,
    wall2 = 2,
    pub const numbered = true;
} = null,
/// Controls the VRR (Adaptive Sync) of your monitors. null: Hyprland's default, `off`.
vrr: ?enum(i64) { off = 0, on = 1, fullscreen = 2, fullscreen_game = 3 } = null,
/// If DPMS is set to off, wake up the monitors if the mouse moves. null: Hyprland's default, `false`.
mouse_move_enables_dpms: ?bool = null,
/// If DPMS is set to off, wake up the monitors if a key is pressed. null: Hyprland's default, `false`.
key_press_enables_dpms: ?bool = null,
/// Name virtual keyboards after the processes that create them. null: Hyprland's default, `true`.
name_vk_after_proc: ?bool = null,
/// Will make mouse focus follow the mouse when drag and dropping. null: Hyprland's default, `true`.
always_follow_on_dnd: ?bool = null,
/// If true, will make keyboard-interactive layers keep their focus on mouse move. null: Hyprland's default, `true`.
layers_hog_keyboard_focus: ?bool = null,
/// If true, will animate manual window resizes/moves. null: Hyprland's default, `false`.
animate_manual_resizes: ?bool = null,
/// If true, will animate windows being dragged by mouse. null: Hyprland's default, `false`.
animate_mouse_windowdragging: ?bool = null,
/// If true, the config will not reload automatically on save. null: Hyprland's default, `false`.
disable_autoreload: ?bool = null,
/// Enable window swallowing. null: Hyprland's default, `false`.
enable_swallow: ?bool = null,
/// The class regex to be used for windows that should be swallowed. null: Hyprland's default, empty.
swallow_regex: ?[]const u8 = null,
/// The title regex to be used for windows that should not be swallowed. null: Hyprland's default, empty.
swallow_exception_regex: ?[]const u8 = null,
/// Whether Hyprland should focus an app that requests to be focused. null: Hyprland's default, `false`.
focus_on_activate: ?bool = null,
/// Whether mouse moving into a different monitor should focus it. null: Hyprland's default, `true`.
mouse_move_focuses_monitor: ?bool = null,
/// If true, will allow you to restart a lockscreen app in case it crashes. null: Hyprland's default, `false`.
allow_session_lock_restore: ?bool = null,
/// Keep rendering workspaces below your lockscreen. null: Hyprland's default, `false`.
session_lock_xray: ?bool = null,
/// Enable blur for lockscreen. You probably want to enable `session_lock_xray`. null: Hyprland's default, `false`.
session_lock_blur: ?bool = null,
/// Change the background color. null: Hyprland's default, `#111111ff`.
background_color: ?kosm.Color = null,
/// Close the special workspace if the last window is removed. null: Hyprland's default, `true`.
close_special_on_empty: ?bool = null,
/// If there is a fullscreen or maximized window, decide whether a tiled window requested to focus should replace it. null: Hyprland's default, `exit_fullscreen`.
on_focus_under_fullscreen: ?enum(i64) { ignore = 0, take_over = 1, exit_fullscreen = 2 } = null,
/// Whether closing a fullscreen window makes the next focused window to be fullscreened. null: Hyprland's default, `disable`.
exit_window_retains_fullscreen: ?enum(i64) { disable = 0, enable = 1, only_when_grouped = 2, only_when_nongrouped = 3 } = null,
/// Windows open on the workspace they were launched on: for the first window only (`single_shot`), or for every window of the process (`persistent`). null: Hyprland's default, `single_shot`.
initial_workspace_tracking: ?enum(i64) {
    disabled = 0,
    single_shot = 1,
    persistent = 2,
    pub const numbered = true;
} = null,
/// The time in seconds a window has to open on its invoked workspace before the tracking token expires. 1..3600. null: Hyprland's default, `10`.
initial_workspace_token_timeout: ?i64 = null,
/// Whether to enable middle-click-paste (aka primary selection). null: Hyprland's default, `true`.
middle_click_paste: ?bool = null,
/// The maximum limit for renderunfocused windows' fps in the background. 1..120. null: Hyprland's default, `15`.
render_unfocused_fps: ?i64 = null,
/// Disable the warning if XDG environment is externally managed. null: Hyprland's default, `false`.
disable_xdg_env_checks: ?bool = null,
/// Disable the warning if hyprland-guiutils is missing. null: Hyprland's default, `false`.
disable_hyprland_guiutils_check: ?bool = null,
/// Whether to disable the warning about not using start-hyprland. null: Hyprland's default, `false`.
disable_watchdog_warning: ?bool = null,
/// The delay in ms after the lockdead screen appears. 0..5000. null: Hyprland's default, `1000`.
lockdead_screen_delay: ?i64 = null,
/// Whether to enable the ANR (app not responding) dialog when your apps hang. null: Hyprland's default, `true`.
enable_anr_dialog: ?bool = null,
/// Number of missed pings before showing the ANR dialog. 1..20. null: Hyprland's default, `5`.
anr_missed_pings: ?i64 = null,
/// Forces 8 bit screencopy. null: Hyprland's default, `true`.
screencopy_force_8b: ?bool = null,
/// Disables notification popup when a monitor fails to set a suitable scale. null: Hyprland's default, `false`.
disable_scale_notification: ?bool = null,
/// Whether to apply minsize and maxsize rules to tiled windows. null: Hyprland's default, `false`.
size_limits_tiled: ?bool = null,
/// Path to custom wav/ogg system bell. `none` or an empty string mute it. `default` uses the system's current one. null: Hyprland's default, `default`.
bell_sound: ?[]const u8 = null,
/// Whether new floating windows must be placed fully/partially on-screen. null: Hyprland's default, `2`.
new_float_force_onscreen: ?i64 = null,
/// Whether existing floating windows must remain fully/partially on-screen. null: Hyprland's default, `0`.
float_force_onscreen: ?i64 = null,

/// Hyprland's `misc.col` options.
pub const Col = @import("misc/Col.zig");
