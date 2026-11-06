//! Which files `edit` changes and how values are spelled in them (D79).

const Format = @import("../Format.zig");

/// A glob of existing files: `~/...` or absolute, `*` inside a name, `**` for any depth (D79).
files: []const u8,
/// Globs of files to leave out, written like `files` (D33).
exclude: []const []const u8 = &.{},
/// The adapter's name ("json"); by default the adapter claiming the extension of `files` (D26).
lang: ?[]const u8 = null,
/// How values are spelled; fields left null take the adapter's, then kosm's (D70).
format: Format = .{},
