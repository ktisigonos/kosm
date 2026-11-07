//! Firefox's `browser.*` prefs.

/// `display.*`: page colors where a page sets none.
display: Display = .{},
/// `tabs.*`: tabs.
tabs: Tabs = .{},

pub const Display = @import("browser/Display.zig");
pub const Tabs = @import("browser/Tabs.zig");
