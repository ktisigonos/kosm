//! A setting with its path split into keys: one an app writes from its own fields, or an extra
//!. `Setting.withExtras` checks a list of them, `Setting.tree` nests it for `generate`.

const Value = @import("../value.zig").Value;

/// The path as the user or the app wrote it, for messages: `general.border_size`.
path: []const u8,
/// The keys of `path`, outermost first. Null means `*`, any one key, which only edit targets
/// take.
keys: []const ?[]const u8,
/// What is written there.
value: Value,
/// Whether it came from the app's `extra` rather than one of its fields.
extra: bool = false,
