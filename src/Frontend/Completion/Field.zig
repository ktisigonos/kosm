//! One field of a record, or one tag of a union, as `Completion` describes it.

const Completion = @import("../Completion.zig");

name: []const u8,
/// The field's doc comment, without the slashes; null when it has none or its source could
/// not be found.
doc: ?[]const u8 = null,
/// What it takes; null for a union's tag without a value.
type: ?Completion.Type,
