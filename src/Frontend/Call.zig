//! What a function or handle a script uses gets from its frontend: an arena, the state of kosm
//! that built the library, and a place to explain a failure.

const Call = @This();

const std = @import("std");

/// Holds what the call allocates, for the whole run.
arena: std.mem.Allocator,
/// Kosm's own, from `Library.state`; a frontend only passes it on.
state: ?*anyopaque,
/// Why the call failed, set by `fail`.
message: ?[]const u8 = null,

/// Errors a call may return. On `CallFailed`, `message` says why, without the script's place,
/// which the frontend puts before it.
pub const Error = std.mem.Allocator.Error || error{CallFailed};

/// Records why the call failed and returns `error.CallFailed`.
pub fn fail(call: *Call, comptime format: []const u8, arguments: anytype) Error {
    call.message = try call.arena.print(format, arguments);
    return error.CallFailed;
}
