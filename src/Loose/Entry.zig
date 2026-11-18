//! One key and its value in a `Loose` table.

const Loose = @import("../Loose.zig");

/// The field name, or a union's tag.
key: []const u8,
/// What the field is set to.
value: Loose,
