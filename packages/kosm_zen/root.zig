//! Zen Browser: its theme colors as CSS custom properties for userChrome.css and userContent.css.

const std = @import("std");

/// Zen's theme colors; build one with `from`.
pub const App = @import("App.zig");
/// Colors from the theme (D27).
pub const from = App.from;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
}
