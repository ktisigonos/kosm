//! The mark one apply leaves in kosm's state directory, to tell later whether a newer one
//! started. The command line makes it the moment `kosm apply` runs, before building anything,
//! and hands it to the runner, so the apply typed last wins however long each takes to build.

const Latest = @This();

const std = @import("std");

/// The file holding the newest apply's token.
path: []const u8,
token: [token_length]u8,

/// The name of the file holding the newest apply's token in kosm's state directory.
pub const file_name = "apply.latest";
/// The length of a token, in hex digits.
pub const token_length = 16;

/// Records an apply starting now in the file at `path`, creating its folders, so every older
/// apply's `isNewest` is false from now on.
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

/// The mark another process announced with `token`, as `announce` gave it; null when `token`
/// is not one.
pub fn adopt(path: []const u8, token: []const u8) ?Latest {
    if (token.len != token_length) return null;
    var latest: Latest = .{ .path = path, .token = undefined };
    @memcpy(&latest.token, token);
    return latest;
}

/// Whether no apply started after this one. When the file cannot be read, the apply goes on,
/// as it would have without the check.
pub fn isNewest(latest: Latest, io: std.Io) bool {
    var buffer: [token_length + 1]u8 = undefined;
    const contents = std.Io.Dir.cwd().readFile(io, latest.path, &buffer) catch return true;
    return std.mem.eql(u8, contents, &latest.token);
}

const testing = std.testing;

test "an apply is the newest until another one starts" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(testing.io, &root_buffer)];
    const path = try std.Io.Dir.path.join(testing.allocator, &.{ root, "state/kosm", file_name });
    defer testing.allocator.free(path);

    const nord = try announce(testing.io, path);
    try testing.expect(nord.isNewest(testing.io));
    const everforest = try announce(testing.io, path);
    try testing.expect(!nord.isNewest(testing.io));
    try testing.expect(everforest.isNewest(testing.io));
}

test "an adopted token is the newest exactly when the announced one is" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(testing.io, &root_buffer)];
    const path = try std.Io.Dir.path.join(testing.allocator, &.{ root, file_name });
    defer testing.allocator.free(path);

    const announced = try announce(testing.io, path);
    const adopted = adopt(path, &announced.token).?;
    try testing.expect(adopted.isNewest(testing.io));
    _ = try announce(testing.io, path);
    try testing.expect(!adopted.isNewest(testing.io));
    try testing.expectEqual(null, adopt(path, "short"));
    try testing.expectEqual(null, adopt(path, ""));
}
