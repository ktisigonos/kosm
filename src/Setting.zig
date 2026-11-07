//! A setting an app doesn't cover, written by path through the app's `extra` (D99).

const Setting = @This();

const Value = @import("value.zig").Value;

/// Where it goes: dot-separated keys, `"quoted.keys"` for a key holding a dot (D32), e.g.
/// `plugin.dynamic_cursors.length`.
path: []const u8,
/// What to write there, formatted like the app's own settings: `.{ .integer = 24 }`.
value: Value,
