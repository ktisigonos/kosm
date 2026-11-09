//! Which files `edit` changes and how values are spelled in them.

const Format = @import("../Format.zig");

/// A glob of existing files: `~/...` or absolute, `*` inside a name, `**` for any depth.
files: []const u8,
/// Globs of files to leave out, written like `files`.
exclude: []const []const u8 = &.{},
/// The adapter's name ("json"); by default the adapter claiming the extension of `files`.
lang: ?[]const u8 = null,
/// How values are spelled; fields left null take the adapter's, then kosm's.
format: Format = .{},
