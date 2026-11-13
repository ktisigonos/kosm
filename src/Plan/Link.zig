//! One symbolic link an apply will make: where, what it points to now, and what after.

const Link = @This();

const std = @import("std");

/// Absolute path of the link, with `~` expanded.
path: []const u8,
/// The path as the app wrote it, for messages and diffs.
display_path: []const u8,
/// What the link will point to, written into it as is (relative to the link's folder, or
/// absolute).
target: []const u8,
/// What the link points to now, or null when nothing is at `path`.
old_target: ?[]const u8,
/// The app planning the link.
owner: []const u8,
/// The folder diffs and reports show this link under, as one line with the others there.
group: ?[]const u8,

/// Whether committing would change the link on disk.
pub fn changed(link: Link) bool {
    const old_target = link.old_target orelse return true;
    return !std.mem.eql(u8, old_target, link.target);
}
