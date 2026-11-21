//! Support for writing kosmoi and apps in one language other than Zig. A package declares one as
//! a public constant, as it declares adapters; kosm finds a script kosmos
//! (`kosmoi/<name>.<extension>`) or app (`apps/<name>/root.<extension>`) by the extension a
//! frontend claims and hands it the script's text. A frontend never knows any app: it only reads
//! scripts into loose values, which kosm puts into typed values, and runs their functions.

const Frontend = @This();

const std = @import("std");
const Loose = @import("Loose.zig");

/// The language's name, for messages: "lua".
name: []const u8,
/// File extensions this frontend claims, with the dot (".lua").
extensions: []const []const u8,
/// Runs a script and reads what it builds: what it builds on and what it sets, or the tree it
/// built by calling Zig code through `context.library`. Strings may point into `source`, which
/// lives for the whole run; anything else is allocated in `context.arena`.
load: *const fn (context: *Context, source: []const u8) Error!Script,
/// Lists the variants a script gives as `kosm apply` spells them after the script's name
/// ("light", "dark", "dark.soft"), running none of them, so kosm can refuse a variant that
/// shares its name with a Zig variant or another script. Null for a frontend whose scripts
/// give no variants; `context.variant` is unused.
variants: ?*const fn (context: *Context, source: []const u8) Error![]const []const u8 = null,
/// Writes the files an editor completes scripts from, out of every type a script may set;
/// kosm puts them in the config's `zig-out/completions/<name>/` whenever it builds the runner
/// of scripts. Allocate in `context.arena`; `context.path` is the frontend's name. Null for a
/// frontend giving no completion.
complete: ?*const fn (context: *Context, completion: Completion) Error![]const Completion.File = null,
/// The file in the config's root that points the editor at those files (".luarc.json"). Kosm
/// creates it only where it is missing, so a user's edits to it stay. Null for none.
editor_file: ?Completion.File = null,
/// Reads what an app's script declares (its fields, their types, defaults and doc comments, and
/// the functions it gives) without calling any of its functions; kosm calls it while building
/// the config, to write the Zig module the app is used through. `context.library` is empty
/// there. Null for a frontend writing no apps.
declare: ?*const fn (context: *Context, source: []const u8) Error!Declaration = null,
/// Reads what an adapter's script declares (its name, extensions, comment syntax, default format
/// and the capabilities it gives as functions) without calling any of its functions; kosm calls
/// it while building the config, to write the Zig module the adapter is used through.
/// `context.library` is empty there. Null for a frontend writing no adapters.
declare_adapter: ?*const fn (context: *Context, source: []const u8) Error!AdapterDeclaration = null,
/// Reads what a frontend's script declares (its name, extensions, editor file and the functions
/// it gives) without calling any of its functions; kosm calls it while building the config, to
/// write the Zig module the frontend is used through. `context.library` is empty there. Null
/// for a frontend writing no frontends.
declare_frontend: ?*const fn (context: *Context, source: []const u8) Error!FrontendDeclaration = null,
/// Says what the script `source` gives (an app, an adapter or a frontend) from what it returns,
/// without calling any of its functions; kosm calls it for a package's root script, which no
/// folder names the kind of. Fail through `Context.fail` when it gives none or more than one.
/// Null for a frontend whose scripts cannot be packages' roots.
declares: ?*const fn (context: *Context, source: []const u8) Error!Declared = null,
/// Calls function `function` of the app's or adapter's script at `context.path`, whose text is
/// `source`, with `arguments`, and returns what it returns: a table as a loose table, a Zig
/// value as its handle. The script runs once, on the first call naming it, in the frontend's one
/// interpreter, so its later calls share its values. Fail through `Context.fail`, the message
/// starting with the script's place. Null for a frontend writing no apps or adapters.
call: ?*const fn (context: *Context, source: []const u8, function: []const u8, arguments: []const Loose) Error!Loose = null,
/// Where the language counts byte positions from, as an adapter's script gives and gets them:
/// 0 for Zig's own, whose ranges end one past their last byte; 1 for Lua's, whose ranges end on
/// their last byte, as `string.sub` takes them.
counts_from: u1 = 0,
/// What `kosm new --language <name>` writes for each kind, in the first of `extensions`.
scaffolds: Scaffolds = .{},

/// The scripts `kosm new` starts a kosmos, app, adapter or frontend from.
pub const Scaffolds = @import("Frontend/Scaffolds.zig");

/// What a script kosmos says: what it builds on, and the values it sets.
pub const Script = @import("Frontend/Script.zig");

/// What an app's script declares, for `declare`.
pub const Declaration = @import("Frontend/Declaration.zig");

/// What an adapter's script declares, for `declare_adapter`.
pub const AdapterDeclaration = @import("Frontend/AdapterDeclaration.zig");

/// What a script gives, for `declares`.
pub const Declared = enum { app, adapter, frontend };

/// What a frontend's script declares, for `declare_frontend`.
pub const FrontendDeclaration = @import("Frontend/FrontendDeclaration.zig");

/// A frontend written through a frontend, which the Zig module kosm generates for it runs.
pub const ScriptFrontend = @import("Frontend/ScriptFrontend.zig");

/// An app written through a frontend, which the Zig module kosm generates for it runs.
pub const ScriptApp = @import("Frontend/ScriptApp.zig");

/// An adapter written through a frontend, which the Zig module kosm generates for it runs.
pub const ScriptAdapter = @import("Frontend/ScriptAdapter.zig");

/// The script of an app or adapter written through a frontend.
pub const ScriptFile = @import("Frontend/ScriptFile.zig");

/// What runs the functions of apps written through a frontend.
pub const Host = @import("Frontend/Host.zig");

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

/// Errors a frontend's functions may return. Return `InvalidScript` through `Context.fail`.
pub const Error = std.mem.Allocator.Error || error{InvalidScript};

/// Whether this frontend claims `extension` (".lua").
pub fn claims(frontend: Frontend, extension: []const u8) bool {
    for (frontend.extensions) |claimed| {
        if (std.mem.eql(u8, claimed, extension)) return true;
    }
    return false;
}
