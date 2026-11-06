//! The node names a tree-sitter grammar uses for keys and values, from its `node-types.json`
//! (D39, D40). `kosm.treesitter.parser` turns them into an adapter's `parser`.

/// Node type of a key and its value ("pair").
pair: []const u8,
/// Field of a `pair` node holding the key ("key").
key: []const u8,
/// Field of a `pair` node holding the value ("value").
value: []const u8,
/// Node types whose pairs form a nested table ("object"). One at the top of the file, with no
/// key, holds the file's top-level keys.
nest: []const []const u8 = &.{},
/// Node types that are lists ("array"); their elements are reached through
/// `Selection.elements` (D77, D80).
list: []const []const u8 = &.{},
/// Key node types written between delimiters ("string"); kosm drops their first and last
/// byte, so `"editor.fontSize"` is the key `editor.fontSize`. Escapes are kept as written.
quoted_key: []const []const u8 = &.{},
/// Node types paths see through: the entries inside count as the enclosing table's, so
/// `hl.config({ general = {...} })` holds `general` (D30). Anything else is invisible.
transparent: []const []const u8 = &.{},
/// Statements that assign values to keys (`M.blur.enabled = true`, D30); null when the
/// language has none.
assign: ?Assign = null,

/// How a grammar spells an assignment statement.
pub const Assign = @import("Spec/Assign.zig");
