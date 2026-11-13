//! One file or link `tree` found.

/// The path below the folder `tree` was given, with `/` between folders (`apps/scalable/x.svg`).
path: []const u8,
/// What a link points to, as written in it; null for a file.
target: ?[]const u8,
