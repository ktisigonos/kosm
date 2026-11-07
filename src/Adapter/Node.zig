//! One key, list element or value of a parsed file, as an adapter's `parser` reports it.
//! Kosm matches paths against this tree (D30-D32), so an adapter only says what the file holds.

const Node = @This();

const Range = @import("Range.zig");

/// The key naming this node in its table, as spelled in the file; null for list elements and
/// the root.
key: ?[]const u8,
/// What the value is.
kind: Kind,
/// Where the entry starts (its key, or the value of a list element), for messages and order.
position: usize,
/// The value's bytes; null for a table the file spells only through dotted keys
/// (`M.blur.enabled = true` has no bytes for `M.blur`).
value: ?Range,
/// A table's entries or a list's elements, in file order. A table's entries without a key are
/// its elements, for languages whose tables are lists too (Lua, D90); paths skip them.
children: []const Node = &.{},

/// The shape of a node's value.
pub const Kind = enum {
    /// Keyed entries a path can step into.
    table,
    /// Elements reached only through `Selection.elements` (D77, D80).
    list,
    /// A single value.
    scalar,
};
