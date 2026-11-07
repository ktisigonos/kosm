//! The distinct colors that printing one file or value clipped to the gamut (D48), so kosm
//! can warn about each once (D88). Fixed capacity, so adapters' `Context` holds it without an
//! allocator; colors past the capacity are only counted.

const ClippedColors = @This();

const std = @import("std");
const Color = @import("Color.zig");

entries: [capacity]Entry = undefined,
length: usize = 0,
/// Distinct colors that did not fit in `entries`.
uncounted: usize = 0,

/// The most distinct colors kept, each warned about on its own.
pub const capacity = 16;

/// One clipped color.
pub const Entry = struct {
    color: Color,
    /// How often it was printed.
    count: usize,
    /// The 1-based template line it was first printed on, or 0 when no line is known.
    line: usize,
};

/// Notes that `color` was printed clipped, on template `line` (0 when there is none).
pub fn add(clipped: *ClippedColors, color: Color, line: usize) void {
    for (clipped.entries[0..clipped.length]) |*entry| {
        if (std.meta.eql(entry.color, color)) {
            entry.count += 1;
            return;
        }
    }
    if (clipped.length == capacity) {
        clipped.uncounted += 1;
        return;
    }
    clipped.entries[clipped.length] = .{ .color = color, .count = 1, .line = line };
    clipped.length += 1;
}

/// The colors kept, in the order they were first printed.
pub fn list(clipped: *const ClippedColors) []const Entry {
    return clipped.entries[0..clipped.length];
}

const testing = std.testing;

test "a color printed twice is kept once with its count and first line" {
    const vivid: Color = .{ .lightness = 0.9, .chroma = 0.4, .hue = 140 };
    const other: Color = .{ .lightness = 0.9, .chroma = 0.4, .hue = 20 };
    var clipped: ClippedColors = .{};
    clipped.add(vivid, 3);
    clipped.add(other, 4);
    clipped.add(vivid, 9);
    try testing.expectEqual(2, clipped.list().len);
    try testing.expectEqual(2, clipped.list()[0].count);
    try testing.expectEqual(3, clipped.list()[0].line);
}

test "colors past the capacity are counted" {
    var clipped: ClippedColors = .{};
    for (0..capacity + 3) |index| clipped.add(.{ .lightness = 2, .chroma = 0, .hue = @floatFromInt(index) }, 0);
    try testing.expectEqual(capacity, clipped.list().len);
    try testing.expectEqual(3, clipped.uncounted);
}
