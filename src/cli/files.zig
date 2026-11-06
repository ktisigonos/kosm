//! Writing the config project's own files.

const std = @import("std");

/// Writes `bytes` to `path` atomically, keeping an existing file's permissions and creating
/// missing parent directories.
pub fn replace(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const permissions: std.Io.File.Permissions = if (cwd.statFile(io, path, .{})) |stat| stat.permissions else |err| switch (err) {
        error.FileNotFound => .default_file,
        else => return err,
    };
    var atomic = try cwd.createFileAtomic(io, path, .{ .permissions = permissions, .replace = true, .make_path = true });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.replace(io);
}
