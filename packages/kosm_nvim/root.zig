//! Neovim: a base16 palette generated as `lua/theme.lua`, for a base16 colorscheme plugin to load.

const std = @import("std");

/// The palette; build one with `from`.
pub const App = @import("App.zig");
/// Colors from the theme (D27).
pub const from = App.from;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
}
