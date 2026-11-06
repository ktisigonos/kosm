//! The node names of an assignment statement, such as Lua's `M.blur.enabled, x = true, 1`.
//! Targets and values pair up by position; a target that is not a name or a dotted index of
//! one (`M[key]`, `f().x`) is skipped, since its key is not known from the text.

/// Node type of the statement ("assignment_statement").
node: []const u8,
/// Node type of the statement's child holding the targets ("variable_list").
targets: []const u8,
/// Field of `targets` naming each target ("name").
target: []const u8,
/// Node type of the statement's child holding the values ("expression_list").
values: []const u8,
/// Field of `values` naming each value ("value").
value: []const u8,
/// Node type of a target that is a bare key ("identifier").
name: []const u8,
/// How a target steps into a table (`M.blur`).
index: Index,

/// A dotted target: a table expression and one key.
pub const Index = @import("Index.zig");
