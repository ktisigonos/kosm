//! Firefox's `browser.display.*` prefs.

const kosm = @import("kosm");

/// `background_color`: page background where a page sets none. Default: black, white in light
/// mode.
background_color: ?kosm.Color = null,
/// `foreground_color`: page text where a page sets none. Default: white, black in light mode.
foreground_color: ?kosm.Color = null,

/// Pref names that differ from the field names' `_` -> `-` spelling.
pub const pref_names = .{ .background_color = "background_color", .foreground_color = "foreground_color" };
