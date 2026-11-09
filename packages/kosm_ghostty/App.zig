//! ghostty's settings: every option of its config, named like ghostty's options
//! (`font-size` is `font_size`). ghostty's docs have no sections, so neither does the app.
//! `generate` writes the set ones to `file`, which ghostty's config includes
//! (`config-file = kosm`); null options are left to ghostty's defaults.

const App = @This();

const std = @import("std");
const kosm = @import("kosm");
const values = @import("values.zig");
const settings = @import("settings.zig");

/// The file kosm owns; ghostty's config includes it. Default: `~/.config/ghostty/kosm`.
file: []const u8 = "~/.config/ghostty/kosm",
/// How values are spelled, e.g. `.color = .hex_upper`. Null fields take the ghostty
/// adapter's: `#rrggbb`, `true`/`false`, then kosm's 6 float decimals.
format: kosm.Format = .{},
/// Derives `palette[8]`..`palette[15]` from `palette[0]`..`palette[7]` when they are null.
/// null: they are not derived. `from`: the theme's `lightness.bright`.
bright: ?kosm.Modifier = null,
/// Writes `keybind = clear` before `keybind`, removing every binding made before it, ghostty's
/// defaults included. kosm's name for that line, since it has no trigger. Default: false.
keybind_clear: bool = false,
/// Options the app doesn't cover, written after its own: `.{ .path = "future-option",
/// .value = .{ .boolean = true } }`. A path is one option named as in ghostty's config. One that
/// repeats a set option or another extra fails the apply, unless ghostty reads that option more
/// than once (`repeatable`, e.g. `keybind`). Default: none.
extra: []const kosm.Setting = &.{},

/// Set Ghostty's graphical user interface language to a language other than the system default language. null: ghostty's default.
language: ?[]const u8 = null,
/// The font families to use, in order; later ones are fallbacks. Each is written as its own line. Empty: ghostty's default.
font_family: []const []const u8 = &.{},
/// The font families for bold text, like `font_family`. Each is written as its own line. Empty: ghostty's default.
font_family_bold: []const []const u8 = &.{},
/// The font families for italic text, like `font_family`. Each is written as its own line. Empty: ghostty's default.
font_family_italic: []const []const u8 = &.{},
/// The font families for bold italic text, like `font_family`. Each is written as its own line. Empty: ghostty's default.
font_family_bold_italic: []const []const u8 = &.{},
/// The named font style (as the font advertises it) for regular text, or `.disabled`. null: ghostty's default, `default`.
font_style: ?values.FontStyle = null,
/// The named font style for bold text, or `.disabled`. null: ghostty's default, `default`.
font_style_bold: ?values.FontStyle = null,
/// The named font style for italic text, or `.disabled`. null: ghostty's default, `default`.
font_style_italic: ?values.FontStyle = null,
/// The named font style for bold italic text, or `.disabled`. null: ghostty's default, `default`.
font_style_bold_italic: ?values.FontStyle = null,
/// Control whether Ghostty should synthesize a style if the requested style is not available in the specified font-family. null: ghostty's default, `bold,italic,bold-italic`.
font_synthetic_style: ?values.SyntheticStyle = null,
/// Font features to apply (`-calt`, `+ss01`, `cv01=2`), one per line. Each is written as its own line. Empty: ghostty's default.
font_feature: []const []const u8 = &.{},
/// Font size in points. null: ghostty's default, `12`.
font_size: ?f64 = null,
/// Variable font axis values for regular text (`wght=800`). Each is written as its own line. Empty: ghostty's default.
font_variation: []const values.FontVariation = &.{},
/// Variable font axis values for bold text. Each is written as its own line. Empty: ghostty's default.
font_variation_bold: []const values.FontVariation = &.{},
/// Variable font axis values for italic text. Each is written as its own line. Empty: ghostty's default.
font_variation_italic: []const values.FontVariation = &.{},
/// Variable font axis values for bold italic text. Each is written as its own line. Empty: ghostty's default.
font_variation_bold_italic: []const values.FontVariation = &.{},
/// Force one or a range of Unicode codepoints to map to a specific named font. Each is written as its own line. Empty: ghostty's default.
font_codepoint_map: []const values.CodepointMap = &.{},
/// Map specific Unicode codepoints to replacement values when copying text to clipboard. Each is written as its own line. Empty: ghostty's default.
clipboard_codepoint_map: []const values.ClipboardCodepointMap = &.{},
/// Draw fonts with a thicker stroke, if supported. null: ghostty's default, `false`.
font_thicken: ?bool = null,
/// Strength of thickening when `font-thicken` is enabled. null: ghostty's default, `255`.
font_thicken_strength: ?u8 = null,
/// Locations to break font shaping into multiple runs. null: ghostty's default, `cursor`.
font_shaping_break: ?values.FontShapingBreak = null,
/// What color space to use when performing alpha blending. null: ghostty's default, `linear-corrected`.
alpha_blending: ?enum { native, linear, linear_corrected } = null,
/// Adjusts the cell width by pixels or a percentage. null: ghostty's default.
adjust_cell_width: ?values.Adjustment = null,
/// Adjusts the cell height by pixels or a percentage; text stays centered vertically. null: ghostty's default.
adjust_cell_height: ?values.Adjustment = null,
/// Distance in pixels or percentage adjustment from the bottom of the cell to the text baseline. null: ghostty's default.
adjust_font_baseline: ?values.Adjustment = null,
/// Distance in pixels or percentage adjustment from the top of the cell to the top of the underline. null: ghostty's default.
adjust_underline_position: ?values.Adjustment = null,
/// Thickness in pixels of the underline. null: ghostty's default.
adjust_underline_thickness: ?values.Adjustment = null,
/// Distance in pixels or percentage adjustment from the top of the cell to the top of the strikethrough. null: ghostty's default.
adjust_strikethrough_position: ?values.Adjustment = null,
/// Thickness in pixels or percentage adjustment of the strikethrough. null: ghostty's default.
adjust_strikethrough_thickness: ?values.Adjustment = null,
/// Distance in pixels or percentage adjustment from the top of the cell to the top of the overline. null: ghostty's default.
adjust_overline_position: ?values.Adjustment = null,
/// Thickness in pixels or percentage adjustment of the overline. null: ghostty's default.
adjust_overline_thickness: ?values.Adjustment = null,
/// Thickness in pixels or percentage adjustment of the bar cursor and outlined rect cursor. null: ghostty's default.
adjust_cursor_thickness: ?values.Adjustment = null,
/// Height in pixels or percentage adjustment of the cursor. null: ghostty's default.
adjust_cursor_height: ?values.Adjustment = null,
/// Thickness in pixels or percentage adjustment of box drawing characters. null: ghostty's default.
adjust_box_thickness: ?values.Adjustment = null,
/// Height in pixels or percentage adjustment of maximum height for nerd font icons. null: ghostty's default.
adjust_icon_height: ?values.Adjustment = null,
/// The method to use for calculating the cell width of a grapheme cluster. null: ghostty's default, `unicode`.
grapheme_width_method: ?enum { legacy, unicode } = null,
/// FreeType load flags to enable. null: ghostty's default, `hinting,no-force-autohint,no-monochrome,autohint,light`.
freetype_load_flags: ?values.FreetypeLoadFlags = null,
/// A theme by name or absolute path, or one theme each for light and dark mode. null: ghostty's default.
theme: ?values.Theme = null,
/// Background color for the window. null: ghostty's default, `#282c34`.
background: ?kosm.Color = null,
/// Foreground color for the window. null: ghostty's default, `#ffffff`.
foreground: ?kosm.Color = null,
/// Background image for the terminal. null: ghostty's default.
background_image: ?[]const u8 = null,
/// Background image opacity, multiplied with `background_opacity`. null: ghostty's default, `1`.
background_image_opacity: ?f64 = null,
/// Background image position. null: ghostty's default, `center`.
background_image_position: ?enum { top_left, top_center, top_right, center_left, center, center_right, bottom_left, bottom_center, bottom_right } = null,
/// How the background image is scaled to the window. null: ghostty's default, `contain`.
background_image_fit: ?enum { contain, cover, stretch, none } = null,
/// Whether to repeat the background image or not. null: ghostty's default, `false`.
background_image_repeat: ?bool = null,
/// The foreground color for selected text. null: ghostty's default.
selection_foreground: ?values.CellColor = null,
/// The background color for selected text. null: ghostty's default.
selection_background: ?values.CellColor = null,
/// Whether to clear selected text when typing. null: ghostty's default, `true`.
selection_clear_on_typing: ?bool = null,
/// Whether to clear selected text after copying. null: ghostty's default, `false`.
selection_clear_on_copy: ?bool = null,
/// Characters that mark word boundaries when selecting by word. null: ghostty's default, spaces, quotes, brackets and shell punctuation.
selection_word_chars: ?[]const u8 = null,
/// The minimum contrast ratio between the foreground and background colors. null: ghostty's default, `1`.
minimum_contrast: ?f64 = null,
/// The 256 terminal colors by index; 0..15 are the ANSI colors, 8..15 their bright forms.
/// `from` sets 0..7 from the wheel and null 8..15 derive through `bright`; the rest
/// are ghostty's (see `palette_generate`).
palette: [256]?kosm.Color = @splat(null),
/// Whether to generate the extended 256 color palette (16..255) from the base 16 colors. null: ghostty's default, `false`.
palette_generate: ?bool = null,
/// Invert the palette colors generated when `palette-generate` is enabled, so that the colors go in reverse order. null: ghostty's default, `false`.
palette_harmonious: ?bool = null,
/// The color of the cursor. null: ghostty's default.
cursor_color: ?values.CellColor = null,
/// The opacity level (opposite of transparency) of the cursor. null: ghostty's default, `1`.
cursor_opacity: ?f64 = null,
/// The style of the cursor. null: ghostty's default, `block`.
cursor_style: ?enum {
    block,
    bar,
    underline,
    block_hollow,
    pub const underscored = true;
} = null,
/// Sets the default blinking state of the cursor. null: ghostty's default.
cursor_style_blink: ?bool = null,
/// The color of the text under the cursor. null: ghostty's default.
cursor_text: ?values.CellColor = null,
/// Enables the ability to move the cursor at prompts by clicking on a location in the prompt text. null: ghostty's default, `true`.
cursor_click_to_move: ?bool = null,
/// Hide the mouse immediately when typing. null: ghostty's default, `false`.
mouse_hide_while_typing: ?bool = null,
/// When to scroll the surface to the bottom. null: ghostty's default, `keystroke,no-output`.
scroll_to_bottom: ?values.ScrollToBottom = null,
/// Determines whether running programs can detect the shift key pressed with a mouse click. null: ghostty's default, `false`.
mouse_shift_capture: ?union(enum) { boolean: bool, always, never } = null,
/// Enable or disable mouse reporting. null: ghostty's default, `true`.
mouse_reporting: ?bool = null,
/// Multiplier for scrolling distance with the mouse wheel. null: ghostty's default, `precision:1,discrete:3`.
mouse_scroll_multiplier: ?values.MouseScrollMultiplier = null,
/// The opacity level (opposite of transparency) of the background. null: the background's alpha when it is below 1, else ghostty's default, `1`.
background_opacity: ?f64 = null,
/// Applies background opacity to cells with an explicit background color set. null: ghostty's default, `false`.
background_opacity_cells: ?bool = null,
/// How much to blur the background when `background_opacity` is below 1. null: ghostty's default, `false`.
background_blur: ?values.BackgroundBlur = null,
/// The opacity level (opposite of transparency) of an unfocused split. null: ghostty's default, `0.7`.
unfocused_split_opacity: ?f64 = null,
/// The color to dim the unfocused split. null: ghostty's default.
unfocused_split_fill: ?kosm.Color = null,
/// The color of the split divider. null: ghostty's default.
split_divider_color: ?kosm.Color = null,
/// Control when Ghostty preserves a zoomed split. null: ghostty's default, `no-navigation`.
split_preserve_zoom: ?values.SplitPreserveZoom = null,
/// The foreground color for search matches. null: ghostty's default, `#000000`.
search_foreground: ?kosm.Color = null,
/// The background color for search matches. null: ghostty's default, `#ffe082`.
search_background: ?kosm.Color = null,
/// The foreground color for the selected search match. null: ghostty's default, `#000000`.
search_selected_foreground: ?kosm.Color = null,
/// The background color for the selected search match. null: ghostty's default, `#f2a57e`.
search_selected_background: ?kosm.Color = null,
/// The command to run, usually a shell. null: ghostty's default.
command: ?[]const u8 = null,
/// This is the same as "command", but only applies to the first terminal surface created when Ghostty starts. null: ghostty's default.
initial_command: ?[]const u8 = null,
/// Controls when command finished notifications are sent. null: ghostty's default, `never`.
notify_on_command_finish: ?enum { never, unfocused, always } = null,
/// If command finished notifications are enabled, this controls how the user is notified. null: ghostty's default, `bell,no-notify`.
notify_on_command_finish_action: ?values.NotifyOnCommandFinishAction = null,
/// How long a command must run before its finish is notified. null: ghostty's default, `5s`.
notify_on_command_finish_after: ?values.Duration = null,
/// Extra environment variables to pass to commands launched in a terminal surface. Each is written as its own line. Empty: ghostty's default.
env: []const values.Env = &.{},
/// Data to send as input to the command on startup. Each is written as its own line. Empty: ghostty's default.
input: []const values.Input = &.{},
/// If true, keep the terminal open after the command exits. null: ghostty's default, `false`.
wait_after_command: ?bool = null,
/// The number of milliseconds of runtime below which we consider a process exit to be abnormal. null: ghostty's default, `250`.
abnormal_command_exit_runtime: ?u32 = null,
/// The size of the scrollback buffer in bytes. null: ghostty's default, `50000000`.
scrollback_limit_bytes: ?values.Limit = null,
/// The maximum number of lines of scrollback to retain. null: ghostty's default, `unlimited`.
scrollback_limit_lines: ?values.Limit = null,
/// Whether to compress scrollback pages while the terminal is idle. null: ghostty's default, `true`.
scrollback_compression: ?bool = null,
/// Control when the scrollbar is shown to scroll the scrollback buffer. null: ghostty's default, `system`.
scrollbar: ?enum { system, never } = null,
/// Match a regular expression against the terminal text and associate clicking it with an action. null: ghostty's default, `true`.
link_url: ?bool = null,
/// Enable hyperlinks created with the OSC 8 escape sequence. null: ghostty's default, `true`.
link_osc8: ?bool = null,
/// Show link previews for a matched URL. null: ghostty's default, `true`.
link_previews: ?union(enum) { boolean: bool, osc8 } = null,
/// Whether to start the window in a maximized state. null: ghostty's default, `false`.
maximize: ?bool = null,
/// Start new windows in fullscreen. null: ghostty's default, `false`.
fullscreen: ?union(enum) { boolean: bool, non_native, non_native_visible_menu, non_native_padded_notch } = null,
/// The title Ghostty will use for the window. null: ghostty's default.
title: ?[]const u8 = null,
/// The setting that will change the application class value. null: ghostty's default.
class: ?[]const u8 = null,
/// This controls the instance name field of the `WM_CLASS` X11 property when running under X11. null: ghostty's default.
x11_instance_name: ?[]const u8 = null,
/// The directory to change to after starting the command. null: ghostty's default.
working_directory: ?values.WorkingDirectory = null,
/// Key bindings, written in order after ghostty's defaults, so a later one for the same
/// trigger wins: `.{ .trigger = "ctrl+a>n", .action = .new_window }`. Empty: ghostty's defaults.
keybind: []const values.Keybind = &.{},
/// Remap modifier keys within Ghostty. Each is written as its own line. Empty: ghostty's default.
key_remap: []const values.KeyRemap = &.{},
/// Horizontal window padding in points, one value or left and right. null: ghostty's default, `2`.
window_padding_x: ?values.Padding = null,
/// Vertical window padding in points, one value or top and bottom. null: ghostty's default, `2`.
window_padding_y: ?values.Padding = null,
/// The viewport dimensions are usually not perfectly divisible by the cell size. null: ghostty's default, `false`.
window_padding_balance: ?union(enum) { boolean: bool, equal } = null,
/// The color of the padding area of the window. null: ghostty's default, `background`.
window_padding_color: ?enum { background, extend, extend_always } = null,
/// Synchronize rendering with the screen refresh rate. null: ghostty's default, `true`.
window_vsync: ?bool = null,
/// If true, new windows will inherit the working directory of the previously focused window. null: ghostty's default, `true`.
window_inherit_working_directory: ?bool = null,
/// If true, new tabs will inherit the working directory of the previously focused tab. null: ghostty's default, `true`.
tab_inherit_working_directory: ?bool = null,
/// If true, new split panes will inherit the working directory of the previously focused split. null: ghostty's default, `true`.
split_inherit_working_directory: ?bool = null,
/// If true, new windows and tabs will inherit the font size of the previously focused window. null: ghostty's default, `true`.
window_inherit_font_size: ?bool = null,
/// Configure a preference for window decorations. null: ghostty's default, `auto`.
window_decoration: ?enum { none, auto, client, server } = null,
/// The font that will be used for the application's window and tab titles. null: ghostty's default.
window_title_font_family: ?[]const u8 = null,
/// The text that will be displayed in the subtitle of the window. null: ghostty's default, `false`.
window_subtitle: ?union(enum) { boolean: bool, working_directory } = null,
/// The theme to use for the windows. null: ghostty's default, `auto`.
window_theme: ?enum { auto, system, light, dark, ghostty } = null,
/// The color space to use when interpreting terminal colors. null: ghostty's default, `srgb`.
window_colorspace: ?enum { srgb, display_p3 } = null,
/// The initial window height in grid cells; needs `window_width` too. null: ghostty's default, `0`.
window_height: ?u32 = null,
/// The initial window width in grid cells; needs `window_height` too. null: ghostty's default, `0`.
window_width: ?u32 = null,
/// The starting window x position in pixels; needs `window_position_y` too (macOS only). null: ghostty's default.
window_position_x: ?i32 = null,
/// The starting window y position in pixels; needs `window_position_x` too (macOS only). null: ghostty's default.
window_position_y: ?i32 = null,
/// Whether to enable saving and restoring window state. null: ghostty's default, `default`.
window_save_state: ?enum { default, never, always } = null,
/// Resize the window in discrete increments of the focused surface's cell size. null: ghostty's default, `false`.
window_step_resize: ?bool = null,
/// The position where new tabs are created. null: ghostty's default, `current`.
window_new_tab_position: ?enum { current, end } = null,
/// Whether to show the tab bar. null: ghostty's default, `auto`.
window_show_tab_bar: ?enum { always, auto, never } = null,
/// Background color for the window titlebar. null: ghostty's default.
window_titlebar_background: ?kosm.Color = null,
/// Foreground color for the window titlebar. null: ghostty's default.
window_titlebar_foreground: ?kosm.Color = null,
/// Controls when drag handles are shown over splits, allowing splits to be rearranged with mouse controls. null: ghostty's default, `auto`.
drag_handle: ?enum { always, auto, never } = null,
/// This controls when resize overlays are shown. null: ghostty's default, `after-first`.
resize_overlay: ?enum { always, never, after_first } = null,
/// If resize overlays are enabled, this controls the position of the overlay. null: ghostty's default, `center`.
resize_overlay_position: ?enum { center, top_left, top_center, top_right, bottom_left, bottom_center, bottom_right } = null,
/// If resize overlays are enabled, this controls how long the overlay is visible on the screen before it is hidden. null: ghostty's default, `750ms`.
resize_overlay_duration: ?values.Duration = null,
/// If true, when there are multiple split panes, the mouse selects the pane that is focused. null: ghostty's default, `false`.
focus_follows_mouse: ?bool = null,
/// Whether programs in the terminal may read the clipboard (OSC 52). null: ghostty's default, `ask`.
clipboard_read: ?enum { allow, deny, ask } = null,
/// Whether programs in the terminal may write the clipboard (OSC 52). null: ghostty's default, `allow`.
clipboard_write: ?enum { allow, deny, ask } = null,
/// The largest single clipboard write a program may make through OSC 5522, in bytes. null: ghostty's default, `67108864`.
clipboard_write_limit_bytes: ?values.Limit = null,
/// Trims trailing whitespace on data that is copied to the clipboard. null: ghostty's default, `true`.
clipboard_trim_trailing_spaces: ?bool = null,
/// Require confirmation before pasting text that appears unsafe. null: ghostty's default, `true`.
clipboard_paste_protection: ?bool = null,
/// If true, bracketed pastes will be considered safe. null: ghostty's default, `true`.
clipboard_paste_bracketed_safe: ?bool = null,
/// Enables or disabled title reporting (CSI 21 t). null: ghostty's default, `false`.
title_report: ?bool = null,
/// The bytes image protocols (such as kitty's) may use per screen; 0 disables them. null: ghostty's default, `320000000`.
image_storage_limit: ?u32 = null,
/// Whether to automatically copy selected text to the clipboard. null: ghostty's default, `primary`.
copy_on_select: ?enum { none, primary, clipboard, both } = null,
/// The action to take when the user right-clicks on the terminal surface. null: ghostty's default, `context-menu`.
right_click_action: ?enum { context_menu, paste, copy, copy_or_paste, ignore } = null,
/// The action to take when the user middle-clicks on the terminal surface. null: ghostty's default, `primary-paste`.
middle_click_action: ?enum { primary_paste, clipboard_paste, ignore } = null,
/// The time in milliseconds between clicks to consider a click a repeat (double, triple, etc.) or an entirely new single click. null: ghostty's default, `0`.
click_repeat_interval: ?u32 = null,
/// Additional configuration files to read. Each is written as its own line. Empty: ghostty's default.
config_file: []const []const u8 = &.{},
/// Confirms that a surface should be closed before closing it. null: ghostty's default, `true`.
confirm_close_surface: ?union(enum) { boolean: bool, always } = null,
/// Whether or not to quit after the last surface is closed. null: ghostty's default, `true`.
quit_after_last_window_closed: ?bool = null,
/// Controls how long Ghostty will stay running after the last open surface has been closed. null: ghostty's default.
quit_after_last_window_closed_delay: ?values.Duration = null,
/// This controls whether an initial window is created when Ghostty is run. null: ghostty's default, `true`.
initial_window: ?bool = null,
/// The duration that undo operations remain available. null: ghostty's default, `5s`.
undo_timeout: ?values.Duration = null,
/// The position of the "quick" terminal window. null: ghostty's default, `top`.
quick_terminal_position: ?enum { top, bottom, left, right, center } = null,
/// The size of the quick terminal, as a percentage of the screen or in pixels. null: ghostty's default.
quick_terminal_size: ?values.QuickTerminalSize = null,
/// The layer of the quick terminal window (GTK Wayland only). null: ghostty's default, `top`.
gtk_quick_terminal_layer: ?enum { overlay, top, bottom, background } = null,
/// The namespace for the quick terminal window. null: ghostty's default, `ghostty-quick-terminal`.
gtk_quick_terminal_namespace: ?[]const u8 = null,
/// The screen where the quick terminal should show up. null: ghostty's default, `main`.
quick_terminal_screen: ?enum { main, mouse, macos_menu_bar } = null,
/// Duration (in seconds) of the quick terminal enter and exit animation. null: ghostty's default, `0.2`.
quick_terminal_animation_duration: ?f64 = null,
/// Automatically hide the quick terminal when focus shifts to another window. null: ghostty's default, `false`.
quick_terminal_autohide: ?bool = null,
/// This configuration option determines the behavior of the quick terminal when switching between macOS spaces. null: ghostty's default, `move`.
quick_terminal_space_behavior: ?enum { move, remain } = null,
/// Determines under which circumstances that the quick terminal should receive keyboard input. null: ghostty's default, `on-demand`.
quick_terminal_keyboard_interactivity: ?enum { none, on_demand, exclusive } = null,
/// Whether to enable shell integration auto-injection or not. null: ghostty's default, `detect`.
shell_integration: ?enum { none, detect, bash, elvish, fish, nushell, zsh } = null,
/// Shell integration features to enable. null: ghostty's default, `cursor,no-sudo,title,no-ssh-env,no-ssh-terminfo,path`.
shell_integration_features: ?values.ShellIntegrationFeatures = null,
/// Custom entries of the command palette, added to ghostty's own. Empty: only ghostty's.
command_palette_entry: []const values.CommandPaletteEntry = &.{},
/// Sets the reporting format for OSC sequences that request color information. null: ghostty's default, `16-bit`.
osc_color_report_format: ?enum { none, @"8_bit", @"16_bit" } = null,
/// If true, allows the "KAM" mode (ANSI mode 2) to be used within the terminal. null: ghostty's default, `false`.
vt_kam_allowed: ?bool = null,
/// If true, allows the running program to resize the window using the xterm `CSI 8 ; rows ; columns t` escape sequence. null: ghostty's default, `false`.
vt_window_resize_allowed: ?bool = null,
/// Enables or disables checksum reporting (DECRQCRA, `CSI Pi ; Pg ; Pt ; Pl ; Pb ; Pr * y`). null: ghostty's default, `false`.
vt_xt_checksum_report: ?bool = null,
/// How the checksum reported for DECRQCRA (see `vt-xt-checksum-report`) is calculated. null: ghostty's default, `negate,attributes,trim,no-undrawn,no-full`.
vt_xt_checksum_extension: ?values.ChecksumExtension = null,
/// Custom shaders to run after the default shaders. Each is written as its own line. Empty: ghostty's default.
custom_shader: []const []const u8 = &.{},
/// If `true` (default), the focused terminal surface will run an animation loop when custom shaders are used. null: ghostty's default, `true`.
custom_shader_animation: ?union(enum) { boolean: bool, always } = null,
/// Bell features to enable if bell support is available in your runtime. null: ghostty's default, `no-system,no-audio,attention,title,no-border`.
bell_features: ?values.BellFeatures = null,
/// If `audio` is an enabled bell feature, this is a path to an audio file. null: ghostty's default.
bell_audio_path: ?[]const u8 = null,
/// If `audio` is an enabled bell feature, this is the volume to play the audio file at (relative to the system volume). null: ghostty's default, `0.5`.
bell_audio_volume: ?f64 = null,
/// Control the in-app notifications that Ghostty shows. null: ghostty's default, `clipboard-copy,config-reload`.
app_notifications: ?values.AppNotifications = null,
/// Makes macOS fullscreen non-native: no animation and no new space. null: ghostty's default, `false`.
macos_non_native_fullscreen: ?union(enum) { boolean: bool, visible_menu, padded_notch } = null,
/// Whether the window buttons in the macOS titlebar are visible. null: ghostty's default, `visible`.
macos_window_buttons: ?enum { visible, hidden } = null,
/// The style of the macOS titlebar. null: ghostty's default, `transparent`.
macos_titlebar_style: ?enum { native, transparent, tabs, hidden } = null,
/// Whether the proxy icon in the macOS titlebar is visible. null: ghostty's default, `visible`.
macos_titlebar_proxy_icon: ?enum { visible, hidden } = null,
/// Controls the windowing behavior when dropping a file or folder onto the Ghostty icon in the macOS dock. null: ghostty's default, `new-tab`.
macos_dock_drop_behavior: ?enum { new_tab, new_window } = null,
/// macOS doesn't have a distinct "alt" key and instead has the "option" key which behaves slightly differently. null: ghostty's default.
macos_option_as_alt: ?union(enum) { boolean: bool, left, right } = null,
/// Whether to enable the macOS window shadow. null: ghostty's default, `true`.
macos_window_shadow: ?bool = null,
/// If true, the macOS icon in the dock and app switcher will be hidden. null: ghostty's default, `never`.
macos_hidden: ?enum { never, always } = null,
/// Enables macOS Secure Input when a password prompt is detected. null: ghostty's default, `true`.
macos_auto_secure_input: ?bool = null,
/// If true, Ghostty will show a graphical indication when secure input is enabled. null: ghostty's default, `true`.
macos_secure_input_indication: ?bool = null,
/// If true, Ghostty exposes and handles the built-in AppleScript dictionary on macOS. null: ghostty's default, `true`.
macos_applescript: ?bool = null,
/// Customize the macOS app icon. null: ghostty's default, `official`.
macos_icon: ?enum { official, blueprint, chalkboard, microchip, glass, holographic, paper, retro, xray, custom, custom_style } = null,
/// The absolute path to the custom icon file. null: ghostty's default.
macos_custom_icon: ?[]const u8 = null,
/// The material to use for the frame of the macOS app icon. null: ghostty's default, `aluminum`.
macos_icon_frame: ?enum { aluminum, beige, plastic, chrome } = null,
/// The color of the ghost in the macOS app icon. null: ghostty's default.
macos_icon_ghost_color: ?kosm.Color = null,
/// The colors of the gradient on the screen of the macOS icon, bottom first. null: ghostty's default.
macos_icon_screen_color: ?[]const kosm.Color = null,
/// Whether macOS Shortcuts are allowed to control Ghostty. null: ghostty's default, `ask`.
macos_shortcuts: ?enum { allow, deny, ask } = null,
/// Put every surface (tab, split, window) into a transient `systemd` scope. null: ghostty's default, `single-instance`.
linux_cgroup: ?enum { never, always, single_instance } = null,
/// Memory limit for any individual terminal process (tab, split, window, etc.) in bytes. null: ghostty's default.
linux_cgroup_memory_limit: ?u64 = null,
/// Number of processes limit for any individual terminal process (tab, split, window, etc.). null: ghostty's default.
linux_cgroup_processes_limit: ?u64 = null,
/// Whether failing to create the `systemd` scope for `linux_cgroup` is an error. null: ghostty's default, `false`.
linux_cgroup_hard_fail: ?bool = null,
/// Enable or disable GTK's OpenGL debugging logs. null: ghostty's default, `false`.
gtk_opengl_debug: ?bool = null,
/// Whether new `ghostty` processes open a window in the running instance. null: ghostty's default, `detect`.
gtk_single_instance: ?union(enum) { boolean: bool, detect } = null,
/// When enabled, the full GTK titlebar is displayed instead of your window manager's simple titlebar. null: ghostty's default, `true`.
gtk_titlebar: ?bool = null,
/// Determines the side of the screen that the GTK tab bar will stick to. null: ghostty's default, `top`.
gtk_tabs_location: ?enum { top, bottom, hidden } = null,
/// Shows each tab close button at the start of the tab and its icon at the end. null: ghostty's default, `false`.
gtk_tabs_inverted: ?bool = null,
/// Hides the titlebar while the window is maximized. null: ghostty's default, `false`.
gtk_titlebar_hide_when_maximized: ?bool = null,
/// Determines the appearance of the top and bottom bars tab bar. null: ghostty's default, `raised`.
gtk_toolbar_style: ?enum { flat, raised, raised_border } = null,
/// The style of the GTK titlebar. null: ghostty's default, `native`.
gtk_titlebar_style: ?enum { native, tabs } = null,
/// Whether GTK tabs fill the available space. null: ghostty's default, `true`.
gtk_wide_tabs: ?bool = null,
/// If `true` (default), then two-finger horizontal scrolling on a touchpad will switch between tabs. null: ghostty's default, `true`.
gtk_horizontal_tab_scroll: ?bool = null,
/// Custom CSS files to be loaded. Each is written as its own line. Empty: ghostty's default.
gtk_custom_css: []const []const u8 = &.{},
/// Whether programs in the terminal can show desktop notifications (OSC 9, OSC 777). null: ghostty's default, `true`.
desktop_notifications: ?bool = null,
/// Whether programs in the terminal can show progress bars (OSC 9;4). null: ghostty's default, `true`.
progress_style: ?bool = null,
/// Modifies the color used for bold text in the terminal. null: ghostty's default.
bold_color: ?values.BoldColor = null,
/// The opacity level (opposite of transparency) of the faint text. null: ghostty's default, `0.5`.
faint_opacity: ?f64 = null,
/// This will be used to set the `TERM` environment variable. null: ghostty's default, `xterm-ghostty`.
term: ?[]const u8 = null,
/// String to send when we receive `ENQ` (`0x05`) from the command that we are running. null: ghostty's default.
enquiry_response: ?[]const u8 = null,
/// Configures the low-level API to use for async IO, eventing, etc. null: ghostty's default, `auto`.
async_backend: ?enum {
    auto,
    epoll,
    io_uring,
    kqueue,
    pub const underscored = true;
} = null,
/// Control the auto-update functionality of Ghostty. null: ghostty's default.
auto_update: ?enum { off, check, download } = null,
/// The release channel to use for auto-updates. null: ghostty's default.
auto_update_channel: ?enum { stable, tip } = null,

/// Colors from the theme: foreground and background from white and black (swapped in
/// light mode), the 8 ANSI colors from the wheel, selection from the `emphasis.strong` and
/// `state.selected` variations. Every other option is left to ghostty.
pub fn from(theme: kosm.Theme) App {
    const palette = theme.palette;
    const variations = theme.variations;
    const foreground = if (theme.mode == .dark) palette.white else palette.black;
    const background = if (theme.mode == .dark) palette.black else palette.white;
    var app: App = .{ .bright = variations.lightness.bright };

    app.foreground = foreground;
    app.background = background;
    app.selection_foreground = .{ .color = variations.emphasis.strong.apply(foreground) };
    app.selection_background = .{ .color = variations.state.selected.apply(background) };
    for ([_]kosm.Color{ palette.black, palette.red, palette.green, palette.yellow, palette.blue, palette.magenta, palette.cyan, palette.white }, 0..) |color, index| {
        app.palette[index] = color;
    }
    return app;
}

/// Makes every running ghostty re-read its config by sending it SIGUSR2. With no ghostty
/// running, kosm only warns.
pub fn reload(self: App, reloader: *kosm.Reloader) !void {
    _ = self;
    try reloader.run(&.{ "pkill", "-USR2", "-x", "ghostty" });
}

/// Writes every set option to `file`.
pub fn apply(self: App, output: *kosm.Output) !void {
    const options = try kosm.Setting.leaves(output.allocator, try settings.tree(output.allocator, self.withDerived()));
    const all = try kosm.Setting.withExtras(output, self.file, options, self.extra, .{ .paths = .one_key, .repeatable = repeatable });
    try output.generate(.{ .file = self.file, .lang = "ghostty", .format = self.format }, try kosm.Setting.tree(output.allocator, all));
}

/// Options ghostty reads more than once, each line adding another, so extras may repeat them
///: every option the app holds as a list.
pub const repeatable = blk: {
    @setEvalBranchQuota(20_000);
    var keys: []const []const u8 = &.{};
    for (@typeInfo(App).@"struct".field_names, @typeInfo(App).@"struct".field_types) |name, Field| {
        if (settings.isOwnField(name) or @typeInfo(Field) == .optional) continue;
        keys = keys ++ .{settings.optionName(name)};
    }
    const final = keys;
    break :blk final;
};

/// An 8-bit alpha can't hold 0.5 exactly (`80` is 0.502), so derived opacities are rounded
/// to what the hex digits meant.
const opacity_steps = 100;

/// The number of ANSI colors that have a bright form.
const ansi_colors = 8;

fn roundedAlpha(alpha: f64) f64 {
    return @round(alpha * opacity_steps) / opacity_steps;
}

/// Fills the options that derive from others when left null.
fn withDerived(self: App) App {
    var app = self;
    if (app.background_opacity == null) if (app.background) |background| {
        if (background.alpha < 1) app.background_opacity = roundedAlpha(background.alpha);
    };
    const bright = self.bright orelse return app;
    for (0..ansi_colors) |index| {
        if (app.palette[index + ansi_colors] == null) if (app.palette[index]) |base| {
            app.palette[index + ansi_colors] = bright.apply(base);
        };
    }
    return app;
}

const testing = std.testing;
const adapter = @import("adapter.zig").adapter;

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings = undefined,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output = undefined,

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "ghostty",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn written(fixture: *Fixture) []const u8 {
        return fixture.plan.files.items[0].new;
    }
};

/// Kyanos as `kosm init` ships it, with Ricer's highlight (HSV value +10) as `bright`.
fn kyanosTheme() kosm.Theme {
    var theme = kosm.Theme.from(.{
        .black = kosm.hex("041c2680"),
        .white = kosm.hex("a3c5cc"),
        .red = kosm.hex("80333c"),
        .green = kosm.hex("338051"),
        .yellow = kosm.hex("668033"),
        .blue = kosm.hex("267180"),
        .magenta = kosm.hex("436496"),
        .cyan = kosm.hex("268078"),
    }, .dark);
    theme.variations.lightness.bright = .{ .hsv = .{ .value = 0.10 } };
    return theme;
}

test "Kyanos writes what Ricer's ghostty file holds, plus the selection colors it derives" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var app = from(kyanosTheme());
    app.font_family = &.{ "Maple Mono Normal NFP", "Cascadia Code NF", "Adwaita Mono" };
    app.font_family_bold = &.{"Maple Mono Normal NFP"};
    app.font_family_italic = &.{"Maple Mono Normal NFP"};
    app.font_family_bold_italic = &.{"Maple Mono Normal NFP"};
    app.font_size = 13;
    app.cursor_color = .{ .color = kosm.hex("ffffff") };
    try app.apply(&fixture.output);
    try testing.expectEqual(0, fixture.warnings.items.items.len);

    // ~/.config/ghostty/Ricer, in kosm's spelling: `#` and lowercase hex, no padding in `palette`.
    const ricer = [_][]const u8{
        "font-family = Maple Mono Normal NFP",
        "font-family = Cascadia Code NF",
        "font-family = Adwaita Mono",
        "font-family-bold = Maple Mono Normal NFP",
        "font-family-italic = Maple Mono Normal NFP",
        "font-family-bold-italic = Maple Mono Normal NFP",
        "font-size = 13",
        "palette = 0=#041c26",
        "palette = 1=#80333c",
        "palette = 2=#338051",
        "palette = 3=#668033",
        "palette = 4=#267180",
        "palette = 5=#436496",
        "palette = 6=#268078",
        "palette = 7=#a3c5cc",
        "cursor-color = #ffffff",
        "background = #041c26",
        "foreground = #a3c5cc",
        "background-opacity = 0.5",
    };
    // Ricer rounded RGB to 2 decimals before its HSV math and truncated after it, so kosm's exact
    // bright colors differ from its file by up to 2 per channel.
    const ricer_bright = [_][]const u8{ "082e3f", "993d49", "3d9961", "7a993d", "2d8699", "4d74af", "2d998f", "b7dce5" };
    const max_channel_difference = 2;

    var lines = std.mem.tokenizeScalar(u8, fixture.written(), '\n');
    var line_count: usize = 0;
    while (lines.next()) |line| : (line_count += 1) {
        const in_ricer = for (ricer) |expected| {
            if (std.mem.eql(u8, expected, line)) break true;
        } else false;
        if (!in_ricer and !std.mem.startsWith(u8, line, "selection-") and !isBrightPaletteLine(line)) {
            std.debug.print("not in Ricer: {s}\nwritten:\n{s}\n", .{ line, fixture.written() });
            return error.TestUnexpectedResult;
        }
    }
    try testing.expectEqual(ricer.len + ricer_bright.len + 2, line_count);
    for (ricer_bright, 8..) |expected, index| {
        const written = app.withDerived().palette[index].?.toRgb();
        const ricer_color = (try kosm.Color.parseHex(expected)).toRgb();
        for ([_][2]f64{ .{ written.red, ricer_color.red }, .{ written.green, ricer_color.green }, .{ written.blue, ricer_color.blue } }) |pair| {
            try testing.expect(@abs(@round(pair[0] * 255) - @round(pair[1] * 255)) <= max_channel_difference);
        }
    }
}

fn isBrightPaletteLine(line: []const u8) bool {
    for (8..16) |index| {
        var prefix_buffer: [16]u8 = undefined;
        // "palette = 15=#" is 14 bytes, so the buffer always fits.
        const prefix = std.fmt.bufPrint(&prefix_buffer, "palette = {d}=#", .{index}) catch unreachable;
        if (std.mem.startsWith(u8, line, prefix)) return true;
    }
    return false;
}

test "light mode swaps background and foreground, and set derived options win" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var app = from(kosm.Theme.from(.{ .black = kosm.hex("102840"), .white = kosm.hex("eceff4") }, .light));
    app.palette[9] = kosm.hex("ff0000");
    app.background_opacity = 0.9;
    app.keybind = &.{.{ .trigger = "ctrl+enter", .action = .unbind }};
    try app.apply(&fixture.output);
    const written = fixture.written();
    for ([_][]const u8{
        "background = #eceff4\n",
        "foreground = #102840\n",
        "palette = 9=#ff0000\n",
        "background-opacity = 0.9\n",
        "keybind = ctrl+enter=unbind\n",
    }) |expected| {
        if (std.mem.indexOf(u8, written, expected) == null) {
            std.debug.print("missing:\n{s}\nin:\n{s}\n", .{ expected, written });
            return error.TestExpectedEqual;
        }
    }
    try testing.expect(std.mem.indexOf(u8, written, "palette = 16=") == null);
    try testing.expect(std.mem.indexOf(u8, written, "keybind = clear") == null);
    try testing.expectEqualStrings("~/.config/ghostty/kosm", fixture.plan.files.items[0].display_path);
}

test "App{} writes an empty file, and without bright no bright color is derived" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const empty: App = .{};
    try empty.apply(&fixture.output);
    try testing.expectEqualStrings("", fixture.written());

    var app: App = .{};
    app.palette[1] = kosm.hex("80333c");
    try testing.expectEqual(null, app.withDerived().palette[9]);
}

test "background_opacity follows the background's alpha below 1 and is not written at 1" {
    var app: App = .{ .background = kosm.hex("041c26bf") };
    try testing.expectEqual(0.75, app.withDerived().background_opacity.?);
    app.background = kosm.hex("041c26");
    try testing.expectEqual(null, app.withDerived().background_opacity);
}

test "extras follow the options, repeatable ones as often as given" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var app: App = .{};
    app.font_size = 13;
    app.keybind = &.{.{ .trigger = "ctrl+a", .action = .{ .text = "a" } }};
    app.extra = &.{
        .{ .path = "keybind", .value = .{ .raw = "ctrl+b=new_tab" } },
        .{ .path = "future-option", .value = .{ .boolean = true } },
        .{ .path = "keybind", .value = .{ .raw = "ctrl+c=copy_to_clipboard" } },
    };
    try app.apply(&fixture.output);
    try testing.expectEqualStrings(
        \\font-size = 13
        \\keybind = ctrl+a=text:a
        \\keybind = ctrl+b=new_tab
        \\future-option = true
        \\keybind = ctrl+c=copy_to_clipboard
        \\
    , fixture.written());
}

test "an extra repeating a set option fails naming both" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var app: App = .{};
    app.font_size = 13;
    app.extra = &.{.{ .path = "font-size", .value = .{ .integer = 12 } }};
    try testing.expectError(error.AppFailed, app.apply(&fixture.output));
    try testing.expectEqualStrings("extra 'font-size' and setting 'font-size' write the same key, or one inside the other; keep one", fixture.diagnostics.message());
}
