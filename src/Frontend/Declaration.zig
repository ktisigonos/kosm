//! What a script declares, as a frontend reads it without calling any of its functions: the
//! fields of an app, modifier, palette style or variation family, with their types, defaults
//! and doc comments, and the functions it gives. Kosm writes the Zig module it is used through
//! from it.

const Declaration = @This();

/// The fields, in the order the script writes them.
fields: []const Field,
/// The names of the functions the script gives: an app's "from", "apply", and "reload" when it
/// reloads its program; a modifier's or style's "apply"; a family's "from".
functions: []const []const u8,
/// The doc comment of what it declares, without the comment markers; null when it has none.
doc: ?[]const u8 = null,

/// One field of what it declares.
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
    /// default is `.{}`, so a struct whose fields all have defaults, or a table the field gives.
    zig: []const u8,
    /// A struct the same script declares, by its name ("Base", "Params"); its default is `.{}`.
    declared: []const u8,
    /// A Zig function giving a type, called with these types: `kosm.Kosmos(Base)`. Its default
    /// is `.{}`, or a table the field gives.
    applied: Applied,

    /// A Zig function giving a type, and what it is called with.
    pub const Applied = struct {
        /// The function by the name a script reaches it under: "kosm.Kosmos".
        function: []const u8,
        arguments: []const Type,
    };
};

/// Whether the script gives the function `name`.
pub fn gives(declaration: Declaration, name: []const u8) bool {
    for (declaration.functions) |function| {
        if (@import("std").mem.eql(u8, function, name)) return true;
    }
    return false;
}
