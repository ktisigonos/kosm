//! Which files `find` picks.

/// A glob of existing files: `~/...` or absolute, `*` inside a name, `**` for any depth.
files: []const u8,
/// Globs of files to leave out, written like `files`.
exclude: []const []const u8 = &.{},
