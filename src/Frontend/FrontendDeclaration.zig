//! What a frontend's script declares, as the frontend it is written through reads it without
//! calling any of its functions: the frontend's plain data and the functions it gives. Kosm
//! writes the Zig module the frontend is used through from it.

const FrontendDeclaration = @This();

const std = @import("std");
const Completion = @import("Completion.zig");

/// The language's name, for messages and the completion folder: "json".
name: []const u8,
/// File extensions the frontend claims, with the dot (".json").
extensions: []const []const u8 = &.{},
/// The file in the config's root pointing an editor at the completion files; null for none.
editor_file: ?Completion.File = null,
/// The functions the script gives, by `kosm.Frontend`'s names: "load", "variants", "complete".
functions: []const []const u8 = &.{},

/// Whether the script gives the function `name`.
pub fn gives(declaration: FrontendDeclaration, name: []const u8) bool {
    for (declaration.functions) |function| {
        if (std.mem.eql(u8, function, name)) return true;
    }
    return false;
}
