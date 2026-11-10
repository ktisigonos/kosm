//! Neovim: a base16 palette generated as `lua/theme.lua`, for a base16 colorscheme plugin to load.

const std = @import("std");

/// The palette; build one with `from`.
pub const App = @import("App.zig");
/// Colors from the theme.
pub const from = App.from;
/// The adapter the app writes with, so a config needs only this package to rice Neovim.
pub const lua_adapter = @import("kosm_lua").adapter;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
}
