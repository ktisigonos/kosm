# kosm_kitty

kitty for kosm: the `kitty` adapter (writes kitty.conf files) and the kitty app.

The app covers every kitty.conf option, grouped like kitty's own docs and named exactly like
kitty's options (`kitty.cursor.cursor_trail = 1`). It writes only the options that are set to
`~/.config/kitty/kosm.conf`; everything left `null` stays kitty's default. Make kitty read it
once, at the end of your own `kitty.conf` so its colors win:

```conf
include kosm.conf
```

`from(theme)` sets the colors (D27): foreground and background from white and black (swapped in
light mode), `color0`..`color7` from the wheel, cyan for URLs and the active border. Choices
are enums in Zig spelling (`.thin_sparse` for `thin-sparse`); structured values are typed
(`window_padding_width = .all(10)`, `window_border_width = .{ .pixels = 1 }`); the types live in
`kosm_kitty.values`. Keyboard and mouse mappings (`map`, `mouse_map`) are not covered yet.

## App fields

| Field | Default |
|---|---|
| `file` | `~/.config/kitty/kosm.conf` |
| `color_format` | null: `#rrggbb` |
| `bright` | the theme's `lightness.bright`; makes `color8`..`color15` from `color0`..`color7` |

### `fonts` (Fonts)

| Option | Type | Meaning |
|---|---|---|
| `font_family` | `?values.Font` | The main font face: a family name or a precise font specification. null: kitty's default, `monospace`. |
| `bold_font` | `?values.FontOrAuto` | The bold face, picked automatically from `font_family` by default. null: kitty's default, `auto`. |
| `italic_font` | `?values.FontOrAuto` | The italic face, picked automatically from `font_family` by default. null: kitty's default, `auto`. |
| `bold_italic_font` | `?values.FontOrAuto` | The bold italic face, picked automatically from `font_family` by default. null: kitty's default, `auto`. |
| `font_size` | `?f64` | Font size (in pts). null: kitty's default, `11.0`. |
| `force_ltr` | `?bool` | Render right-to-left scripts left to right, without kitty reordering words. null: kitty's default, `no`. |
| `symbol_map` | `[]const values.SymbolMap` | Map the specified Unicode codepoints to a particular font. Each item is written as its own line. |
| `narrow_symbols` | `[]const values.NarrowSymbols` | Restrict codepoints to a number of cells instead of letting them grow into following spaces. Each item is written as its own line. |
| `disable_ligatures` | `?enum { never, cursor, always }` | Choose how you want to handle multi-character ligatures. null: kitty's default, `never`. |
| `font_features` | `[]const values.FontFeatures` | Choose exactly which OpenType features to enable or disable. Each item is written as its own line. |
| `modify_font` | `[]const values.ModifyFont` | Modify font characteristics such as the position or thickness of the underline and strikethrough. Each item is written as its own line. |
| `box_drawing_scale` | `?values.BoxDrawingScale` | The sizes of the lines used for the box drawing Unicode characters. null: kitty's default, `0.001, 1, 1.5, 2`. |
| `undercurl_style` | `?enum { thin_sparse, thin_dense, thick_sparse, thick_dense }` | The style with which undercurls are rendered. null: kitty's default, `thin-sparse`. |
| `underline_exclusion` | `?values.UnderlineExclusion` | The size of the gaps kitty leaves in underlines where they cross descenders; 0 disables them. null: kitty's default, `1`. |
| `text_composition_strategy` | `?values.TextComposition` | Control how kitty composites text glyphs onto the background color. null: kitty's default, `platform`. |
| `text_fg_override_threshold` | `?values.ContrastThreshold` | A setting to prevent low contrast between foreground and background colors. null: kitty's default, `0`. |

### `cursor` (Text cursor customization)

| Option | Type | Meaning |
|---|---|---|
| `cursor` | `?values.ColorOrNone` | Default text cursor color; `none` renders it as reverse video. null: `colors.foreground` (D23). |
| `cursor_text_color` | `?values.ColorOrBackground` | The color of text under the cursor, or the cell's background color. null: `colors.background` (D23). |
| `cursor_shape` | `?enum { block, beam, underline }` | The cursor shape can be one of `block`, `beam`, `underline`. null: kitty's default, `block`. |
| `cursor_shape_unfocused` | `?enum { block, beam, underline, hollow, unchanged }` | Defines the text cursor shape when the OS window is not focused. null: kitty's default, `hollow`. |
| `cursor_beam_thickness` | `?f64` | The thickness of the beam cursor (in pts). null: kitty's default, `1.5`. |
| `cursor_underline_thickness` | `?f64` | The thickness of the underline cursor (in pts). null: kitty's default, `2.0`. |
| `cursor_blink_interval` | `?values.Timing` | The interval to blink the cursor (in seconds). null: kitty's default, `-1`. |
| `cursor_stop_blinking_after` | `?f64` | Stop blinking cursor after the specified number of seconds of keyboard inactivity. null: kitty's default, `15.0`. |
| `cursor_trail` | `?u32` | Set this to a value larger than zero to enable a "cursor trail" animation. null: kitty's default, `0`. |
| `cursor_trail_decay` | `?values.TrailDecay` | Controls the decay times for the cursor trail effect when the `cursor_trail` is enabled. null: kitty's default, `0.1 0.4`. |
| `cursor_trail_start_threshold` | `?values.TrailThreshold` | Set the distance threshold for starting the cursor trail. null: kitty's default, `2`. |
| `cursor_trail_color` | `?values.ColorOrNone` | Set the color of the cursor trail when `cursor_trail` is enabled. null: kitty's default, `none`. |

### `scrollback` (Scrollback)

| Option | Type | Meaning |
|---|---|---|
| `scrollback_lines` | `?i64` | Number of lines of history to keep in memory for scrolling back. null: kitty's default, `2000`. |
| `scrollbar` | `?enum { scrolled, always, never, hovered, scrolled_and_hovered, scrolled_or_hovered }` | Control when the scrollbar is displayed. null: kitty's default, `scrolled`. |
| `scrollbar_interactive` | `?bool` | If disabled, the scrollbar will not be controllable via the mouse and all mouse events will pass through the scrollbar. null: kitty's default, `yes`. |
| `scrollbar_jump_on_click` | `?bool` | Clicking the scrollbar track jumps there instead of moving one screen at a time. null: kitty's default, `yes`. |
| `scrollbar_width` | `?f64` | The width of the scroll bar in units of cell width. null: kitty's default, `0.5`. |
| `scrollbar_hover_width` | `?f64` | The width of the scroll bar when the mouse is hovering over it, in units of cell width. null: kitty's default, `1`. |
| `scrollbar_handle_opacity` | `?f64` | The opacity of the scrollbar handle, 0 being fully transparent and 1 being full opaque. null: kitty's default, `0.5`. |
| `scrollbar_radius` | `?f64` | The radius (curvature) of the scrollbar handle in units of cell width. null: kitty's default, `0.3`. |
| `scrollbar_gap` | `?f64` | The gap between the scrollbar and the window edge in units of cell width. null: kitty's default, `0.1`. |
| `scrollbar_min_handle_height` | `?f64` | The minimum height of the scrollbar handle in units of cell height. null: kitty's default, `1`. |
| `scrollbar_hitbox_expansion` | `?f64` | The extra area around the handle to allow easier grabbing of the scollbar in units of cell width. null: kitty's default, `0.25`. |
| `scrollbar_track_opacity` | `?f64` | The opacity of the scrollbar track, 0 being fully transparent and 1 being full opaque. null: kitty's default, `0`. |
| `scrollbar_track_hover_opacity` | `?f64` | The opacity of the scrollbar track when the mouse is over the scrollbar, 0 being fully transparent and 1 being full opaque. null: kitty's default, `0.1`. |
| `scrollbar_handle_color` | `?values.ScrollbarColor` | The color of the scrollbar handle. null: kitty's default, `foreground`. |
| `scrollbar_track_color` | `?values.ScrollbarColor` | The color of the scrollbar track. null: kitty's default, `foreground`. |
| `progress_bar` | `?enum { left, right, top, bottom, hidden }` | When a program uses the OSC 9;4 escape sequence to report progress, draw a progress bar in the specified position of the window. null: kitty's default, `top`. |
| `scrollback_pager` | `?[]const u8` | Program with which to view scrollback in a new window. null: kitty's default. |
| `scrollback_pager_history_size` | `?f64` | Separate scrollback history size (in MB), used only for browsing the scrollback buffer with pager. null: kitty's default, `0`. |
| `scrollback_fill_enlarged_window` | `?bool` | Fill new space with lines from the scrollback buffer after enlarging a window. null: kitty's default, `no`. |
| `wheel_scroll_multiplier` | `?f64` | Multiplier for the number of lines scrolled by the mouse wheel. null: kitty's default, `5.0`. |
| `wheel_scroll_min_lines` | `?i64` | The minimum number of lines scrolled by the mouse wheel. null: kitty's default, `1`. |
| `touch_scroll_multiplier` | `?f64` | Multiplier for the number of lines scrolled by a touchpad. null: kitty's default, `1.0`. |
| `pixel_scroll` | `?bool` | Enable per-pixel scrolling, in the kitty scrollback buffer, when using high precision input devices (for example touchpads). null: kitty's default, `yes`. |
| `momentum_scroll` | `?f64` | The amount of friction to apply to slow down momentum (inertial) scrolling. null: kitty's default, `0.96`. |

### `mouse` (Mouse)

| Option | Type | Meaning |
|---|---|---|
| `mouse_hide_wait` | `?values.MouseHideWait` | Hide mouse cursor after the specified number of seconds of the mouse not being used. null: kitty's default, `3.0`. |
| `url_color` | `?kosm.Color` | The color and style for highlighting URLs on mouse-over. null: kitty's default, `#0087bd`. |
| `url_style` | `?enum { none, straight, double, curly, dotted, dashed }` | The underline style for detected URLs. null: kitty's default, `curly`. |
| `open_url_with` | `?[]const u8` | The program to open clicked URLs. null: kitty's default, `default`. |
| `url_prefixes` | `?[]const []const u8` | The set of URL prefixes to look for when detecting a URL under the mouse cursor. null: kitty's default. |
| `detect_urls` | `?bool` | Detect URLs under the mouse. null: kitty's default, `yes`. |
| `detect_url_regex` | `[]const []const u8` | A regular expression to detect as a URL under the mouse, in addition to the URLs detected via `url_prefixes`. Each item is written as its own line. |
| `url_excluded_characters` | `?[]const u8` | Additional characters to be disallowed from URLs, when detecting URLs under the mouse cursor. null: kitty's default. |
| `show_hyperlink_targets` | `?enum { never, always, ctrl, shift, super, alt }` | When the mouse hovers over a terminal hyperlink, show the actual URL that will be activated when the hyperlink is clicked. null: kitty's default, `never`. |
| `hyperlink_target_position` | `?enum { top, bottom, below, tooltip }` | Where to display the URL shown by `show_hyperlink_targets`. null: kitty's default, `top`. |
| `underline_hyperlinks` | `?enum { hover, always, never }` | Control how hyperlinks are underlined. null: kitty's default, `hover`. |
| `copy_on_select` | `?values.CopyOnSelect` | Copy to clipboard or a private buffer on select. null: kitty's default, `no`. |
| `clear_selection_on_clipboard_loss` | `?bool` | When the contents of the clipboard no longer reflect the current selection, clear it. null: kitty's default, `no`. |
| `paste_actions` | `?values.PasteActions` | A comma separated list of actions to take when pasting or dropping text into the terminal. null: kitty's default, `quote-urls-at-prompt,confirm`. |
| `strip_trailing_spaces` | `?enum { always, never, smart }` | Remove spaces at the end of lines when copying to clipboard. null: kitty's default, `never`. |
| `select_by_word_characters` | `?[]const u8` | Characters considered part of a word when double clicking. null: kitty's default, `@-./_~?&=%+#`. |
| `select_by_word_characters_forward` | `?[]const u8` | Characters considered part of a word when extending the selection forward on double clicking. null: kitty's default. |
| `click_interval` | `?f64` | The interval between successive clicks to detect double/triple clicks (in seconds). null: kitty's default, `-1.0`. |
| `focus_follows_mouse` | `?enum { no, yes, drop }` | Set the active window to the window under the mouse when the mouse crosses into a different window. null: kitty's default, `no`. |
| `pointer_shape_when_grabbed` | `?values.PointerShape` | The shape of the mouse pointer when the program running in the terminal grabs the mouse. null: kitty's default, `arrow`. |
| `default_pointer_shape` | `?values.PointerShape` | The default shape of the mouse pointer. null: kitty's default, `beam`. |
| `pointer_shape_when_dragging` | `?values.DraggingPointer` | The default shape of the mouse pointer when dragging across text. null: kitty's default, `beam crosshair`. |
| `drag_threshold` | `?u32` | The threshold distance the mouse must move to start a drag and drop. null: kitty's default, `5`. |
| `clear_all_mouse_actions` | `?bool` | Remove all mouse action definitions up to this point. null: kitty's default, `no`. |

### `performance` (Performance tuning)

| Option | Type | Meaning |
|---|---|---|
| `repaint_delay` | `?u32` | Delay between screen updates (in milliseconds). null: kitty's default, `10`. |
| `input_delay` | `?u32` | Delay before input from the program running in the terminal is processed (in milliseconds). null: kitty's default, `3`. |
| `sync_to_monitor` | `?bool` | Sync screen updates to the refresh rate of the monitor. null: kitty's default, `yes`. |

### `bell` (Terminal bell)

| Option | Type | Meaning |
|---|---|---|
| `enable_audio_bell` | `?bool` | The audio bell. null: kitty's default, `yes`. |
| `visual_bell_duration` | `?values.Timing` | The visual bell duration (in seconds). null: kitty's default, `0.0`. |
| `visual_bell_color` | `?values.ColorOrNone` | The color used by visual bell. null: kitty's default, `none`. |
| `window_alert_on_bell` | `?bool` | Request window attention on bell. null: kitty's default, `yes`. |
| `bell_on_tab` | `?[]const u8` | Some text or a Unicode symbol to show on the tab if a window in the tab that does not have focus has a bell. null: kitty's default. |
| `command_on_bell` | `?[]const u8` | Program to run when a bell occurs. null: kitty's default, `none`. |
| `macos_dock_badge_on_bell` | `?bool` | Show a badge on kitty's dock icon when a bell occurs and kitty is not the active application (macOS only). null: kitty's default, `yes`. |
| `bell_path` | `?[]const u8` | Path to a sound file to play as the bell sound. null: kitty's default, `none`. |
| `linux_bell_theme` | `?[]const u8` | The XDG Sound Theme kitty will use to play the bell sound. null: kitty's default, `__custom`. |

### `window` (Window layout)

| Option | Type | Meaning |
|---|---|---|
| `remember_window_size` | `?bool` | Reuse the last OS window size and maximized state for new instances. null: kitty's default, `yes`. |
| `initial_window_width` | `?values.WindowSize` | The width of a new OS window, in pixels or cells. null: kitty's default, `640`. |
| `initial_window_height` | `?values.WindowSize` | The height of a new OS window, in pixels or cells. null: kitty's default, `400`. |
| `remember_window_position` | `?bool` | Reuse the last OS window position for new instances. null: kitty's default, `no`. |
| `enabled_layouts` | `?[]const values.Layout` | The enabled window layouts. null: kitty's default, `*`. |
| `window_resize_step_cells` | `?u32` | The width step, in cells, when resizing a window in a layout with `start_resizing_window`. null: kitty's default, `2`. |
| `window_resize_step_lines` | `?u32` | The height step, in lines, when resizing a window in a layout with `start_resizing_window`. null: kitty's default, `2`. |
| `window_border_width` | `?values.Length` | The width of window borders. null: kitty's default, `0.5pt`. |
| `draw_minimal_borders` | `?bool` | Draw only the minimum borders needed. null: kitty's default, `yes`. |
| `window_border_radius` | `?values.Length` | The corner radius of window borders. null: kitty's default, `0`. |
| `draw_window_borders_for_single_window` | `?bool` | Draw borders around a window even when there is only a single window visible. null: kitty's default, `no`. |
| `window_margin_width` | `?values.Edges` | The window margin (in pts) (blank area outside the border). null: kitty's default, `0`. |
| `single_window_margin_width` | `?values.Edges` | The window margin to use when only a single window is visible (in pts). null: kitty's default, `-1`. |
| `collapse_window_margins` | `?bool` | Count the gap between neighbouring windows once instead of as the sum of both margins. null: kitty's default, `no`. |
| `window_padding_width` | `?values.Edges` | The window padding (in pts) (blank area between the text and the window border). null: kitty's default, `0`. |
| `single_window_padding_width` | `?values.Edges` | The window padding to use when only a single window is visible (in pts). null: kitty's default, `-1`. |
| `placement_strategy` | `?values.Position` | Where the cell area sits when the window size is not a multiple of the cell size. null: kitty's default, `center`. |
| `padding_fill_strategy` | `?enum { background, neighboring_cell }` | How the padding left when the window size is not a multiple of the cell size is filled. null: kitty's default, `background`. |
| `active_border_color` | `?values.ColorOrNone` | The color for the border of the active window. null: kitty's default, `#00ff00`. |
| `inactive_border_color` | `?kosm.Color` | The color for the border of inactive windows. null: kitty's default, `#cccccc`. |
| `bell_border_color` | `?kosm.Color` | The color for the border of inactive windows in which a bell has occurred. null: kitty's default, `#ff5a00`. |
| `inactive_text_alpha` | `?f64` | Fade the content in inactive windows by the specified amount. null: kitty's default, `1.0`. |
| `hide_window_decorations` | `?enum { no, yes, titlebar_only, titlebar_and_corners }` | Hide the window decorations (title-bar and window borders) with `yes`. null: kitty's default, `no`. |
| `window_logo_path` | `?[]const u8` | Path to a logo image. null: kitty's default, `none`. |
| `window_logo_position` | `?values.Position` | Where to position the window logo in the window. null: kitty's default, `bottom-right`. |
| `window_logo_alpha` | `?f64` | The amount the logo should be faded into the background. null: kitty's default, `0.5`. |
| `window_logo_scale` | `?values.LogoScale` | The percentage (0-100] of the window size to which the logo should scale. null: kitty's default, `0`. |
| `resize_debounce_time` | `?values.ResizeDebounce` | How long to wait, in seconds, before redrawing during a live resize of an OS window. null: kitty's default, `0.1 0.5`. |
| `resize_in_steps` | `?bool` | Resize the OS window in steps as large as the cells, instead of with the usual pixel accuracy. null: kitty's default, `no`. |
| `visual_window_select_characters` | `?[]const u8` | The list of characters for visual window selection. null: kitty's default. |
| `confirm_os_window_close` | `?values.ConfirmClose` | Ask for confirmation when closing an OS window or a tab with at least this number of kitty windows in it by window manager (e.g. null: kitty's default, `-1`. |
| `window_drag_tolerance` | `?f64` | Control dragging window borders to resize kitty windows. null: kitty's default, `2`. |
| `window_title_bar` | `?enum { top, bottom }` | Control the position of the window title bar relative to the window content. null: kitty's default, `top`. |
| `window_title_bar_min_windows` | `?u32` | The minimum number of visible windows in a tab before window title bars are shown. null: kitty's default, `0`. |
| `window_title_template` | `?[]const u8` | A template to render the window title bar text. null: kitty's default. |
| `active_window_title_template` | `?[]const u8` | Template to use for the active window title bar. null: kitty's default, `none`. |
| `window_title_bar_active_foreground` | `?values.ColorOrNone` | Foreground color for the active window title bar. null: kitty's default, `none`. |
| `window_title_bar_active_background` | `?values.ColorOrNone` | Background color for the active window title bar. null: kitty's default, `none`. |
| `window_title_bar_inactive_foreground` | `?values.ColorOrNone` | Foreground color for inactive window title bars. null: kitty's default, `none`. |
| `window_title_bar_inactive_background` | `?values.ColorOrNone` | Background color for inactive window title bars. null: kitty's default, `none`. |
| `window_title_bar_align` | `?enum { left, center, right }` | Horizontal alignment of the text in window title bars. null: kitty's default, `center`. |

### `tab_bar` (Tab bar)

| Option | Type | Meaning |
|---|---|---|
| `tab_bar_edge` | `?enum { top, bottom, left, right }` | The edge to show the tab bar on, `top`, `bottom`, `left` or `right`. null: kitty's default, `bottom`. |
| `tab_bar_margin_width` | `?f64` | The margin perpendicular to the tab bar edge (in pts). null: kitty's default, `0.0`. |
| `tab_bar_margin_height` | `?values.TabBarMarginHeight` | The margin along the tab bar edge (in pts). null: kitty's default, `0.0 0.0`. |
| `tab_bar_style` | `?enum { fade, hidden, powerline, separator, slant, custom }` | The tab bar style, can be one of. null: kitty's default, `fade`. |
| `tab_bar_filter` | `?[]const u8` | A `search expression`. null: kitty's default. |
| `tab_bar_align` | `?enum { start, center, end, left, right }` | The alignment of the tab bar, can be one of. null: kitty's default, `start`. |
| `tab_bar_show_new_tab_button` | `?bool` | When set to `yes`, a `+` button is always shown at the end of the tab bar as a clickable shortcut to open a new tab. null: kitty's default, `no`. |
| `tab_bar_min_tabs` | `?u32` | The minimum number of tabs that must exist before the tab bar is shown. null: kitty's default, `2`. |
| `tab_switch_strategy` | `?enum { last, left, previous, right }` | The algorithm to use when switching to a tab when the current tab is closed. null: kitty's default, `previous`. |
| `tab_fade` | `?[]const f64` | Control how each tab fades into the background when using `fade` for the `tab_bar_style`. null: kitty's default, `0.25 0.5 0.75 1`. |
| `tab_separator` | `?[]const u8` | The separator between tabs in the tab bar when using `separator` as the `tab_bar_style`. null: kitty's default. |
| `tab_powerline_style` | `?enum { angled, round, slanted }` | The powerline separator style between tabs in the tab bar when using `powerline` as the `tab_bar_style`, can be one of. null: kitty's default, `angled`. |
| `tab_activity_symbol` | `?[]const u8` | Some text or a Unicode symbol to show on the tab if a window in the tab that does not have focus has some activity. null: kitty's default, `none`. |
| `tab_title_max_length` | `?u32` | The maximum number of cells that can be used to render the text in a tab. null: kitty's default, `0`. |
| `tab_title_max_lines` | `?u32` | The maximum number of lines each tab may occupy, for vertical tab bars only (see `tab_bar_edge`). null: kitty's default, `1`. |
| `tab_title_wrap` | `?values.TitleWrap` | Wrap tab titles that are too long to fit instead of truncating them, for vertical tab bars only (see `tab_bar_edge`). null: kitty's default, `no`. |
| `tab_title_template` | `?[]const u8` | A template to render the tab title. null: kitty's default. |
| `active_tab_title_template` | `?[]const u8` | Template to use for active tabs. null: kitty's default, `none`. |
| `active_tab_foreground` | `?kosm.Color` | Tab bar colors and styles. null: kitty's default, `#000`. |
| `active_tab_background` | `?kosm.Color` | kitty's `active_tab_background`. null: kitty's default, `#eee`. |
| `active_tab_font_style` | `?values.FontStyle` | The font style of the active tab. null: kitty's default, `bold-italic`. |
| `inactive_tab_foreground` | `?kosm.Color` | kitty's `inactive_tab_foreground`. null: kitty's default, `#444`. |
| `inactive_tab_background` | `?kosm.Color` | kitty's `inactive_tab_background`. null: kitty's default, `#999`. |
| `inactive_tab_font_style` | `?values.FontStyle` | The font style of inactive tabs. null: kitty's default, `normal`. |
| `tab_bar_background` | `?values.ColorOrNone` | Background color for the tab bar. null: kitty's default, `none`. |
| `tab_bar_margin_color` | `?values.ColorOrNone` | Color for the tab bar margin area. null: kitty's default, `none`. |

### `colors` (Color scheme)

| Option | Type | Meaning |
|---|---|---|
| `foreground` | `?kosm.Color` | The foreground and background colors. null: kitty's default, `#dddddd`. |
| `background` | `?kosm.Color` | kitty's `background`. null: kitty's default, `#000000`. |
| `background_opacity` | `?f64` | The opacity of the background color, 0..1. null: the alpha of `colors.background`, written only when below 1, rounded to two decimals (D23). |
| `background_blur` | `?i64` | Set to a positive value to enable background blur (blurring of the visuals behind a transparent window) on platforms that support it. null: kitty's default, `0`. |
| `transparent_background_colors` | `?[]const values.TransparentColor` | A space separated list of upto 7 colors, with opacity. null: kitty's default. |
| `dynamic_background_opacity` | `?bool` | Allow changing `background_opacity` at runtime, by shortcut or remote control. null: kitty's default, `no`. |
| `background_image` | `?[]const u8` | Glob pattern matching one or more background images. null: kitty's default, `none`. |
| `background_image_layout` | `?enum { mirror_tiled, scaled, tiled, clamped, centered, cscaled }` | Whether to tile, scale or clamp the background image. null: kitty's default, `tiled`. |
| `background_image_linear` | `?bool` | When background image is scaled, whether linear interpolation should be used. null: kitty's default, `no`. |
| `background_tint` | `?f64` | How much to tint the background image by the background color. null: kitty's default, `0.0`. |
| `background_tint_gaps` | `?f64` | How much to tint the background image at the window gaps by the background color, after applying `background_tint`. null: kitty's default, `1.0`. |
| `dim_opacity` | `?f64` | How much to dim text that has the DIM/FAINT attribute set. null: kitty's default, `0.4`. |
| `selection_foreground` | `?values.ColorOrNone` | The foreground and background colors for text selected with the mouse. null: kitty's default, `#000000`. |
| `selection_background` | `?values.ColorOrNone` | The background color of text selected with the mouse. null: kitty's default, `#fffacd`. |
| `palette_generate` | `?enum { fixed, semantic, legacy }` | How to fill in any colors that are unset (set to `none`) in the 256-color palette. null: kitty's default, `fixed`. |
| `color0` | `?kosm.Color` | black null: kitty's default, `#000000`. |
| `color8` | `?kosm.Color` | Bright variant of `color0`. null: `color0` through the app's `bright` modifier (D23). |
| `color1` | `?kosm.Color` | red null: kitty's default, `#cc0403`. |
| `color9` | `?kosm.Color` | Bright variant of `color1`. null: `color1` through the app's `bright` modifier (D23). |
| `color2` | `?kosm.Color` | green null: kitty's default, `#19cb00`. |
| `color10` | `?kosm.Color` | Bright variant of `color2`. null: `color2` through the app's `bright` modifier (D23). |
| `color3` | `?kosm.Color` | yellow null: kitty's default, `#cecb00`. |
| `color11` | `?kosm.Color` | Bright variant of `color3`. null: `color3` through the app's `bright` modifier (D23). |
| `color4` | `?kosm.Color` | blue null: kitty's default, `#0d73cc`. |
| `color12` | `?kosm.Color` | Bright variant of `color4`. null: `color4` through the app's `bright` modifier (D23). |
| `color5` | `?kosm.Color` | magenta null: kitty's default, `#cb1ed1`. |
| `color13` | `?kosm.Color` | Bright variant of `color5`. null: `color5` through the app's `bright` modifier (D23). |
| `color6` | `?kosm.Color` | cyan null: kitty's default, `#0dcdcd`. |
| `color14` | `?kosm.Color` | Bright variant of `color6`. null: `color6` through the app's `bright` modifier (D23). |
| `color7` | `?kosm.Color` | white null: kitty's default, `#dddddd`. |
| `color15` | `?kosm.Color` | Bright variant of `color7`. null: `color7` through the app's `bright` modifier (D23). |
| `mark1_foreground` | `?kosm.Color` | Color for marks of type 1 null: kitty's default, `black`. |
| `mark1_background` | `?kosm.Color` | Color for marks of type 1 (light steel blue) null: kitty's default, `#98d3cb`. |
| `mark2_foreground` | `?kosm.Color` | Color for marks of type 2 null: kitty's default, `black`. |
| `mark2_background` | `?kosm.Color` | Color for marks of type 2 (beige) null: kitty's default, `#f2dcd3`. |
| `mark3_foreground` | `?kosm.Color` | Color for marks of type 3 null: kitty's default, `black`. |
| `mark3_background` | `?kosm.Color` | Color for marks of type 3 (violet) null: kitty's default, `#f274bc`. |

### `advanced` (Advanced)

| Option | Type | Meaning |
|---|---|---|
| `shell` | `?[]const u8` | The shell program to execute. null: kitty's default, `.`. |
| `editor` | `?[]const u8` | The terminal based text editor (such as `vim` or `nano`) to use when editing the kitty config file or similar tasks. null: kitty's default, `.`. |
| `close_on_child_death` | `?bool` | Close the window when the child process (usually the shell) exits. null: kitty's default, `no`. |
| `remote_control_password` | `[]const values.RemoteControlPassword` | Allow other programs to control kitty using passwords. Each item is written as its own line. |
| `allow_remote_control` | `?enum { password, socket_only, socket, no, yes }` | Allow other programs to control kitty. null: kitty's default, `no`. |
| `listen_on` | `?[]const u8` | Listen to the specified socket for remote control connections. null: kitty's default, `none`. |
| `env` | `[]const values.Env` | Specify the environment variables to be set in all child processes. Each item is written as its own line. |
| `custom_shaders` | `?[]const []const u8` | Space separated list of custom shader pipeline names. null: kitty's default. |
| `filter_notification` | `[]const []const u8` | Specify rules to filter out notifications sent by applications running in kitty. Each item is written as its own line. |
| `watcher` | `[]const []const u8` | Path to python file which will be loaded for `watchers`. Each item is written as its own line. |
| `exe_search_path` | `[]const []const u8` | Control where kitty finds the programs to run. Each item is written as its own line. |
| `update_check_interval` | `?f64` | The interval to periodically check if an update to kitty is available (in hours). null: kitty's default, `24`. |
| `auto_reload_config` | `?f64` | Automatically reload configuration files when they are changed. null: kitty's default, `0.1`. |
| `startup_session` | `?[]const u8` | Path to a session file to use for all kitty instances. null: kitty's default, `none`. |
| `restore_session_after_logout` | `?bool` | Save kitty's windows as a session on logout and restore them on the next start. null: kitty's default, `no`. |
| `clipboard_control` | `?values.ClipboardControl` | Allow programs running in kitty to read and write from the clipboard. null: kitty's default. |
| `clipboard_max_size` | `?f64` | The maximum size (in MB) of data from programs running in kitty that will be stored for writing to the system clipboard. null: kitty's default, `512`. |
| `file_transfer_confirmation_bypass` | `?[]const u8` | The password that can be supplied to the `file transfer kitten` to skip the transfer confirmation prompt. null: kitty's default. |
| `allow_hyperlinks` | `?enum { yes, no, ask }` | Process `hyperlink` escape sequences (OSC 8). null: kitty's default, `yes`. |
| `shell_integration` | `?values.ShellIntegration` | Enable shell integration on supported shells. null: kitty's default, `enabled`. |
| `allow_cloning` | `?enum { yes, no, ask }` | Control whether programs running in the terminal can request new windows to be created. null: kitty's default, `ask`. |
| `clone_source_strategies` | `?values.CloneSourceStrategies` | Control what shell code is sourced when running `clone-in-kitty` in the newly cloned window. null: kitty's default, `venv,conda,env_var,path`. |
| `notify_on_cmd_finish` | `?values.NotifyOnCmdFinish` | Show a desktop notification when a long-running command finishes (needs `shell_integration`). null: kitty's default, `never`. |
| `term` | `?[]const u8` | The value of the `TERM` environment variable to set. null: kitty's default, `xterm-kitty`. |
| `terminfo_type` | `?enum { path, direct, none }` | The value of the `TERMINFO` environment variable to set. null: kitty's default, `path`. |
| `forward_stdio` | `?bool` | Forward STDOUT and STDERR of the kitty process to child processes. null: kitty's default, `no`. |
| `menu_map` | `[]const values.MenuMap` | Specify entries for various menus in kitty. Each item is written as its own line. |

### `os` (OS specific tweaks)

| Option | Type | Meaning |
|---|---|---|
| `wayland_titlebar_color` | `?values.TitlebarColor` | The color of the kitty window's titlebar on Wayland systems with client side window decorations such as GNOME. null: kitty's default, `system`. |
| `macos_titlebar_color` | `?values.MacosTitlebarColor` | The color of the kitty window's titlebar on macOS. null: kitty's default, `system`. |
| `macos_option_as_alt` | `?enum { no, left, right, both }` | Use the `Option` key as an `Alt` key on macOS. null: kitty's default, `no`. |
| `macos_hide_from_tasks` | `?bool` | Hide kitty from running tasks on macOS (Cmd+Tab and the Dock). null: kitty's default, `no`. |
| `macos_quit_when_last_window_closed` | `?bool` | Have kitty quit when all the top-level windows are closed on macOS. null: kitty's default, `no`. |
| `macos_window_resizable` | `?bool` | Disable this if you want kitty top-level OS windows to not be resizable on macOS. null: kitty's default, `yes`. |
| `macos_thicken_font` | `?f64` | Draw an extra border around the font with the given width, to increase legibility at small font sizes on macOS. null: kitty's default, `0`. |
| `macos_traditional_fullscreen` | `?bool` | Use the macOS traditional full-screen transition, that is faster, but less pretty. null: kitty's default, `no`. |
| `macos_fullscreen_ignore_safe_area_insets` | `?bool` | When using `macos_traditional_fullscreen`, ignore the safe area insets on displays such as MacBook screens with a notch. null: kitty's default, `no`. |
| `macos_use_physical_screen_frame` | `?bool` | Place macOS desktop panels in the physical screen frame instead of the visible one. null: kitty's default, `no`. |
| `macos_ns_window_layer` | `?[]const u8` | Set the macOS NSWindow level for newly created panel OS windows such as with the `panel kitten`. null: kitty's default, `unset`. |
| `macos_show_window_title_in` | `?enum { all, menubar, none, window }` | Control where the window title is displayed on macOS. null: kitty's default, `all`. |
| `macos_menubar_title_max_length` | `?u32` | The maximum number of characters from the window title to show in the macOS global menu bar. null: kitty's default, `0`. |
| `macos_custom_beam_cursor` | `?bool` | Use a custom mouse cursor for macOS that is easier to see on both light and dark backgrounds. null: kitty's default, `no`. |
| `macos_colorspace` | `?enum { srgb, default, displayp3 }` | The colorspace in which to interpret terminal colors. null: kitty's default, `srgb`. |
| `linux_display_server` | `?enum { auto, wayland, x11 }` | Choose between Wayland and X11 backends. null: kitty's default, `auto`. |
| `wayland_enable_ime` | `?bool` | Enable Input Method Extension on Wayland. null: kitty's default, `yes`. |

### `shortcuts` (Keyboard shortcuts)

| Option | Type | Meaning |
|---|---|---|
| `kitty_mod` | `?values.Modifiers` | Special modifier key alias for default shortcuts. null: kitty's default, `ctrl+shift`. |
| `remap_modifiers` | `?[]const values.ModifierRemap` | Remap modifiers, making one modifier act as another. null: kitty's default. |
| `clear_all_shortcuts` | `?bool` | Remove all shortcut definitions up to this point. null: kitty's default, `no`. |
| `map_timeout` | `?f64` | The default timeout (in seconds) for multi-key mappings and modal keyboard modes. null: kitty's default, `0.0`. |
| `action_alias` | `[]const values.Alias` | Define action aliases to avoid repeating the same options in multiple mappings. Each item is written as its own line. |
| `kitten_alias` | `[]const values.Alias` | Like `action_alias` above, but specifically for kittens. Each item is written as its own line. |
