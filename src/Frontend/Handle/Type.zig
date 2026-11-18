//! The type of a handle's value, as a table of what a script can do with it. Kosm builds one
//! per Zig type by reflection; a frontend only calls it.

const Loose = @import("../../Loose.zig");
const Call = @import("../Call.zig");
const Function = @import("../Function.zig");
const Handle = @import("../Handle.zig");

/// `Handle.id` of the Zig type.
id: *const anyopaque,
/// As the Zig source declares it, for messages and completion: "kosm_kitty.App", "kosm.Color".
name: []const u8,
/// The names a script reads and sets: a struct's fields or a union's tags; empty for a list.
fields: []const []const u8 = &.{},
/// Whether the value is a list, whose items `length` counts.
list: bool = false,
/// Functions taking the value as their first argument (`color:mix(other, 0.5)`), which a
/// frontend passes the handle itself to.
methods: []const Function = &.{},
/// What `key` holds: a scalar as itself, an enum as its name, null as null, and a struct, union
/// or list as a handle into the value, so setting its fields changes this value.
get: *const fn (call: *Call, pointer: *anyopaque, key: Handle.Key) Call.Error!Loose,
/// Sets what `key` holds as `kosm.assign` would, all or nothing.
set: *const fn (call: *Call, pointer: *anyopaque, key: Handle.Key, value: Loose) Call.Error!void,
/// How many items a list holds; 0 for anything else.
length: *const fn (pointer: *anyopaque) usize,

/// The method named `name`, or null.
pub fn method(handle_type: *const @This(), name: []const u8) ?Function {
    for (handle_type.methods) |candidate| {
        if (@import("std").mem.eql(u8, candidate.name, name)) return candidate;
    }
    return null;
}
