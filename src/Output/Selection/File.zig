//! One file `edit` picked, parsed once.

const Adapter = @import("../../Adapter.zig");

/// Absolute path, as the glob reached it.
path: []const u8,
/// The path as messages show it, `~` for the home directory.
display_path: []const u8,
/// Its contents when the plan was made; every range is into these bytes.
source: []const u8,
/// Its keys and values, as the adapter parsed them.
root: Adapter.Node,
