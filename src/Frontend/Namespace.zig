//! A name a script reaches functions, values and other namespaces through: a package
//! (`kosm_kitty`), a type (`kosm.Theme`), or a kosmos and its variants (`kosmoi.personal`).

const Namespace = @This();

const std = @import("std");
const Function = @import("Function.zig");

/// As the script spells it, from the global down: "kosm.Theme", "kosmoi.personal".
name: []const u8,
/// What calling the namespace itself does (`kosmoi.personal(params)`), or null.
call: ?Function = null,
entries: []const Entry = &.{},

/// One name in a namespace.
pub const Entry = @import("Namespace/Entry.zig");

/// The entry named `name`, or null.
pub fn find(namespace: Namespace, name: []const u8) ?Entry {
    for (namespace.entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry;
    }
    return null;
}
