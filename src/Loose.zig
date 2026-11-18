//! A value with no Zig type yet, as a frontend reads it from a script or `--set` from the
//! command line, for `kosm.assign` to put into a typed tree.

const Loose = @This();

/// What the value is.
value: Kind,
/// Where it was written, put before messages about it (`personal.lua:12`, `--set`); null
/// takes the origin of the value holding it.
origin: ?[]const u8 = null,

/// One key and its value in a `table`.
pub const Entry = @import("Loose/Entry.zig");

pub const Kind = union(enum) {
    /// Fields set by name; the fields it leaves out keep their value.
    table: []const Entry,
    /// Items replacing a whole list.
    list: []const Loose,
    /// Text for a text field, an enum or union tag, or a color.
    string: []const u8,
    /// Text read as the field's type, the way a command-line flag is: `0.5`, `true`, `sky`.
    /// `null` clears an optional.
    text: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    /// Clears an optional field.
    null,
    /// A Zig value a script holds, copied into a field of the same type.
    handle: Handle,
};

const Handle = @import("Frontend/Handle.zig");
