//! What kosm hands a frontend's `complete`: every type a script may set, described as plain
//! data with the doc comments of its Zig source, so the frontend can write the files an editor
//! completes scripts from without knowing any app.

const Completion = @This();

const std = @import("std");

/// Every struct a script may set, each once, named as its Zig source declares it
/// ("kosm_kitty.App", or "kosm_kitty.App.fonts" for one written inline in a field).
records: []const Record,
/// Every Zig kosmos a script may build on.
kosmoi: []const Kosmos,
/// The record of the overrides a script building on no kosmos gives: one field per app a
/// theme alone builds.
standalone: []const u8,
/// The record of the theme input such a script gives.
theme: []const u8,
/// Every namespace of the library a script calls, globals (no dot in their name) included.
namespaces: []const Namespace = &.{},

/// A struct and its fields.
pub const Record = @import("Completion/Record.zig");
/// One field of a record, or one tag of a union.
pub const Field = @import("Completion/Field.zig");
/// A Zig kosmos and the records of its parameters and tree.
pub const Kosmos = @import("Completion/Kosmos.zig");
/// A function a script may call.
pub const Function = @import("Completion/Function.zig");
/// A namespace of the library a script calls.
pub const Namespace = @import("Completion/Namespace.zig");
/// A file a frontend writes for an editor: its path and contents.
pub const File = @import("Completion/File.zig");

/// What a field takes, as a script writes it.
pub const Type = union(enum) {
    boolean,
    integer,
    number,
    text,
    /// A color as text: `#rrggbb`, `rgb(...)`, `hsl(...)` or `oklch(...)`.
    color,
    /// A color as `color` takes it, or the name of a hue of the palette.
    color_or_hue,
    /// The path of a file kosm reads before the kosmos runs (an image in `Params`).
    path,
    /// Any value a program's setting takes: a table, list, string, number or boolean.
    value,
    /// One of these names.
    choice: []const []const u8,
    /// A union: the name of a tag without a value, or a table of one tag and its value. A tag
    /// without a value is a field typed null.
    variant: []const Field,
    /// The record of this name.
    record: []const u8,
    /// A list of items of this type.
    list: *const Type,
    /// This type, or null (`kosm.null` in a script) for "not set".
    optional: *const Type,
    /// The namespace of this name.
    namespace: []const u8,
};

/// The record named `name`, or null.
pub fn find(completion: Completion, name: []const u8) ?Record {
    for (completion.records) |record| {
        if (std.mem.eql(u8, record.name, name)) return record;
    }
    return null;
}
