//! Where `generate` writes and how (D64).

const ColorFormat = @import("../ColorFormat.zig");

/// The file to own whole: `~/...` or an absolute path.
file: []const u8,
/// The adapter's name ("css"); by default the adapter claiming the file's extension (D26).
lang: ?[]const u8 = null,
/// How colors are printed; by default the adapter's format for its language, then `hex` (D61).
color_format: ?ColorFormat = null,
