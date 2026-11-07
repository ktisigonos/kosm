# kosm_ghostty

ghostty for kosm: the `ghostty` adapter (reads and writes ghostty config files, and
`# kosm:begin` blocks in them) and the ghostty app.

The app covers every option of ghostty 1.4's config, named exactly like ghostty's options with
underscores (`ghostty.font_size = 13`). ghostty's docs have no sections, so neither does the app:
every option is a field of `App`. It writes only the options that are set to
`~/.config/ghostty/kosm.ghostty`; everything left `null` (or an empty list) stays ghostty's
default. Make ghostty read it once, at the end of your own config so its values win:

```
config-file = kosm.ghostty
```

`from(theme)` sets the colors (D27): foreground and background from white and black (swapped in
light mode), `palette[0]`..`palette[7]` from the wheel, the selection from the `emphasis.strong`
and `state.selected` variations. `palette[8]`..`palette[15]` derive from those through `bright`,
and `background_opacity` from the background's alpha, unless you set them (D23).

Choices are enums in Zig spelling (`.linear_corrected` for `linear-corrected`). Where ghostty
mixes `true`/`false` with words, the field is a union with a `boolean` member
(`confirm_close_surface = .always` or `.{ .boolean = false }`). Flag lists such as
`bell-features` are structs of `?bool` (`.{ .audio = true, .system = false }` writes
`audio,no-system`); unset flags keep ghostty's defaults. Options ghostty lets you repeat
(`font_family`, `env`, `custom_shader`, ...) are slices, one line each. The types live in
`kosm_ghostty.values`.

Left out: `config-default-files`, which ghostty only reads from the command line, and `link`,
which ghostty can't set yet.

After every apply the app reloads every running ghostty by sending it SIGUSR2
(`pkill -USR2 -x ghostty`, D74). If no ghostty is running, kosm prints a warning and carries on.

## Keybinds

```zig
ghostty.keybind = &.{
    .{ .trigger = "ctrl+enter", .action = .unbind },
    .{ .trigger = "ctrl+a>n", .action = .new_window, .chain = &.{.{ .goto_split = .left }} },
    .{ .trigger = "ctrl+shift+d", .action = .{ .new_split = .right }, .global = true },
    .{ .table = "vim", .trigger = "j", .action = .{ .scroll_page_lines = 1 } },
    .{ .trigger = "ctrl+u", .action = .{ .text = "\x15" } },
};
```

- `trigger` is ghostty's syntax: `+` joins keys held together, `>` joins steps pressed one after
  another (`ctrl+a>n`: Ctrl+A, then N).
- `action` is any of ghostty's actions (`ghostty +list-actions`) with a typed parameter.
  `.text` is plain text, which kosm writes as the Zig string literal ghostty expects. `.raw`
  writes an action kosm doesn't know yet as is (`.{ .raw = "new_action:argument" }`).
- `chain` runs more actions after `action` (`keybind = chain=...` lines).
- `table` puts the binding in a key table; `all`, `global`, `unconsumed` and `performable` are
  ghostty's prefixes.
- `keybind_clear = true` writes `keybind = clear` first, removing ghostty's default bindings.
  It is kosm's name for that line, since it has no trigger.

kosm checks only that a binding fits on one line; ghostty reports a trigger or action it can't
read in its own log.

## App fields

| Field | Default |
|---|---|
| `file` | `~/.config/ghostty/kosm.ghostty` |
| `format` | `.{}`: the ghostty adapter's `#rrggbb` and `true`/`false`, then 6 float decimals (D70) |
| `bright` | the theme's `lightness.bright`; makes `palette[8]`..`palette[15]` from `palette[0]`..`palette[7]` |
| `keybind_clear` | `false`; `true` writes `keybind = clear` before `keybind` |

## Options

| Option | Type | Meaning |
|---|---|---|
| `language` | `?[]const u8` | Set Ghostty's graphical user interface language to a language other than the system default language. null: ghostty's default. |
| `font_family` | `[]const []const u8` | The font families to use, in order; later ones are fallbacks. Each is written as its own line. Empty: ghostty's default. |
| `font_family_bold` | `[]const []const u8` | The font families for bold text, like `font_family`. Each is written as its own line. Empty: ghostty's default. |
| `font_family_italic` | `[]const []const u8` | The font families for italic text, like `font_family`. Each is written as its own line. Empty: ghostty's default. |
| `font_family_bold_italic` | `[]const []const u8` | The font families for bold italic text, like `font_family`. Each is written as its own line. Empty: ghostty's default. |
| `font_style` | `?values.FontStyle` | The named font style (as the font advertises it) for regular text, or `.disabled`. null: ghostty's default, `default`. |
| `font_style_bold` | `?values.FontStyle` | The named font style for bold text, or `.disabled`. null: ghostty's default, `default`. |
| `font_style_italic` | `?values.FontStyle` | The named font style for italic text, or `.disabled`. null: ghostty's default, `default`. |
| `font_style_bold_italic` | `?values.FontStyle` | The named font style for bold italic text, or `.disabled`. null: ghostty's default, `default`. |
| `font_synthetic_style` | `?values.SyntheticStyle` | Control whether Ghostty should synthesize a style if the requested style is not available in the specified font-family. null: ghostty's default, `bold,italic,bold-italic`. |
| `font_feature` | `[]const []const u8` | Font features to apply (`-calt`, `+ss01`, `cv01=2`), one per line. Each is written as its own line. Empty: ghostty's default. |
| `font_size` | `?f64` | Font size in points. null: ghostty's default, `12`. |
| `font_variation` | `[]const values.FontVariation` | Variable font axis values for regular text (`wght=800`). Each is written as its own line. Empty: ghostty's default. |
| `font_variation_bold` | `[]const values.FontVariation` | Variable font axis values for bold text. Each is written as its own line. Empty: ghostty's default. |
| `font_variation_italic` | `[]const values.FontVariation` | Variable font axis values for italic text. Each is written as its own line. Empty: ghostty's default. |
| `font_variation_bold_italic` | `[]const values.FontVariation` | Variable font axis values for bold italic text. Each is written as its own line. Empty: ghostty's default. |
| `font_codepoint_map` | `[]const values.CodepointMap` | Force one or a range of Unicode codepoints to map to a specific named font. Each is written as its own line. Empty: ghostty's default. |
| `clipboard_codepoint_map` | `[]const values.ClipboardCodepointMap` | Map specific Unicode codepoints to replacement values when copying text to clipboard. Each is written as its own line. Empty: ghostty's default. |
| `font_thicken` | `?bool` | Draw fonts with a thicker stroke, if supported. null: ghostty's default, `false`. |
| `font_thicken_strength` | `?u8` | Strength of thickening when `font-thicken` is enabled. null: ghostty's default, `255`. |
| `font_shaping_break` | `?values.FontShapingBreak` | Locations to break font shaping into multiple runs. null: ghostty's default, `cursor`. |
| `alpha_blending` | `?enum { native, linear, linear_corrected }` | What color space to use when performing alpha blending. null: ghostty's default, `linear-corrected`. |
| `adjust_cell_width` | `?values.Adjustment` | Adjusts the cell width by pixels or a percentage. null: ghostty's default. |
| `adjust_cell_height` | `?values.Adjustment` | Adjusts the cell height by pixels or a percentage; text stays centered vertically. null: ghostty's default. |
| `adjust_font_baseline` | `?values.Adjustment` | Distance in pixels or percentage adjustment from the bottom of the cell to the text baseline. null: ghostty's default. |
| `adjust_underline_position` | `?values.Adjustment` | Distance in pixels or percentage adjustment from the top of the cell to the top of the underline. null: ghostty's default. |
| `adjust_underline_thickness` | `?values.Adjustment` | Thickness in pixels of the underline. null: ghostty's default. |
| `adjust_strikethrough_position` | `?values.Adjustment` | Distance in pixels or percentage adjustment from the top of the cell to the top of the strikethrough. null: ghostty's default. |
| `adjust_strikethrough_thickness` | `?values.Adjustment` | Thickness in pixels or percentage adjustment of the strikethrough. null: ghostty's default. |
| `adjust_overline_position` | `?values.Adjustment` | Distance in pixels or percentage adjustment from the top of the cell to the top of the overline. null: ghostty's default. |
| `adjust_overline_thickness` | `?values.Adjustment` | Thickness in pixels or percentage adjustment of the overline. null: ghostty's default. |
| `adjust_cursor_thickness` | `?values.Adjustment` | Thickness in pixels or percentage adjustment of the bar cursor and outlined rect cursor. null: ghostty's default. |
| `adjust_cursor_height` | `?values.Adjustment` | Height in pixels or percentage adjustment of the cursor. null: ghostty's default. |
| `adjust_box_thickness` | `?values.Adjustment` | Thickness in pixels or percentage adjustment of box drawing characters. null: ghostty's default. |
| `adjust_icon_height` | `?values.Adjustment` | Height in pixels or percentage adjustment of maximum height for nerd font icons. null: ghostty's default. |
| `grapheme_width_method` | `?enum { legacy, unicode }` | The method to use for calculating the cell width of a grapheme cluster. null: ghostty's default, `unicode`. |
| `freetype_load_flags` | `?values.FreetypeLoadFlags` | FreeType load flags to enable. null: ghostty's default, `hinting,no-force-autohint,no-monochrome,autohint,light`. |
| `theme` | `?values.Theme` | A theme by name or absolute path, or one theme each for light and dark mode. null: ghostty's default. |
| `background` | `?kosm.Color` | Background color for the window. null: ghostty's default, `#282c34`. |
| `foreground` | `?kosm.Color` | Foreground color for the window. null: ghostty's default, `#ffffff`. |
| `background_image` | `?[]const u8` | Background image for the terminal. null: ghostty's default. |
| `background_image_opacity` | `?f64` | Background image opacity, multiplied with `background_opacity`. null: ghostty's default, `1`. |
| `background_image_position` | `?enum { top_left, top_center, top_right, center_left, center, center_right, bottom_left, bottom_center, bottom_right }` | Background image position. null: ghostty's default, `center`. |
| `background_image_fit` | `?enum { contain, cover, stretch, none }` | How the background image is scaled to the window. null: ghostty's default, `contain`. |
| `background_image_repeat` | `?bool` | Whether to repeat the background image or not. null: ghostty's default, `false`. |
| `selection_foreground` | `?values.CellColor` | The foreground color for selected text. null: ghostty's default. |
| `selection_background` | `?values.CellColor` | The background color for selected text. null: ghostty's default. |
| `selection_clear_on_typing` | `?bool` | Whether to clear selected text when typing. null: ghostty's default, `true`. |
| `selection_clear_on_copy` | `?bool` | Whether to clear selected text after copying. null: ghostty's default, `false`. |
| `selection_word_chars` | `?[]const u8` | Characters that mark word boundaries when selecting by word. null: ghostty's default, spaces, quotes, brackets and shell punctuation. |
| `minimum_contrast` | `?f64` | The minimum contrast ratio between the foreground and background colors. null: ghostty's default, `1`. |
| `palette` | `[256]?kosm.Color` | The 256 terminal colors by index; 0..15 are the ANSI colors, 8..15 their bright forms. `from` sets 0..7 from the wheel; null 8..15 derive from 0..7 through `bright` (D23). Each set index is written as `palette = N=#rrggbb`; the rest are ghostty's. |
| `palette_generate` | `?bool` | Whether to generate the extended 256 color palette (16..255) from the base 16 colors. null: ghostty's default, `false`. |
| `palette_harmonious` | `?bool` | Invert the palette colors generated when `palette-generate` is enabled, so that the colors go in reverse order. null: ghostty's default, `false`. |
| `cursor_color` | `?values.CellColor` | The color of the cursor. null: ghostty's default. |
| `cursor_opacity` | `?f64` | The opacity level (opposite of transparency) of the cursor. null: ghostty's default, `1`. |
| `cursor_style` | `?enum { block, bar, underline, block_hollow }` | The style of the cursor. null: ghostty's default, `block`. |
| `cursor_style_blink` | `?bool` | Sets the default blinking state of the cursor. null: ghostty's default. |
| `cursor_text` | `?values.CellColor` | The color of the text under the cursor. null: ghostty's default. |
| `cursor_click_to_move` | `?bool` | Enables the ability to move the cursor at prompts by clicking on a location in the prompt text. null: ghostty's default, `true`. |
| `mouse_hide_while_typing` | `?bool` | Hide the mouse immediately when typing. null: ghostty's default, `false`. |
| `scroll_to_bottom` | `?values.ScrollToBottom` | When to scroll the surface to the bottom. null: ghostty's default, `keystroke,no-output`. |
| `mouse_shift_capture` | `?union(enum) { boolean: bool, always, never }` | Determines whether running programs can detect the shift key pressed with a mouse click. null: ghostty's default, `false`. |
| `mouse_reporting` | `?bool` | Enable or disable mouse reporting. null: ghostty's default, `true`. |
| `mouse_scroll_multiplier` | `?values.MouseScrollMultiplier` | Multiplier for scrolling distance with the mouse wheel. null: ghostty's default, `precision:1,discrete:3`. |
| `background_opacity` | `?f64` | The opacity level (opposite of transparency) of the background. null: ghostty's default, `1`. |
| `background_opacity_cells` | `?bool` | Applies background opacity to cells with an explicit background color set. null: ghostty's default, `false`. |
| `background_blur` | `?values.BackgroundBlur` | How much to blur the background when `background_opacity` is below 1. null: ghostty's default, `false`. |
| `unfocused_split_opacity` | `?f64` | The opacity level (opposite of transparency) of an unfocused split. null: ghostty's default, `0.7`. |
| `unfocused_split_fill` | `?kosm.Color` | The color to dim the unfocused split. null: ghostty's default. |
| `split_divider_color` | `?kosm.Color` | The color of the split divider. null: ghostty's default. |
| `split_preserve_zoom` | `?values.SplitPreserveZoom` | Control when Ghostty preserves a zoomed split. null: ghostty's default, `no-navigation`. |
| `search_foreground` | `?kosm.Color` | The foreground color for search matches. null: ghostty's default, `#000000`. |
| `search_background` | `?kosm.Color` | The background color for search matches. null: ghostty's default, `#ffe082`. |
| `search_selected_foreground` | `?kosm.Color` | The foreground color for the selected search match. null: ghostty's default, `#000000`. |
| `search_selected_background` | `?kosm.Color` | The background color for the selected search match. null: ghostty's default, `#f2a57e`. |
| `command` | `?[]const u8` | The command to run, usually a shell. null: ghostty's default. |
| `initial_command` | `?[]const u8` | This is the same as "command", but only applies to the first terminal surface created when Ghostty starts. null: ghostty's default. |
| `notify_on_command_finish` | `?enum { never, unfocused, always }` | Controls when command finished notifications are sent. null: ghostty's default, `never`. |
| `notify_on_command_finish_action` | `?values.NotifyOnCommandFinishAction` | If command finished notifications are enabled, this controls how the user is notified. null: ghostty's default, `bell,no-notify`. |
| `notify_on_command_finish_after` | `?values.Duration` | How long a command must run before its finish is notified. null: ghostty's default, `5s`. |
| `env` | `[]const values.Env` | Extra environment variables to pass to commands launched in a terminal surface. Each is written as its own line. Empty: ghostty's default. |
| `input` | `[]const values.Input` | Data to send as input to the command on startup. Each is written as its own line. Empty: ghostty's default. |
| `wait_after_command` | `?bool` | If true, keep the terminal open after the command exits. null: ghostty's default, `false`. |
| `abnormal_command_exit_runtime` | `?u32` | The number of milliseconds of runtime below which we consider a process exit to be abnormal. null: ghostty's default, `250`. |
| `scrollback_limit_bytes` | `?values.Limit` | The size of the scrollback buffer in bytes. null: ghostty's default, `50000000`. |
| `scrollback_limit_lines` | `?values.Limit` | The maximum number of lines of scrollback to retain. null: ghostty's default, `unlimited`. |
| `scrollback_compression` | `?bool` | Whether to compress scrollback pages while the terminal is idle. null: ghostty's default, `true`. |
| `scrollbar` | `?enum { system, never }` | Control when the scrollbar is shown to scroll the scrollback buffer. null: ghostty's default, `system`. |
| `link_url` | `?bool` | Match a regular expression against the terminal text and associate clicking it with an action. null: ghostty's default, `true`. |
| `link_osc8` | `?bool` | Enable hyperlinks created with the OSC 8 escape sequence. null: ghostty's default, `true`. |
| `link_previews` | `?union(enum) { boolean: bool, osc8 }` | Show link previews for a matched URL. null: ghostty's default, `true`. |
| `maximize` | `?bool` | Whether to start the window in a maximized state. null: ghostty's default, `false`. |
| `fullscreen` | `?union(enum) { boolean: bool, non_native, non_native_visible_menu, non_native_padded_notch }` | Start new windows in fullscreen. null: ghostty's default, `false`. |
| `title` | `?[]const u8` | The title Ghostty will use for the window. null: ghostty's default. |
| `class` | `?[]const u8` | The setting that will change the application class value. null: ghostty's default. |
| `x11_instance_name` | `?[]const u8` | This controls the instance name field of the `WM_CLASS` X11 property when running under X11. null: ghostty's default. |
| `working_directory` | `?values.WorkingDirectory` | The directory to change to after starting the command. null: ghostty's default. |
| `keybind` | `[]const values.Keybind` | Key bindings, written in order after ghostty's defaults; see Keybinds above. Empty: ghostty's defaults. |
| `key_remap` | `[]const values.KeyRemap` | Remap modifier keys within Ghostty. Each is written as its own line. Empty: ghostty's default. |
| `window_padding_x` | `?values.Padding` | Horizontal window padding in points, one value or left and right. null: ghostty's default, `2`. |
| `window_padding_y` | `?values.Padding` | Vertical window padding in points, one value or top and bottom. null: ghostty's default, `2`. |
| `window_padding_balance` | `?union(enum) { boolean: bool, equal }` | The viewport dimensions are usually not perfectly divisible by the cell size. null: ghostty's default, `false`. |
| `window_padding_color` | `?enum { background, extend, extend_always }` | The color of the padding area of the window. null: ghostty's default, `background`. |
| `window_vsync` | `?bool` | Synchronize rendering with the screen refresh rate. null: ghostty's default, `true`. |
| `window_inherit_working_directory` | `?bool` | If true, new windows will inherit the working directory of the previously focused window. null: ghostty's default, `true`. |
| `tab_inherit_working_directory` | `?bool` | If true, new tabs will inherit the working directory of the previously focused tab. null: ghostty's default, `true`. |
| `split_inherit_working_directory` | `?bool` | If true, new split panes will inherit the working directory of the previously focused split. null: ghostty's default, `true`. |
| `window_inherit_font_size` | `?bool` | If true, new windows and tabs will inherit the font size of the previously focused window. null: ghostty's default, `true`. |
| `window_decoration` | `?enum { none, auto, client, server }` | Configure a preference for window decorations. null: ghostty's default, `auto`. |
| `window_title_font_family` | `?[]const u8` | The font that will be used for the application's window and tab titles. null: ghostty's default. |
| `window_subtitle` | `?union(enum) { boolean: bool, working_directory }` | The text that will be displayed in the subtitle of the window. null: ghostty's default, `false`. |
| `window_theme` | `?enum { auto, system, light, dark, ghostty }` | The theme to use for the windows. null: ghostty's default, `auto`. |
| `window_colorspace` | `?enum { srgb, display_p3 }` | The color space to use when interpreting terminal colors. null: ghostty's default, `srgb`. |
| `window_height` | `?u32` | The initial window height in grid cells; needs `window_width` too. null: ghostty's default, `0`. |
| `window_width` | `?u32` | The initial window width in grid cells; needs `window_height` too. null: ghostty's default, `0`. |
| `window_position_x` | `?i32` | The starting window x position in pixels; needs `window_position_y` too (macOS only). null: ghostty's default. |
| `window_position_y` | `?i32` | The starting window y position in pixels; needs `window_position_x` too (macOS only). null: ghostty's default. |
| `window_save_state` | `?enum { default, never, always }` | Whether to enable saving and restoring window state. null: ghostty's default, `default`. |
| `window_step_resize` | `?bool` | Resize the window in discrete increments of the focused surface's cell size. null: ghostty's default, `false`. |
| `window_new_tab_position` | `?enum { current, end }` | The position where new tabs are created. null: ghostty's default, `current`. |
| `window_show_tab_bar` | `?enum { always, auto, never }` | Whether to show the tab bar. null: ghostty's default, `auto`. |
| `window_titlebar_background` | `?kosm.Color` | Background color for the window titlebar. null: ghostty's default. |
| `window_titlebar_foreground` | `?kosm.Color` | Foreground color for the window titlebar. null: ghostty's default. |
| `drag_handle` | `?enum { always, auto, never }` | Controls when drag handles are shown over splits, allowing splits to be rearranged with mouse controls. null: ghostty's default, `auto`. |
| `resize_overlay` | `?enum { always, never, after_first }` | This controls when resize overlays are shown. null: ghostty's default, `after-first`. |
| `resize_overlay_position` | `?enum { center, top_left, top_center, top_right, bottom_left, bottom_center, bottom_right }` | If resize overlays are enabled, this controls the position of the overlay. null: ghostty's default, `center`. |
| `resize_overlay_duration` | `?values.Duration` | If resize overlays are enabled, this controls how long the overlay is visible on the screen before it is hidden. null: ghostty's default, `750ms`. |
| `focus_follows_mouse` | `?bool` | If true, when there are multiple split panes, the mouse selects the pane that is focused. null: ghostty's default, `false`. |
| `clipboard_read` | `?enum { allow, deny, ask }` | Whether programs in the terminal may read the clipboard (OSC 52). null: ghostty's default, `ask`. |
| `clipboard_write` | `?enum { allow, deny, ask }` | Whether programs in the terminal may write the clipboard (OSC 52). null: ghostty's default, `allow`. |
| `clipboard_write_limit_bytes` | `?values.Limit` | The largest single clipboard write a program may make through OSC 5522, in bytes. null: ghostty's default, `67108864`. |
| `clipboard_trim_trailing_spaces` | `?bool` | Trims trailing whitespace on data that is copied to the clipboard. null: ghostty's default, `true`. |
| `clipboard_paste_protection` | `?bool` | Require confirmation before pasting text that appears unsafe. null: ghostty's default, `true`. |
| `clipboard_paste_bracketed_safe` | `?bool` | If true, bracketed pastes will be considered safe. null: ghostty's default, `true`. |
| `title_report` | `?bool` | Enables or disabled title reporting (CSI 21 t). null: ghostty's default, `false`. |
| `image_storage_limit` | `?u32` | The bytes image protocols (such as kitty's) may use per screen; 0 disables them. null: ghostty's default, `320000000`. |
| `copy_on_select` | `?enum { none, primary, clipboard, both }` | Whether to automatically copy selected text to the clipboard. null: ghostty's default, `primary`. |
| `right_click_action` | `?enum { context_menu, paste, copy, copy_or_paste, ignore }` | The action to take when the user right-clicks on the terminal surface. null: ghostty's default, `context-menu`. |
| `middle_click_action` | `?enum { primary_paste, clipboard_paste, ignore }` | The action to take when the user middle-clicks on the terminal surface. null: ghostty's default, `primary-paste`. |
| `click_repeat_interval` | `?u32` | The time in milliseconds between clicks to consider a click a repeat (double, triple, etc.) or an entirely new single click. null: ghostty's default, `0`. |
| `config_file` | `[]const []const u8` | Additional configuration files to read. Each is written as its own line. Empty: ghostty's default. |
| `confirm_close_surface` | `?union(enum) { boolean: bool, always }` | Confirms that a surface should be closed before closing it. null: ghostty's default, `true`. |
| `quit_after_last_window_closed` | `?bool` | Whether or not to quit after the last surface is closed. null: ghostty's default, `true`. |
| `quit_after_last_window_closed_delay` | `?values.Duration` | Controls how long Ghostty will stay running after the last open surface has been closed. null: ghostty's default. |
| `initial_window` | `?bool` | This controls whether an initial window is created when Ghostty is run. null: ghostty's default, `true`. |
| `undo_timeout` | `?values.Duration` | The duration that undo operations remain available. null: ghostty's default, `5s`. |
| `quick_terminal_position` | `?enum { top, bottom, left, right, center }` | The position of the "quick" terminal window. null: ghostty's default, `top`. |
| `quick_terminal_size` | `?values.QuickTerminalSize` | The size of the quick terminal, as a percentage of the screen or in pixels. null: ghostty's default. |
| `gtk_quick_terminal_layer` | `?enum { overlay, top, bottom, background }` | The layer of the quick terminal window (GTK Wayland only). null: ghostty's default, `top`. |
| `gtk_quick_terminal_namespace` | `?[]const u8` | The namespace for the quick terminal window. null: ghostty's default, `ghostty-quick-terminal`. |
| `quick_terminal_screen` | `?enum { main, mouse, macos_menu_bar }` | The screen where the quick terminal should show up. null: ghostty's default, `main`. |
| `quick_terminal_animation_duration` | `?f64` | Duration (in seconds) of the quick terminal enter and exit animation. null: ghostty's default, `0.2`. |
| `quick_terminal_autohide` | `?bool` | Automatically hide the quick terminal when focus shifts to another window. null: ghostty's default, `false`. |
| `quick_terminal_space_behavior` | `?enum { move, remain }` | This configuration option determines the behavior of the quick terminal when switching between macOS spaces. null: ghostty's default, `move`. |
| `quick_terminal_keyboard_interactivity` | `?enum { none, on_demand, exclusive }` | Determines under which circumstances that the quick terminal should receive keyboard input. null: ghostty's default, `on-demand`. |
| `shell_integration` | `?enum { none, detect, bash, elvish, fish, nushell, zsh }` | Whether to enable shell integration auto-injection or not. null: ghostty's default, `detect`. |
| `shell_integration_features` | `?values.ShellIntegrationFeatures` | Shell integration features to enable. null: ghostty's default, `cursor,no-sudo,title,no-ssh-env,no-ssh-terminfo,path`. |
| `command_palette_entry` | `[]const values.CommandPaletteEntry` | Custom entries of the command palette (`.title`, `.description`, `.action`), added to ghostty's own. Empty: only ghostty's. |
| `osc_color_report_format` | `?enum { none, @"8_bit", @"16_bit" }` | Sets the reporting format for OSC sequences that request color information. null: ghostty's default, `16-bit`. |
| `vt_kam_allowed` | `?bool` | If true, allows the "KAM" mode (ANSI mode 2) to be used within the terminal. null: ghostty's default, `false`. |
| `vt_window_resize_allowed` | `?bool` | If true, allows the running program to resize the window using the xterm `CSI 8 ; rows ; columns t` escape sequence. null: ghostty's default, `false`. |
| `vt_xt_checksum_report` | `?bool` | Enables or disables checksum reporting (DECRQCRA, `CSI Pi ; Pg ; Pt ; Pl ; Pb ; Pr * y`). null: ghostty's default, `false`. |
| `vt_xt_checksum_extension` | `?values.ChecksumExtension` | How the checksum reported for DECRQCRA (see `vt-xt-checksum-report`) is calculated. null: ghostty's default, `negate,attributes,trim,no-undrawn,no-full`. |
| `custom_shader` | `[]const []const u8` | Custom shaders to run after the default shaders. Each is written as its own line. Empty: ghostty's default. |
| `custom_shader_animation` | `?union(enum) { boolean: bool, always }` | If `true` (default), the focused terminal surface will run an animation loop when custom shaders are used. null: ghostty's default, `true`. |
| `bell_features` | `?values.BellFeatures` | Bell features to enable if bell support is available in your runtime. null: ghostty's default, `no-system,no-audio,attention,title,no-border`. |
| `bell_audio_path` | `?[]const u8` | If `audio` is an enabled bell feature, this is a path to an audio file. null: ghostty's default. |
| `bell_audio_volume` | `?f64` | If `audio` is an enabled bell feature, this is the volume to play the audio file at (relative to the system volume). null: ghostty's default, `0.5`. |
| `app_notifications` | `?values.AppNotifications` | Control the in-app notifications that Ghostty shows. null: ghostty's default, `clipboard-copy,config-reload`. |
| `macos_non_native_fullscreen` | `?union(enum) { boolean: bool, visible_menu, padded_notch }` | Makes macOS fullscreen non-native: no animation and no new space. null: ghostty's default, `false`. |
| `macos_window_buttons` | `?enum { visible, hidden }` | Whether the window buttons in the macOS titlebar are visible. null: ghostty's default, `visible`. |
| `macos_titlebar_style` | `?enum { native, transparent, tabs, hidden }` | The style of the macOS titlebar. null: ghostty's default, `transparent`. |
| `macos_titlebar_proxy_icon` | `?enum { visible, hidden }` | Whether the proxy icon in the macOS titlebar is visible. null: ghostty's default, `visible`. |
| `macos_dock_drop_behavior` | `?enum { new_tab, new_window }` | Controls the windowing behavior when dropping a file or folder onto the Ghostty icon in the macOS dock. null: ghostty's default, `new-tab`. |
| `macos_option_as_alt` | `?union(enum) { boolean: bool, left, right }` | macOS doesn't have a distinct "alt" key and instead has the "option" key which behaves slightly differently. null: ghostty's default. |
| `macos_window_shadow` | `?bool` | Whether to enable the macOS window shadow. null: ghostty's default, `true`. |
| `macos_hidden` | `?enum { never, always }` | If true, the macOS icon in the dock and app switcher will be hidden. null: ghostty's default, `never`. |
| `macos_auto_secure_input` | `?bool` | Enables macOS Secure Input when a password prompt is detected. null: ghostty's default, `true`. |
| `macos_secure_input_indication` | `?bool` | If true, Ghostty will show a graphical indication when secure input is enabled. null: ghostty's default, `true`. |
| `macos_applescript` | `?bool` | If true, Ghostty exposes and handles the built-in AppleScript dictionary on macOS. null: ghostty's default, `true`. |
| `macos_icon` | `?enum { official, blueprint, chalkboard, microchip, glass, holographic, paper, retro, xray, custom, custom_style }` | Customize the macOS app icon. null: ghostty's default, `official`. |
| `macos_custom_icon` | `?[]const u8` | The absolute path to the custom icon file. null: ghostty's default. |
| `macos_icon_frame` | `?enum { aluminum, beige, plastic, chrome }` | The material to use for the frame of the macOS app icon. null: ghostty's default, `aluminum`. |
| `macos_icon_ghost_color` | `?kosm.Color` | The color of the ghost in the macOS app icon. null: ghostty's default. |
| `macos_icon_screen_color` | `?[]const kosm.Color` | The colors of the gradient on the screen of the macOS icon, bottom first. null: ghostty's default. |
| `macos_shortcuts` | `?enum { allow, deny, ask }` | Whether macOS Shortcuts are allowed to control Ghostty. null: ghostty's default, `ask`. |
| `linux_cgroup` | `?enum { never, always, single_instance }` | Put every surface (tab, split, window) into a transient `systemd` scope. null: ghostty's default, `single-instance`. |
| `linux_cgroup_memory_limit` | `?u64` | Memory limit for any individual terminal process (tab, split, window, etc.) in bytes. null: ghostty's default. |
| `linux_cgroup_processes_limit` | `?u64` | Number of processes limit for any individual terminal process (tab, split, window, etc.). null: ghostty's default. |
| `linux_cgroup_hard_fail` | `?bool` | Whether failing to create the `systemd` scope for `linux_cgroup` is an error. null: ghostty's default, `false`. |
| `gtk_opengl_debug` | `?bool` | Enable or disable GTK's OpenGL debugging logs. null: ghostty's default, `false`. |
| `gtk_single_instance` | `?union(enum) { boolean: bool, detect }` | Whether new `ghostty` processes open a window in the running instance. null: ghostty's default, `detect`. |
| `gtk_titlebar` | `?bool` | When enabled, the full GTK titlebar is displayed instead of your window manager's simple titlebar. null: ghostty's default, `true`. |
| `gtk_tabs_location` | `?enum { top, bottom, hidden }` | Determines the side of the screen that the GTK tab bar will stick to. null: ghostty's default, `top`. |
| `gtk_tabs_inverted` | `?bool` | Shows each tab close button at the start of the tab and its icon at the end. null: ghostty's default, `false`. |
| `gtk_titlebar_hide_when_maximized` | `?bool` | Hides the titlebar while the window is maximized. null: ghostty's default, `false`. |
| `gtk_toolbar_style` | `?enum { flat, raised, raised_border }` | Determines the appearance of the top and bottom bars tab bar. null: ghostty's default, `raised`. |
| `gtk_titlebar_style` | `?enum { native, tabs }` | The style of the GTK titlebar. null: ghostty's default, `native`. |
| `gtk_wide_tabs` | `?bool` | Whether GTK tabs fill the available space. null: ghostty's default, `true`. |
| `gtk_horizontal_tab_scroll` | `?bool` | If `true` (default), then two-finger horizontal scrolling on a touchpad will switch between tabs. null: ghostty's default, `true`. |
| `gtk_custom_css` | `[]const []const u8` | Custom CSS files to be loaded. Each is written as its own line. Empty: ghostty's default. |
| `desktop_notifications` | `?bool` | Whether programs in the terminal can show desktop notifications (OSC 9, OSC 777). null: ghostty's default, `true`. |
| `progress_style` | `?bool` | Whether programs in the terminal can show progress bars (OSC 9;4). null: ghostty's default, `true`. |
| `bold_color` | `?values.BoldColor` | Modifies the color used for bold text in the terminal. null: ghostty's default. |
| `faint_opacity` | `?f64` | The opacity level (opposite of transparency) of the faint text. null: ghostty's default, `0.5`. |
| `term` | `?[]const u8` | This will be used to set the `TERM` environment variable. null: ghostty's default, `xterm-ghostty`. |
| `enquiry_response` | `?[]const u8` | String to send when we receive `ENQ` (`0x05`) from the command that we are running. null: ghostty's default. |
| `async_backend` | `?enum { auto, epoll, io_uring, kqueue }` | Configures the low-level API to use for async IO, eventing, etc. null: ghostty's default, `auto`. |
| `auto_update` | `?enum { off, check, download }` | Control the auto-update functionality of Ghostty. null: ghostty's default. |
| `auto_update_channel` | `?enum { stable, tip }` | The release channel to use for auto-updates. null: ghostty's default. |
