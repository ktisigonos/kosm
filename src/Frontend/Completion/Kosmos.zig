//! A Zig kosmos a script may build on, as `Completion` describes it.

/// As `kosm apply` spells it: "personal", "frost.iced".
name: []const u8,
/// The kosmos function's doc comment; null when it has none.
doc: ?[]const u8 = null,
/// The record of its `Params`; null when it takes none.
params: ?[]const u8 = null,
/// The record of the tree it returns, which a script's overrides set.
tree: []const u8,
