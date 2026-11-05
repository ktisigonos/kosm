//! kitty: its config language (the `kitty` adapter) and its settings (the app).

const std = @import("std");

/// kitty's settings; build one with `from`.
pub const App = @import("App.zig");
/// Colors from the theme, everything else left to kitty (D27).
pub const from = App.from;
/// Writes kitty.conf files.
pub const adapter = @import("adapter.zig").adapter;
/// The types kitty options take, for naming them in a kosmos.
pub const values = @import("values.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    _ = @import("settings.zig");
    _ = @import("adapter.zig");
}
