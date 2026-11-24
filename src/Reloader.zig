//! What an app's `reload` runs its program's reload through. Kosm hands one to each app
//! after the commit, so apps run commands without touching io themselves.

const Reloader = @This();

const std = @import("std");

io: std.Io,
/// What a leading `~/` in `run`'s arguments expands to; set by kosm.
home: []const u8 = "",
/// How long a command may run before kosm stops it and the reload fails, so a program that
/// hangs (a frozen compositor) cannot hang kosm.
timeout: std.Io.Duration = .fromSeconds(10),
failure_buffer: [failure_capacity]u8 = undefined,
failure_length: usize = 0,

const failure_capacity = 512;

/// The reload failed; `failure` says why.
pub const Error = error{ReloadFailed};

/// Runs `argv` (`&.{ "pkill", "-USR1", "-x", "kitty" }`) and waits for it. An argument
/// starting with `~/` is a path under the home directory, as in apps' files. A command that
/// cannot start, exits with anything but 0, or runs longer than `timeout` (then it is killed)
/// fails the reload. Its stdout is discarded.
pub fn run(reloader: *Reloader, argv: []const []const u8) Error!void {
    if (argv.len == 0) return reloader.fail("the reload command is empty", .{});
    // A reload gets no allocator; the expanded arguments live only as long as this call.
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const expanded = reloader.expandHome(arena.allocator(), argv) catch return reloader.fail("out of memory", .{});
    const command: Command = .{ .argv = expanded };
    var child = std.process.spawn(reloader.io, .{ .argv = expanded, .stdin = .ignore, .stdout = .ignore }) catch |err|
        return reloader.fail("cannot run {f}: {s}", .{ command, @errorName(err) });
    const term = waitAtMost(reloader.io, &child, reloader.timeout) catch |err|
        return reloader.fail("cannot wait for {f}: {s}", .{ command, @errorName(err) });
    const finished = term orelse
        return reloader.fail("{f} ran longer than {d} ms, so kosm stopped it", .{ command, reloader.timeout.toMilliseconds() });
    if (!finished.success()) return reloader.fail("{f} {f}", .{ command, finished });
}

const Waited = union(enum) {
    exited: std.process.Child.WaitError!std.process.Child.Term,
    timed_out: std.Io.Cancelable!void,
};

/// Waits for `child` to exit, or kills it once `timeout` passed and returns null. Waits without
/// a limit when the `Io` cannot run the wait and the timer side by side.
fn waitAtMost(io: std.Io, child: *std.process.Child, timeout: std.Io.Duration) std.process.Child.WaitError!?std.process.Child.Term {
    const pid = child.id.?;
    var buffer: [2]Waited = undefined;
    var select: std.Io.Select(Waited) = .init(io, &buffer);
    defer select.cancelDiscard();
    select.concurrent(.exited, std.process.Child.wait, .{ child, io }) catch return try child.wait(io);
    select.concurrent(.timed_out, std.Io.sleep, .{ io, timeout, .awake }) catch {};
    switch (try select.await()) {
        .exited => |term| return try term,
        .timed_out => {
            // Unless it exited this instant, the wait still runs, so the child is not reaped
            // and its id is still its own.
            std.posix.kill(pid, .KILL) catch {};
            while (true) switch (try select.await()) {
                .exited => |term| {
                    _ = term catch |err| return err;
                    return null;
                },
                .timed_out => {},
            };
        },
    }
}

fn expandHome(reloader: *const Reloader, allocator: std.mem.Allocator, argv: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const expanded = try allocator.alloc([]const u8, argv.len);
    for (argv, expanded) |argument, *result| {
        result.* = if (std.mem.startsWith(u8, argument, "~/"))
            try std.Io.Dir.path.join(allocator, &.{ reloader.home, argument[2..] })
        else
            argument;
    }
    return expanded;
}

/// Why the last `run` failed, or empty.
pub fn failure(reloader: *const Reloader) []const u8 {
    return reloader.failure_buffer[0..reloader.failure_length];
}

/// Records why the reload failed and returns `error.ReloadFailed`, for a reload that fails
/// without running a command. Too-long messages are cut short, like Diagnostics does.
pub fn fail(reloader: *Reloader, comptime format: []const u8, arguments: anytype) Error {
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

test "a command running past the timeout is killed and fails the reload" {
    var reloader: Reloader = .{ .io = testing.io, .timeout = .fromMilliseconds(50) };
    const started = std.Io.Timestamp.now(testing.io, .awake);
    try testing.expectError(error.ReloadFailed, reloader.run(&.{ "sleep", "30" }));
    try testing.expectEqualStrings("'sleep 30' ran longer than 50 ms, so kosm stopped it", reloader.failure());
    try testing.expect(started.untilNow(testing.io, .awake).toMilliseconds() < 5000);
}

test "a command that cannot start fails naming it" {
    var reloader: Reloader = .{ .io = testing.io };
    try testing.expectError(error.ReloadFailed, reloader.run(&.{"kosm-test-no-such-program"}));
    try testing.expectEqualStrings("cannot run 'kosm-test-no-such-program': FileNotFound", reloader.failure());
    try testing.expectError(error.ReloadFailed, reloader.run(&.{}));
    try testing.expectEqualStrings("the reload command is empty", reloader.failure());
}

test "arguments starting with ~/ expand to the home directory" {
    var reloader: Reloader = .{ .io = testing.io, .home = "/home/test" };
    try testing.expectError(error.ReloadFailed, reloader.run(&.{ "false", "~/kosm-test", "~x" }));
    try testing.expectEqualStrings("'false /home/test/kosm-test ~x' exited with code 1", reloader.failure());
}
