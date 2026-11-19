//! Runs the functions of apps written through a frontend, for the Zig modules kosm generates
//! for them. Only the runner of scripts has one, which it installs before any kosmos runs.

const Host = @This();

const std = @import("std");
const Loose = @import("../Loose.zig");
const Call = @import("Call.zig");
const Handle = @import("Handle.zig");
const ScriptApp = @import("ScriptApp.zig");

/// Kosm's own, which `run` and `handle` get back.
state: *anyopaque,
/// Holds what the scripts' functions build, for the whole run.
arena: std.mem.Allocator,
/// Runs function `function` of `app`'s script with `arguments` and returns what it returns. On
/// `error.CallFailed`, `call.message` says why, starting with the script's place.
run: *const fn (state: *anyopaque, call: *Call, app: ScriptApp, function: []const u8, arguments: []const Loose) Call.Error!Loose,
/// A handle to `pointer`, a value of the type `id` names (`Handle.id(T)`), or null for a type
/// no script can be handed.
handle: *const fn (state: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle,

/// The host of this run, or null where no script can run (a kosmos' own runner). A global,
/// because an app's `from(theme)` takes nothing to hand it in: kosm runs one kosmos per process
/// and sets it once, before that kosmos runs. Private, so reflection over kosm never meets a
/// variable.
var installed: ?*const Host = null;

/// For kosm's runner: makes `host` (which must outlive the run) the one apps' scripts run
/// through, or none.
pub fn install(host: ?*const Host) void {
    installed = host;
}

/// The host apps' scripts run through, or null where no script can run.
pub fn current() ?*const Host {
    return installed;
}

/// A call whose arena is the host's.
pub fn call(host: *const Host) Call {
    return .{ .arena = host.arena, .state = host.state };
}

/// A handle to `value`, which must outlive the run, or null when no script can be handed a `T`.
pub fn handleOf(host: *const Host, comptime T: type, value: *T) ?Handle {
    return host.handle(host.state, Handle.id(T), value);
}
