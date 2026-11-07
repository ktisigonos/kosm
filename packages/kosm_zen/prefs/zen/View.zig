//! Zen's `zen.view.*` prefs.

/// `window.*`: the window's color scheme.
window: Window = .{},
/// `compact.*`: compact mode.
compact: Compact = .{},
/// `grey-out-inactive-windows`: dim unfocused windows. null: Zen's, true.
grey_out_inactive_windows: ?bool = null,
/// `use-single-toolbar`: one toolbar in the sidebar instead of a top bar. null: Zen's, true.
use_single_toolbar: ?bool = null,
/// `show-newtab-button-top`: put the new tab button above the tabs. null: Zen's, true.
show_newtab_button_top: ?bool = null,
/// `sidebar-expanded`: show the sidebar expanded. null: Zen's, true.
sidebar_expanded: ?bool = null,

pub const Window = @import("view/Window.zig");
pub const Compact = @import("view/Compact.zig");
