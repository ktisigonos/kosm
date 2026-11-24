//! Keeps two applies from planning and committing at once, and lets the newest one win: each
//! apply says it started in one file of kosm's state directory, then holds a lock on another
//! until it has finished. An apply that sees a newer one started before it commits writes
//! nothing, so `kosm apply nord` followed at once by `kosm apply everforest` ends on everforest.

const std = @import("std");

/// The name of the lock file in kosm's state directory.
pub const file_name = "apply.lock";
/// The name of the file holding the newest apply's token in kosm's state directory.
pub const latest_file_name = "apply.latest";

/// The mark one apply leaves in the latest file, to tell later whether a newer one started.
pub const Latest = struct {
    path: []const u8,
    token: [token_length]u8,

    const token_length = 16;

    /// Records an apply starting now in the file at `path`, creating its folders, so every
    /// older apply's `isNewest` is false from now on.
    pub fn announce(io: std.Io, path: []const u8) !Latest {
        var random: u64 = undefined;
        io.random(std.mem.asBytes(&random));
        const latest: Latest = .{ .path = path, .token = std.fmt.hex(random) };
        var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .make_path = true, .replace = true });
        defer atomic.deinit(io);
        try atomic.file.writeStreamingAll(io, &latest.token);
        try atomic.replace(io);
        return latest;
    }

    /// Whether no apply started after this one. When the file cannot be read, the apply goes
    /// on, as it would have without the check.
    pub fn isNewest(latest: Latest, io: std.Io) bool {
        var buffer: [token_length + 1]u8 = undefined;
        const contents = std.Io.Dir.cwd().readFile(io, latest.path, &buffer) catch return true;
        return std.mem.eql(u8, contents, &latest.token);
    }
};

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

test "an apply is the newest until another one starts" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(testing.io, &root_buffer)];
    const path = try std.Io.Dir.path.join(testing.allocator, &.{ root, "state/kosm", latest_file_name });
    defer testing.allocator.free(path);

    const nord = try Latest.announce(testing.io, path);
    try testing.expect(nord.isNewest(testing.io));
    const everforest = try Latest.announce(testing.io, path);
    try testing.expect(!nord.isNewest(testing.io));
    try testing.expect(everforest.isNewest(testing.io));
}
