//! Zen Browser: its theme colors as CSS custom properties for userChrome.css and userContent.css,
//! and its about:config prefs in every profile's user.js.

const std = @import("std");

/// Zen's theme colors and prefs; build one with `from`.
pub const App = @import("App.zig");
/// Colors and prefs from the theme.
pub const from = App.from;
/// Prefs for a set of profiles, an app of its own; build one with `Profile.from`.
pub const Profile = App.Profile;
/// The adapter the theme colors are written with, so a config needs only this package to rice Zen.
pub const css_adapter = @import("kosm_css").adapter;
/// The adapter the prefs are written with.
pub const userjs_adapter = @import("kosm_userjs").adapter;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    std.testing.refAllDecls(Profile);
    _ = @import("user_js.zig");
}
