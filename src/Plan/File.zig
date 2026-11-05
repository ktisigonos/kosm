//! One file an apply will write: where, who asked, and its contents before and after.

const File = @This();

const std = @import("std");

/// Absolute path, with `~` expanded.
path: []const u8,
/// The path as the app wrote it, for messages and diffs.
display_path: []const u8,
/// The app that writes it, as its path in the kosmos tree.
owner: []const u8,
/// Contents on disk when the plan was made, or null when the file does not exist.
old: ?[]const u8,
/// Contents after the apply.
new: []const u8,

/// Whether committing would change the file on disk (D35).
pub fn changed(file: File) bool {
    const old = file.old orelse return true;
    return !std.mem.eql(u8, old, file.new);
}
