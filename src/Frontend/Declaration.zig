//! What a script declares, as a frontend reads it without calling any of its functions: an
//! app's or a modifier's fields, with their types, defaults and doc comments, and the functions
//! it gives. Kosm writes the Zig module the app or modifier is used through from it.

const Declaration = @This();

/// The app's or modifier's fields, in the order the script writes them.
fields: []const Field,
/// The names of the functions the script gives: an app's "from", "apply", and "reload" when it
/// reloads its program; a modifier's "apply".
functions: []const []const u8,
/// The app's or modifier's doc comment, without the comment markers; null when it has none.
doc: ?[]const u8 = null,

/// One field of an app or modifier.
pub const Field = @import("Declaration/Field.zig");

/// What a field holds.
pub const Type = union(enum) {
    boolean,
    /// A whole number (`i64`).
    integer,
    /// A number (`f64`).
    float,
    text,
    /// This type, or null for "not set"; its default is null.
    optional: *const Type,
    /// A list of items of this type; its default is empty.
    list: *const Type,
    /// A Zig type by the name a script reaches it under ("kosm.Color", "kosm_cursor.App"); its
    /// default is `.{}`, so a struct whose fields all have defaults.
    zig: []const u8,
};

/// Whether the script gives the function `name`.
pub fn gives(declaration: Declaration, name: []const u8) bool {
    for (declaration.functions) |function| {
        if (@import("std").mem.eql(u8, function, name)) return true;
    }
    return false;
}
