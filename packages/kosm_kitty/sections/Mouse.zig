//! kitty's "Mouse" options. Field names are kitty's option names (D27).

const kosm = @import("kosm");
const values = @import("../values.zig");

/// Hide mouse cursor after the specified number of seconds of the mouse not being used. null: kitty's default, `3.0`.
mouse_hide_wait: ?values.MouseHideWait = null,
/// The color and style for highlighting URLs on mouse-over. null: kitty's default, `#0087bd`.
url_color: ?kosm.Color = null,
/// The underline style for detected URLs. null: kitty's default, `curly`.
url_style: ?enum { none, straight, double, curly, dotted, dashed } = null,
/// The program to open clicked URLs. null: kitty's default, `default`.
open_url_with: ?[]const u8 = null,
/// The set of URL prefixes to look for when detecting a URL under the mouse cursor. null: kitty's default.
url_prefixes: ?[]const []const u8 = null,
/// Detect URLs under the mouse. null: kitty's default, `yes`.
detect_urls: ?bool = null,
/// A regular expression to detect as a URL under the mouse, in addition to the URLs detected via `url_prefixes`. Each item is written as its own line.
detect_url_regex: []const []const u8 = &.{},
/// Additional characters to be disallowed from URLs, when detecting URLs under the mouse cursor. null: kitty's default.
url_excluded_characters: ?[]const u8 = null,
/// When the mouse hovers over a terminal hyperlink, show the actual URL that will be activated when the hyperlink is clicked. null: kitty's default, `never`.
show_hyperlink_targets: ?enum { never, always, ctrl, shift, super, alt } = null,
/// Where to display the URL shown by `show_hyperlink_targets`. null: kitty's default, `top`.
hyperlink_target_position: ?enum { top, bottom, below, tooltip } = null,
/// Control how hyperlinks are underlined. null: kitty's default, `hover`.
underline_hyperlinks: ?enum { hover, always, never } = null,
/// Copy to clipboard or a private buffer on select. null: kitty's default, `no`.
copy_on_select: ?values.CopyOnSelect = null,
/// When the contents of the clipboard no longer reflect the current selection, clear it. null: kitty's default, `no`.
clear_selection_on_clipboard_loss: ?bool = null,
/// A comma separated list of actions to take when pasting or dropping text into the terminal. null: kitty's default, `quote-urls-at-prompt,confirm`.
paste_actions: ?values.PasteActions = null,
/// Remove spaces at the end of lines when copying to clipboard. null: kitty's default, `never`.
strip_trailing_spaces: ?enum { always, never, smart } = null,
/// Characters considered part of a word when double clicking. null: kitty's default, `@-./_~?&=%+#`.
select_by_word_characters: ?[]const u8 = null,
/// Characters considered part of a word when extending the selection forward on double clicking. null: kitty's default.
select_by_word_characters_forward: ?[]const u8 = null,
/// The interval between successive clicks to detect double/triple clicks (in seconds). null: kitty's default, `-1.0`.
click_interval: ?f64 = null,
/// Set the active window to the window under the mouse when the mouse crosses into a different window. null: kitty's default, `no`.
focus_follows_mouse: ?enum { no, yes, drop } = null,
/// The shape of the mouse pointer when the program running in the terminal grabs the mouse. null: kitty's default, `arrow`.
pointer_shape_when_grabbed: ?values.PointerShape = null,
/// The default shape of the mouse pointer. null: kitty's default, `beam`.
default_pointer_shape: ?values.PointerShape = null,
/// The default shape of the mouse pointer when dragging across text. null: kitty's default, `beam crosshair`.
pointer_shape_when_dragging: ?values.DraggingPointer = null,
/// The threshold distance the mouse must move to start a drag and drop. null: kitty's default, `5`.
drag_threshold: ?u32 = null,
/// Remove all mouse action definitions up to this point. null: kitty's default, `no`.
clear_all_mouse_actions: ?bool = null,

/// Options kitty allows more than once: each item is its own line.
pub const repeated = [_][]const u8{"detect_url_regex"};
