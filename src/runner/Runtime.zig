//! What a script's calls into Zig need while it runs: where a kosmos it calls loads its images
//! and files from. The library hands it to every call as `Call.state`.

const Runtime = @This();

const std = @import("std");
const kosm = @import("kosm");
const Places = @import("Places.zig");
const images = @import("images.zig");
const kosmos_call = @import("kosmos_call.zig");

/// Holds everything the calls build, for the whole run.
arena: std.mem.Allocator,
io: std.Io,
/// What `~/` stands for.
home: []const u8,
/// The config project, which `~~/` stands for.
config: []const u8,
/// The folder of every package and local module, which `~~<name>/` stands for.
folders: []const Places.Folder,
/// The absolute folder of the script being read, which relative paths it gives start from.
scripts_folder: []const u8,
/// The folder decoded images are cached in; null caches nothing.
cache: ?[]const u8,
/// Where a failed cache write is reported.
stderr: *std.Io.Writer,
/// The kosmoi being built, so that one building on itself fails naming the circle.
building: kosmos_call.Building = .{},
/// Builds the kosmoi that the `Params` of a kosmos a script calls name.
kosmoi: ?kosmos_call.Builder = null,

/// What loading the images and files of a kosmos declared in `folder` needs.
pub fn loading(runtime: Runtime, folder: []const u8, diagnostics: *kosm.Diagnostics) images.Context {
    return .{
        .arena = runtime.arena,
        .io = runtime.io,
        .places = .{ .home = runtime.home, .config = runtime.config, .kosmos = folder, .folders = runtime.folders },
        .cache = runtime.cache,
        .diagnostics = diagnostics,
        .stderr = runtime.stderr,
    };
}
