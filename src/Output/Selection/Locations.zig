//! Prints where matches are, `~/a.json:3, ~/b.json:7`, for messages naming them.

const Locations = @This();

const std = @import("std");
const Match = @import("../Match.zig");

matches: []const Match,

/// More are summed up as "and N more".
const max_shown = 5;

/// Prints up to `max_shown` locations.
pub fn format(locations: Locations, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const shown = @min(locations.matches.len, max_shown);
    for (locations.matches[0..shown], 0..) |match, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}:{d}", .{ match.file, match.line });
    }
    if (locations.matches.len > shown) try writer.print(" and {d} more", .{locations.matches.len - shown});
}
