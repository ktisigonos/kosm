//! Support for writing kosmoi in one language other than Zig. A package declares one as a public
//! constant, as it declares adapters; kosm finds a script kosmos (`kosmoi/<name>.<extension>`) by
//! the extension a frontend claims and hands it the script's text. A frontend never knows any
//! app: it only reads the script into loose values, which kosm puts into the typed tree.

const Frontend = @This();

const std = @import("std");

/// The language's name, for messages: "lua".
name: []const u8,
/// File extensions this frontend claims, with the dot (".lua").
extensions: []const []const u8,
/// Reads a script's text into what it builds on and what it sets. Strings may point into
/// `source`, which lives for the whole run; anything else is allocated in `context.arena`.
load: *const fn (context: *Context, source: []const u8) Error!Script,

/// What a script kosmos says: what it builds on, and the values it sets.
pub const Script = @import("Frontend/Script.zig");

/// What `load` gets besides the text: an arena, the script's path and a place to explain a
/// failure.
pub const Context = @import("Frontend/Context.zig");

/// Errors `load` may return. Return `InvalidScript` through `Context.fail`.
pub const Error = std.mem.Allocator.Error || error{InvalidScript};

/// Whether this frontend claims `extension` (".lua").
pub fn claims(frontend: Frontend, extension: []const u8) bool {
    for (frontend.extensions) |claimed| {
        if (std.mem.eql(u8, claimed, extension)) return true;
    }
    return false;
}
