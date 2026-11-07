//! ghostty: its config language (the `ghostty` adapter) and its settings (the app).

const std = @import("std");

/// ghostty's settings; build one with `from`.
pub const App = @import("App.zig");
/// Colors from the theme, everything else left to ghostty (D27).
pub const from = App.from;
/// Reads and writes ghostty config files.
pub const adapter = @import("adapter.zig").adapter;
/// The types ghostty options take, for naming them in a kosmos.
pub const values = @import("values.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    _ = @import("settings.zig");
    _ = @import("adapter.zig");
    _ = @import("parser.zig");
}
