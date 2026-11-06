//! Where a command that works on a config project runs and reports.

const Context = @This();

const std = @import("std");

io: std.Io,
/// Holds everything a command allocates; freed by the caller.
arena: std.mem.Allocator,
/// The config project's absolute path.
config: []const u8,
/// The environment for `zig`; null passes on kosm's own.
environ_map: ?*const std.process.Environ.Map = null,
/// What a command did, and what packages provide.
stdout: *std.Io.Writer,
/// Errors, and the output of a failing `zig`.
stderr: *std.Io.Writer,

/// The command failed and has said why on stderr.
pub const Failed = error{Failed};

/// Prints `error: <message>` to stderr and returns `error.Failed`.
pub fn fail(context: Context, comptime format: []const u8, arguments: anytype) (Failed || std.Io.Writer.Error) {
    context.stderr.print("error: " ++ format ++ "\n", arguments) catch |err| return err;
    return error.Failed;
}
