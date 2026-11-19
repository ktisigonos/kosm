//! What an adapter's script declares, as a frontend reads it without calling any of its
//! functions: the adapter's plain data and the capabilities it gives as functions. Kosm writes
//! the Zig module the adapter is used through from it.

const AdapterDeclaration = @This();

const std = @import("std");
const Adapter = @import("../Adapter.zig");
const Loose = @import("../Loose.zig");

/// The language name apps pass as `.lang`: "keys".
name: []const u8,
/// File extensions the adapter claims, with the dot (".keys").
extensions: []const []const u8 = &.{},
/// How the language writes a comment on a line of its own; null for none.
comment: ?Adapter.Comment = null,
/// A table of `kosm.Format`'s fields (`color`, `boolean`, `float_precision`), which kosm
/// checks; null for none.
default_format: ?Loose = null,
/// The capabilities the script gives as functions, by `kosm.Adapter`'s names: "format",
/// "parser", "serialize", "insert".
functions: []const []const u8 = &.{},

/// Whether the script gives the capability `name` as a function.
pub fn gives(declaration: AdapterDeclaration, name: []const u8) bool {
    for (declaration.functions) |function| {
        if (std.mem.eql(u8, function, name)) return true;
    }
    return false;
}
