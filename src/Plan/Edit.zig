//! One change an app plans inside a file: a byte range of its current contents and the bytes
//! that replace it (D73).

const Edit = @This();

const std = @import("std");

/// What the edit owns, which decides what it clashes with (D38).
target: Target,
/// First byte replaced, in the file's current contents.
start: usize,
/// One past the last byte replaced; equal to `start` for an insertion.
end: usize,
/// The bytes written in place of the range.
content: []const u8,
/// The app that asked for it, as its path in the kosmos tree.
owner: []const u8,

/// What an edit owns inside its file.
pub const Target = union(enum) {
    /// The whole file (`generate`, `template`).
    whole_file,
    /// The block with this id (D72).
    block: []const u8,
    /// A value set by path (D31, D35); clashes only where the bytes overlap.
    value,
};

/// Whether the two edits may not both be planned (D38, D73).
pub fn clashes(edit: Edit, other: Edit) bool {
    if (edit.target == .whole_file or other.target == .whole_file) return true;
    if (edit.target == .block and other.target == .block and std.mem.eql(u8, edit.target.block, other.target.block)) return true;
    return edit.start < other.end and other.start < edit.end;
}

fn testEdit(id: []const u8, start: usize, end: usize) Edit {
    return .{ .target = .{ .block = id }, .start = start, .end = end, .content = "", .owner = "app" };
}

test "edits clash on overlapping bytes, a shared block id or a whole file" {
    const testing = std.testing;
    try testing.expect(testEdit("a", 0, 5).clashes(testEdit("b", 4, 8)));
    try testing.expect(!testEdit("a", 0, 4).clashes(testEdit("b", 4, 8)));
    try testing.expect(!testEdit("a", 10, 10).clashes(testEdit("b", 10, 10)));
    try testing.expect(testEdit("a", 10, 10).clashes(testEdit("a", 10, 10)));
    const whole: Edit = .{ .target = .whole_file, .start = 0, .end = 0, .content = "", .owner = "app" };
    try testing.expect(whole.clashes(testEdit("b", 10, 10)));
    const value: Edit = .{ .target = .value, .start = 2, .end = 6, .content = "", .owner = "app" };
    try testing.expect(value.clashes(testEdit("a", 5, 9)));
    try testing.expect(!value.clashes(testEdit("a", 6, 9)));
    try testing.expect(!value.clashes(.{ .target = .value, .start = 0, .end = 2, .content = "", .owner = "app" }));
}
