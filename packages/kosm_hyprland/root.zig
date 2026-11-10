//! Hyprland: every `hl.config` option, generated as a Lua module or set in your own files.

const std = @import("std");

/// Hyprland's settings; build one with `from`.
pub const App = @import("App.zig");
/// Colors from the theme, everything else left to Hyprland.
pub const from = App.from;
/// The types Hyprland options take, for naming them in a kosmos.
pub const values = @import("values.zig");
/// The adapter the app writes with, so a config needs only this package to rice Hyprland.
pub const lua_adapter = @import("kosm_lua").adapter;

test {
    @setEvalBranchQuota(100_000);
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    std.testing.refAllDecls(values);
    _ = @import("settings.zig");
}
