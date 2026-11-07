//! Zen's `zen.view.window.*` prefs.

/// `scheme`: the window's light or dark look. Default: the theme's mode.
scheme: ?Scheme = null,

/// Zen's `zen.view.window.scheme` values.
pub const Scheme = enum(u2) {
    dark = 0,
    light = 1,
    /// Follow the system's light or dark setting.
    auto = 2,
};
