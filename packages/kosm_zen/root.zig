//! Zen Browser: its theme colors as CSS custom properties for userChrome.css and userContent.css,
//! and its about:config prefs in every profile's user.js.

const std = @import("std");

/// Zen's theme colors and prefs; build one with `from`.
pub const App = @import("App.zig");
/// Colors and prefs from the theme (D27).
pub const from = App.from;
/// Prefs for a set of profiles, an app of its own (D94); build one with `Profile.from`.
pub const Profile = App.Profile;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    std.testing.refAllDecls(Profile);
    _ = @import("user_js.zig");
}
