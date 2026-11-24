//! One file an apply will write: where, its contents before, the edits apps planned in it
//!, and its contents after.

const File = @This();

const std = @import("std");
const Edit = @import("Edit.zig");

/// Absolute path, with `~` expanded.
path: []const u8,
/// The path as the app wrote it, for messages and diffs.
display_path: []const u8,
/// Contents on disk when the plan was made, or null when the file does not exist.
old: ?[]const u8,
/// Every planned edit, in the order planned.
edits: std.ArrayList(Edit) = .empty,
/// Contents after the apply: `old` with every edit applied.
new: []const u8 = "",
/// Whether the apply makes the file executable, as an app asked.
executable: bool = false,
/// Whether the file on disk is executable now; false when it does not exist.
was_executable: bool = false,
/// The folder diffs and reports show this file under, as one line with the others there, or
/// null to show the file itself.
group: ?[]const u8 = null,

/// The contents edits are ranges of: `old`, or empty for a missing file.
pub fn current(file: File) []const u8 {
    return file.old orelse "";
}

/// Whether committing would change the file on disk.
pub fn changed(file: File) bool {
    const old = file.old orelse return true;
    if (file.executable and !file.was_executable) return true;
    return !sameBytes(old, file.new);
}

/// Whether `first` and `second` hold the same bytes. libc's `memcmp` is optimized even in a
/// debug build, where `std.mem.eql` made comparing every planned file a tenth of an apply.
fn sameBytes(first: []const u8, second: []const u8) bool {
    if (first.len != second.len) return false;
    if (first.len == 0) return true;
    return memcmp(first.ptr, second.ptr, first.len) == 0;
}

extern "c" fn memcmp(first: [*]const u8, second: [*]const u8, length: usize) c_int;

/// The first planned edit that `edit` clashes with, if any.
pub fn clash(file: *const File, edit: Edit) ?*const Edit {
    for (file.edits.items) |*planned| {
        if (planned.clashes(edit)) return planned;
    }
    return null;
}

/// Whether a planned edit inserts at `offset`.
pub fn insertsAt(file: File, offset: usize) bool {
    for (file.edits.items) |planned| {
        if (planned.start == offset and planned.end == offset) return true;
    }
    return false;
}

/// The app planning every edit of the file, or empty when several apps do.
pub fn owner(file: File) []const u8 {
    if (file.edits.items.len == 0) return "";
    const first = file.edits.items[0].owner;
    for (file.edits.items[1..]) |planned| {
        if (!std.mem.eql(u8, planned.owner, first)) return "";
    }
    return first;
}
