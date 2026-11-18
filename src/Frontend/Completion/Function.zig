//! A function a script may call, as `Completion` describes it.

const Completion = @import("../Completion.zig");

name: []const u8,
/// The function's doc comment; null when it has none.
doc: ?[]const u8 = null,
/// Named as the source names them; a parameter whose type a script cannot spell has no type.
parameters: []const Completion.Field = &.{},
/// What it returns; null for nothing.
result: ?Completion.Type = null,
