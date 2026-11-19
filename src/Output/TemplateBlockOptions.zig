//! Where `templateBlockValue` writes, and the template it writes.

const Format = @import("../Format.zig");
const BlockOptions = @import("BlockOptions.zig");

/// The file holding the block: `~/...` or an absolute path. Created when missing, unless
/// `missing` is `.skip`.
file: []const u8,
/// Names the block in its markers: letters, digits, `_`, `-` and `.`; unique in the file.
id: []const u8,
/// The template, its `kosm.<path>` placeholders resolved against the values given with it.
text: []const u8,
/// The adapter's name ("kitty"); by default the adapter claiming the file's extension.
lang: ?[]const u8 = null,
/// How values are spelled; fields left null take the adapter's, then kosm's.
format: Format = .{},
/// What happens when the file does not exist. Default: `.create`.
missing: BlockOptions.Missing = .create,
