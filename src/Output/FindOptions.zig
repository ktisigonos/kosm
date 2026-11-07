//! Which files `find` picks (D79, D95).

/// A glob of existing files: `~/...` or absolute, `*` inside a name, `**` for any depth (D79).
files: []const u8,
/// Globs of files to leave out, written like `files` (D33).
exclude: []const []const u8 = &.{},
