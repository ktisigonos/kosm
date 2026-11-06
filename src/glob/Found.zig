//! One file a selector glob picked.

/// The path as the glob reached it, symlinks kept.
path: []const u8,
/// The path with every symlink resolved, which tells two routes to one file apart.
real: []const u8,
