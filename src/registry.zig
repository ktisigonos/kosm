//! The functions of a run that plain data refers to by number (a modifier's own code, a palette
//! style's), so the data a script holds never points at code or at memory it could change.

const std = @import("std");
const keep = @import("keep.zig");

/// A list of functions of shape `Run`, each kept with a copy of its fields. `Run` takes the
/// fields as `*const anyopaque` first.
pub fn Registry(comptime Run: type) type {
    return struct {
        /// A function `add` kept: its code and its fields.
        pub const Entry = struct {
            run: *const Run,
            fields: *const anyopaque,
        };

        /// Every function `add` kept. A global, because a kosmos takes no allocator; it lives as
        /// long as the lists `kosm.keep` keeps.
        var entries: std.ArrayList(Entry) = .empty;

        /// Keeps `run` with a copy of `fields` for the whole run and returns its number.
        pub fn add(comptime T: type, run: *const Run, fields: T) usize {
            const kept = keep.keep(T, &.{fields});
            // A kosmos cannot handle running out of memory; kosm stops with this message instead.
            entries.append(keep.allocator(), .{ .run = run, .fields = &kept[0] }) catch @panic("kosm: out of memory keeping a function");
            return entries.items.len - 1;
        }

        /// The function numbered `id`, or null when `add` gave no such number.
        pub fn get(id: usize) ?Entry {
            if (id >= entries.items.len) return null;
            return entries.items[id];
        }
    };
}
