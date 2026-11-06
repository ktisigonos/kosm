//! The node names of a dotted index, such as Lua's `M.blur`.

/// Node type of the index ("dot_index_expression").
node: []const u8,
/// Field holding the indexed table ("table"): a name or another index.
table: []const u8,
/// Field holding the key ("field").
key: []const u8,
