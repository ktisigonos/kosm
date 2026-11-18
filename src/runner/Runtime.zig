//! What a script's calls into Zig need while it runs: where a kosmos it calls loads its images
//! and files from. The library hands it to every call as `Call.state`.

const std = @import("std");
const Places = @import("Places.zig");

/// Holds everything the calls build, for the whole run.
arena: std.mem.Allocator,
io: std.Io,
/// What `~/` stands for.
home: []const u8,
/// The config project, which `~~/` stands for.
config: []const u8,
/// The folder of every package and local module, which `~~<name>/` stands for.
folders: []const Places.Folder,
/// The folder relative paths a script gives start from.
scripts_folder: []const u8,
/// The folder decoded images are cached in; null caches nothing.
cache: ?[]const u8,
/// Where a failed cache write is reported.
stderr: *std.Io.Writer,
