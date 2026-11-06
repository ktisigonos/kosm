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

pub const RunError = Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

/// Runs `zig` with `arguments` in the config directory; see `run`.
pub fn runZig(context: Context, arguments: []const []const u8) RunError!std.process.RunResult {
    return context.run(try std.mem.concat(context.arena, []const u8, &.{ &.{"zig"}, arguments }));
}

/// Runs `argv` in the config directory and collects its output; a program that cannot start fails.
pub fn run(context: Context, argv: []const []const u8) RunError!std.process.RunResult {
    return std.process.run(context.arena, context.io, .{
        .argv = argv,
        .cwd = .{ .path = context.config },
        .environ_map = context.environ_map,
    }) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => context.fail("cannot run {s}: {s}", .{ argv[0], @errorName(err) }),
    };
}
