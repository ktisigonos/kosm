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
/// Runs a script and reads what it builds: what it builds on and what it sets, or the tree it
/// built by calling Zig code through `context.library`. Strings may point into `source`, which
/// lives for the whole run; anything else is allocated in `context.arena`.
load: *const fn (context: *Context, source: []const u8) Error!Script,
/// Writes the files an editor completes scripts from, out of every type a script may set;
/// kosm puts them in the config's `zig-out/completions/<name>/` whenever it builds the runner
/// of scripts. Null for a frontend giving no completion.
complete: ?*const fn (arena: std.mem.Allocator, completion: Completion) std.mem.Allocator.Error![]const Completion.File = null,
/// The file in the config's root that points the editor at those files (".luarc.json"). Kosm
/// creates it only where it is missing, so a user's edits to it stay. Null for none.
editor_file: ?Completion.File = null,

/// What a script kosmos says: what it builds on, and the values it sets.
pub const Script = @import("Frontend/Script.zig");

/// What `load` gets besides the text: an arena, the script's path and a place to explain a
/// failure.
pub const Context = @import("Frontend/Context.zig");

/// Every type a script may set, for `complete`.
pub const Completion = @import("Frontend/Completion.zig");

/// Every Zig function, value and namespace a script may call.
pub const Library = @import("Frontend/Library.zig");

/// A name a script reaches functions, values and other namespaces through.
pub const Namespace = @import("Frontend/Namespace.zig");

/// A Zig function a script calls.
pub const Function = @import("Frontend/Function.zig");

/// A Zig value a script holds by reference.
pub const Handle = @import("Frontend/Handle.zig");

/// What a function or handle gets from its frontend when a script uses it.
pub const Call = @import("Frontend/Call.zig");

/// Errors `load` may return. Return `InvalidScript` through `Context.fail`.
pub const Error = std.mem.Allocator.Error || error{InvalidScript};

/// Whether this frontend claims `extension` (".lua").
pub fn claims(frontend: Frontend, extension: []const u8) bool {
    for (frontend.extensions) |claimed| {
        if (std.mem.eql(u8, claimed, extension)) return true;
    }
    return false;
}
