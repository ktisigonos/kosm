//! What an app's `reload` runs its program's reload through. Kosm hands one to each app
//! after the commit, so apps run commands without touching io themselves.

const Reloader = @This();

const std = @import("std");

io: std.Io,
failure_buffer: [failure_capacity]u8 = undefined,
failure_length: usize = 0,

const failure_capacity = 512;

/// The reload failed; `failure` says why.
pub const Error = error{ReloadFailed};

/// Runs `argv` (`&.{ "pkill", "-USR1", "-x", "kitty" }`) and waits for it. A command that
/// cannot start, or exits with anything but 0, fails the reload. Its stdout is discarded.
pub fn run(reloader: *Reloader, argv: []const []const u8) Error!void {
    if (argv.len == 0) return reloader.fail("the reload command is empty", .{});
    const command: Command = .{ .argv = argv };
    var child = std.process.spawn(reloader.io, .{ .argv = argv, .stdin = .ignore, .stdout = .ignore }) catch |err|
        return reloader.fail("cannot run {f}: {s}", .{ command, @errorName(err) });
    const term = child.wait(reloader.io) catch |err|
        return reloader.fail("cannot wait for {f}: {s}", .{ command, @errorName(err) });
    if (!term.success()) return reloader.fail("{f} {f}", .{ command, term });
}

/// Why the last `run` failed, or empty.
pub fn failure(reloader: *const Reloader) []const u8 {
    return reloader.failure_buffer[0..reloader.failure_length];
}

/// Records the failure. Too-long messages are cut short, like Diagnostics does.
fn fail(reloader: *Reloader, comptime format: []const u8, arguments: anytype) Error {
    const written = std.fmt.bufPrint(&reloader.failure_buffer, format, arguments) catch reloader.failure_buffer[0..];
    reloader.failure_length = written.len;
    return error.ReloadFailed;
}

/// Prints a command as `'pkill -USR1 -x kitty'`.
const Command = struct {
    argv: []const []const u8,

    pub fn format(command: Command, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeByte('\'');
        for (command.argv, 0..) |argument, index| {
            if (index != 0) try writer.writeByte(' ');
            try writer.writeAll(argument);
        }
        try writer.writeByte('\'');
    }
};

const testing = std.testing;

test "a command that exits 0 reloads" {
    var reloader: Reloader = .{ .io = testing.io };
    try reloader.run(&.{"true"});
    try testing.expectEqualStrings("", reloader.failure());
}

test "a command exiting non-zero fails with its exit code" {
    var reloader: Reloader = .{ .io = testing.io };
    try testing.expectError(error.ReloadFailed, reloader.run(&.{ "false", "--quiet" }));
    try testing.expectEqualStrings("'false --quiet' exited with code 1", reloader.failure());
}

test "a command that cannot start fails naming it" {
    var reloader: Reloader = .{ .io = testing.io };
    try testing.expectError(error.ReloadFailed, reloader.run(&.{"kosm-test-no-such-program"}));
    try testing.expectEqualStrings("cannot run 'kosm-test-no-such-program': FileNotFound", reloader.failure());
    try testing.expectError(error.ReloadFailed, reloader.run(&.{}));
    try testing.expectEqualStrings("the reload command is empty", reloader.failure());
}
