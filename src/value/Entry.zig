//! One key and its value in a `Value.table`, in the order the app's struct declares them.

const Value = @import("../value.zig").Value;

/// The field name.
key: []const u8,
/// The field's value.
value: Value,
