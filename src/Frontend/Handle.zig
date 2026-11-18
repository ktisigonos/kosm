//! A Zig value a script holds by reference: a tree, an app, a theme, a color. Kosm keeps the
//! value typed in its arena; a script reads and sets its fields, items and methods through
//! `type`, and gives the handle back as an argument or a field's value, which copies it.

const Handle = @This();

/// The value, of the type `type` describes. Valid for the whole run.
pointer: *anyopaque,
/// What the value is and how a script reaches into it.
type: *const Type,

/// The type of a handle's value, as a table of what a script can do with it.
pub const Type = @import("Handle/Type.zig");

/// What a script names inside a handle: a field (or a union's tag) by name, or a list's item
/// by position from 0.
pub const Key = union(enum) {
    field: []const u8,
    item: usize,
};

/// One identity per Zig type, which `Type.id` holds, so a handle's type can be checked without
/// knowing its table.
pub fn id(comptime T: type) *const anyopaque {
    return &Identity(T).byte;
}

fn Identity(comptime T: type) type {
    return struct {
        // Makes the struct, and so `byte`, distinct for every `T`.
        const Of = T;
        var byte: u8 = 0;
    };
}

/// The value as a `T`, or null when the handle holds another type.
pub fn as(handle: Handle, comptime T: type) ?*T {
    if (handle.type.id != id(T)) return null;
    return @ptrCast(@alignCast(handle.pointer));
}

test "every type has an identity of its own" {
    const std = @import("std");
    try std.testing.expect(id(u8) == id(u8));
    try std.testing.expect(id(u8) != id(u16));
    try std.testing.expect(id(struct { a: u8 }) != id(struct { a: u8 }));
}
