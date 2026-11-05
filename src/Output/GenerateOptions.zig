//! Where `generate` writes and how (D64).

const Format = @import("../Format.zig");

/// The file to own whole: `~/...` or an absolute path.
file: []const u8,
/// The adapter's name ("css"); by default the adapter claiming the file's extension (D26).
lang: ?[]const u8 = null,
/// How values are spelled; fields left null take the adapter's, then kosm's (D70).
format: Format = .{},
