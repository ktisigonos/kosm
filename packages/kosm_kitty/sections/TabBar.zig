//! kitty's "Tab bar" options. Field names are kitty's option names (D27).

const kosm = @import("kosm");
const values = @import("../values.zig");

/// The edge to show the tab bar on, `top`, `bottom`, `left` or `right`. null: kitty's default, `bottom`.
tab_bar_edge: ?enum { top, bottom, left, right } = null,
/// The margin perpendicular to the tab bar edge (in pts). null: kitty's default, `0.0`.
tab_bar_margin_width: ?f64 = null,
/// The margin along the tab bar edge (in pts). null: kitty's default, `0.0 0.0`.
tab_bar_margin_height: ?values.TabBarMarginHeight = null,
/// The tab bar style, can be one of. null: kitty's default, `fade`.
tab_bar_style: ?enum { fade, hidden, powerline, separator, slant, custom } = null,
/// A `search expression`. null: kitty's default.
tab_bar_filter: ?[]const u8 = null,
/// The alignment of the tab bar, can be one of. null: kitty's default, `start`.
tab_bar_align: ?enum { start, center, end, left, right } = null,
/// When set to `yes`, a `+` button is always shown at the end of the tab bar as a clickable shortcut to open a new tab. null: kitty's default, `no`.
tab_bar_show_new_tab_button: ?bool = null,
/// The minimum number of tabs that must exist before the tab bar is shown. null: kitty's default, `2`.
tab_bar_min_tabs: ?u32 = null,
/// The algorithm to use when switching to a tab when the current tab is closed. null: kitty's default, `previous`.
tab_switch_strategy: ?enum { last, left, previous, right } = null,
/// Control how each tab fades into the background when using `fade` for the `tab_bar_style`. null: kitty's default, `0.25 0.5 0.75 1`.
tab_fade: ?[]const f64 = null,
/// The separator between tabs in the tab bar when using `separator` as the `tab_bar_style`. null: kitty's default.
tab_separator: ?[]const u8 = null,
/// The powerline separator style between tabs in the tab bar when using `powerline` as the `tab_bar_style`, can be one of. null: kitty's default, `angled`.
tab_powerline_style: ?enum { angled, round, slanted } = null,
/// Some text or a Unicode symbol to show on the tab if a window in the tab that does not have focus has some activity. null: kitty's default, `none`.
tab_activity_symbol: ?[]const u8 = null,
/// The maximum number of cells that can be used to render the text in a tab. null: kitty's default, `0`.
tab_title_max_length: ?u32 = null,
/// The maximum number of lines each tab may occupy, for vertical tab bars only (see `tab_bar_edge`). null: kitty's default, `1`.
tab_title_max_lines: ?u32 = null,
/// Wrap tab titles that are too long to fit instead of truncating them, for vertical tab bars only (see `tab_bar_edge`). null: kitty's default, `no`.
tab_title_wrap: ?values.TitleWrap = null,
/// A template to render the tab title. null: kitty's default.
tab_title_template: ?[]const u8 = null,
/// Template to use for active tabs. null: kitty's default, `none`.
active_tab_title_template: ?[]const u8 = null,
/// Tab bar colors and styles. null: kitty's default, `#000`.
active_tab_foreground: ?kosm.Color = null,
/// kitty's `active_tab_background`. null: kitty's default, `#eee`.
active_tab_background: ?kosm.Color = null,
/// The font style of the active tab. null: kitty's default, `bold-italic`.
active_tab_font_style: ?values.FontStyle = null,
/// kitty's `inactive_tab_foreground`. null: kitty's default, `#444`.
inactive_tab_foreground: ?kosm.Color = null,
/// kitty's `inactive_tab_background`. null: kitty's default, `#999`.
inactive_tab_background: ?kosm.Color = null,
/// The font style of inactive tabs. null: kitty's default, `normal`.
inactive_tab_font_style: ?values.FontStyle = null,
/// Background color for the tab bar. null: kitty's default, `none`.
tab_bar_background: ?values.ColorOrNone = null,
/// Color for the tab bar margin area. null: kitty's default, `none`.
tab_bar_margin_color: ?values.ColorOrNone = null,
