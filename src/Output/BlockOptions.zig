//! Where `block` writes and how (D71, D72).

const Format = @import("../Format.zig");

/// The file holding the block: `~/...` or an absolute path. Created when missing.
file: []const u8,
/// Names the block in its markers: letters, digits, `_`, `-` and `.`; unique in the file.
id: []const u8,
/// The adapter's name ("kitty"); by default the adapter claiming the file's extension (D26).
lang: ?[]const u8 = null,
/// How values are spelled; fields left null take the adapter's, then kosm's (D70).
format: Format = .{},
