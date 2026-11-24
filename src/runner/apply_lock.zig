//! Keeps two applies from planning and committing at once: each holds a lock on one file in
//! kosm's state directory until it has finished, and the second waits for the first.

const std = @import("std");

/// The name of the lock file in kosm's state directory.
pub const file_name = "apply.lock";

/// Takes the lock at `path`, creating the file and its folders, after saying on `stderr` that
/// it waits when another apply holds it. The lock lasts until the returned file is closed or
/// the process ends.
pub fn acquire(io: std.Io, path: []const u8, stderr: *std.Io.Writer) !std.Io.File {
    const cwd = std.Io.Dir.cwd();
    if (std.Io.Dir.path.dirname(path)) |folder| try cwd.createDirPath(io, folder);
    const file = try cwd.createFile(io, path, .{ .truncate = false });
    errdefer file.close(io);
    if (try file.tryLock(io, .exclusive)) return file;
    try stderr.writeAll("waiting for another kosm apply to finish\n");
    try stderr.flush();
    try file.lock(io, .exclusive);
    return file;
}

const testing = std.testing;

test "the lock creates its folders and is held until it is closed" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(testing.io, &root_buffer)];
    const path = try std.Io.Dir.path.join(testing.allocator, &.{ root, "state/kosm", file_name });
    defer testing.allocator.free(path);
    var stderr_buffer: [128]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);

    const held = try acquire(testing.io, path, &stderr);
    // Locks belong to each opening of the file, so a second one stands for another apply.
    const other = try std.Io.Dir.cwd().openFile(testing.io, path, .{});
    defer other.close(testing.io);
    try testing.expect(!try other.tryLock(testing.io, .exclusive));
    held.close(testing.io);
    try testing.expect(try other.tryLock(testing.io, .exclusive));
    try testing.expectEqualStrings("", stderr.buffered());
}
