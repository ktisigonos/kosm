//! Where `block` writes and how.

const Format = @import("../Format.zig");

/// The file holding the block: `~/...` or an absolute path. Created when missing, unless
/// `missing` is `.skip`.
file: []const u8,
/// Names the block in its markers: letters, digits, `_`, `-` and `.`; unique in the file.
id: []const u8,
/// The adapter's name ("kitty"); by default the adapter claiming the file's extension.
lang: ?[]const u8 = null,
/// How values are spelled; fields left null take the adapter's, then kosm's.
format: Format = .{},
/// What happens when the file does not exist. Default: `.create`.
missing: Missing = .create,

/// What a block does with a file that does not exist.
pub const Missing = enum {
    /// Creates the file holding only the block.
    create,
    /// Writes nothing and warns, leaving the file for its program to create.
    skip,
};
