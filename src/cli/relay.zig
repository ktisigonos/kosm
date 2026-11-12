//! `kosm relay <file>`: a native messaging host for browser extensions. The browser starts it
//! while it runs; it sends the file as one message at once and again whenever the file changes,
//! and exits when the browser closes its end. It knows nothing about any browser or app.

const std = @import("std");

/// How often the file is checked for a change, in milliseconds.
const check_interval_milliseconds = 500;
/// The largest message a native messaging host may send to Firefox.
const message_limit = 1024 * 1024;

/// Runs the host; returns the exit status after printing what went wrong. The browser shows
/// a host's stderr in its console.
pub fn relay(init: std.process.Init, path: []const u8, stderr: *std.Io.Writer) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var file: Watched = .{ .path = path };
    while (true) {
        file.sendIfChanged(init.io, init.gpa, &stdout.interface) catch |err| switch (err) {
            // The browser is gone.
            error.WriteFailed => return 0,
            error.MessageTooLong => {
                try stderr.print("error: kosm relay: {s} is over {d} bytes, the most a browser accepts\n", .{ path, message_limit });
                return 1;
            },
            else => {
                try stderr.print("error: kosm relay: cannot read {s}: {s}\n", .{ path, @errorName(err) });
                return 1;
            },
        };
        if (try closedWithin(std.Io.File.stdin().handle, check_interval_milliseconds)) return 0;
    }
}

/// The file a relay forwards, and what it last sent.
const Watched = struct {
    path: []const u8,
    /// The state of the file when it was last sent, or null before the first message.
    sent: ?Stamp = null,

    /// What tells one version of a file from the next without reading it.
    const Stamp = struct {
        modified: i96,
        size: u64,
        inode: std.Io.File.INode,
    };

    const Error = std.Io.Dir.StatFileError || std.Io.Dir.ReadFileAllocError || std.Io.Writer.Error || error{MessageTooLong};

    /// Sends the file as one message when it is new or changed since the last one. A missing
    /// file sends nothing: the extension keeps what it had until the file appears.
    fn sendIfChanged(watched: *Watched, io: std.Io, allocator: std.mem.Allocator, output: *std.Io.Writer) Error!void {
        const stat = std.Io.Dir.cwd().statFile(io, watched.path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        const stamp: Stamp = .{ .modified = stat.mtime.nanoseconds, .size = stat.size, .inode = stat.inode };
        if (watched.sent) |sent| if (std.meta.eql(sent, stamp)) return;
        if (stat.size > message_limit) return error.MessageTooLong;
        const contents = std.Io.Dir.cwd().readFileAlloc(io, watched.path, allocator, .limited(message_limit + 1)) catch |err| switch (err) {
            // Replaced between the stat and the read; the next check sends the new one.
            error.FileNotFound => return,
            error.StreamTooLong => return error.MessageTooLong,
            else => return err,
        };
        defer allocator.free(contents);
        if (contents.len > message_limit) return error.MessageTooLong;
        try writeMessage(output, contents);
        watched.sent = stamp;
    }
};

/// Writes one native message: its length as a native-endian u32, then its bytes.
fn writeMessage(output: *std.Io.Writer, message: []const u8) std.Io.Writer.Error!void {
    try output.writeInt(u32, @intCast(message.len), @import("builtin").cpu.arch.endian());
    try output.writeAll(message);
    try output.flush();
}

/// Waits up to `milliseconds` for `input` to close, discarding anything sent on it (the
/// extension sends nothing a relay needs). True once it is closed.
fn closedWithin(input: std.posix.fd_t, milliseconds: i32) std.posix.PollError!bool {
    var descriptors = [_]std.posix.pollfd{.{ .fd = input, .events = std.posix.POLL.IN, .revents = 0 }};
    if (try std.posix.poll(&descriptors, milliseconds) == 0) return false;
    const events = descriptors[0].revents;
    if (events & std.posix.POLL.IN != 0) {
        var discarded: [4096]u8 = undefined;
        const read = std.posix.read(input, &discarded) catch return true;
        return read == 0;
    }
    return events & (std.posix.POLL.HUP | std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0;
}

const testing = std.testing;

fn testWatched(tmp: *testing.TmpDir, name: []const u8) !Watched {
    const directory = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    return .{ .path = try std.Io.Dir.path.join(testing.allocator, &.{ directory, name }) };
}

test "a message is the native-endian length, then the bytes" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try writeMessage(&output.writer, "{\"a\":1}");
    const written = output.written();
    try testing.expectEqual(7, std.mem.readInt(u32, written[0..4], @import("builtin").cpu.arch.endian()));
    try testing.expectEqualStrings("{\"a\":1}", written[4..]);
}

test "relay sends the file once, and again only after it changes" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var watched = try testWatched(&tmp, "values.json");
    defer testing.allocator.free(watched.path);
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();

    try watched.sendIfChanged(testing.io, testing.allocator, &output.writer);
    try testing.expectEqual(0, output.written().len);

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "values.json", .data = "{\"a\":1}" });
    try watched.sendIfChanged(testing.io, testing.allocator, &output.writer);
    try watched.sendIfChanged(testing.io, testing.allocator, &output.writer);
    try testing.expectEqual(4 + 7, output.written().len);

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "values.json", .data = "{\"a\":22}" });
    try watched.sendIfChanged(testing.io, testing.allocator, &output.writer);
    try testing.expectEqual(4 + 7 + 4 + 8, output.written().len);
    try testing.expectEqualStrings("{\"a\":22}", output.written()[15..]);
}

test "relay refuses a file over the browser's message limit" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var watched = try testWatched(&tmp, "big.json");
    defer testing.allocator.free(watched.path);
    const big = try testing.allocator.alloc(u8, message_limit + 1);
    defer testing.allocator.free(big);
    @memset(big, ' ');
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "big.json", .data = big });
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try testing.expectError(error.MessageTooLong, watched.sendIfChanged(testing.io, testing.allocator, &output.writer));
    try testing.expectEqual(0, output.written().len);
}

test "relay sees its input close, and keeps going while it is open" {
    var ends: [2]std.posix.fd_t = undefined;
    try testing.expectEqual(0, std.os.linux.pipe(&ends));
    defer _ = std.os.linux.close(ends[0]);
    try testing.expect(!try closedWithin(ends[0], 0));
    _ = std.os.linux.write(ends[1], "x", 1);
    try testing.expect(!try closedWithin(ends[0], 0));
    _ = std.os.linux.close(ends[1]);
    try testing.expect(try closedWithin(ends[0], 0));
}
