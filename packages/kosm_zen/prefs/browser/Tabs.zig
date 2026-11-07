//! Firefox's `browser.tabs.*` prefs.

/// `allow_transparent_browser`: let transparent pages show what is behind the window. null:
/// Firefox's, false.
allow_transparent_browser: ?bool = null,

/// Pref names that differ from the field names' `_` -> `-` spelling.
pub const pref_names = .{ .allow_transparent_browser = "allow_transparent_browser" };
