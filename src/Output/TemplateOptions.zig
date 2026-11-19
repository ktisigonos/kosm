//! Where `templateValue` writes, and the template it writes.

const Format = @import("../Format.zig");

/// The file to own whole: `~/...` or an absolute path.
file: []const u8,
/// The template, its `kosm.<path>` placeholders resolved against the values given with it.
text: []const u8,
/// How values are spelled; fields left null take those of the adapter claiming the file's
/// extension, then kosm's.
format: Format = .{},
