//! The names closest to a misspelled one, and the `did you mean` naming them. Every message
//! about an unknown name (a kosmos, a field, a tag, a parameter) finds them the same way.

const std = @import("std");

/// A suggestion is at most one edit away per this many bytes of the misspelled name, rounded up
/// (`frost` takes `frozen`, three edits), so a short name gets no wild guesses.
const bytes_per_allowed_edit = 2;

/// The most edits a suggestion for a name `length` bytes long may be away; at least one.
pub fn allowedEdits(length: usize) usize {
    return @max(1, (length + bytes_per_allowed_edit - 1) / bytes_per_allowed_edit);
}

/// The edits from `name` to `candidate`, or `maxInt` when they would replace all of the shorter
/// one (`alacritty` is no `kitty`, `shade` no `hue`), so a suggestion always keeps some of both.
/// Works at compile time too.
pub fn closeness(name: []const u8, candidate: []const u8) usize {
    const edits = distance(name, candidate);
    return if (edits < @min(name.len, candidate.len)) edits else std.math.maxInt(usize);
}

/// The fewest edits from `name` to any of `known` that keeps some of both (see `closeness`);
/// `maxInt` when there is none.
pub fn closestDistance(name: []const u8, known: []const []const u8) usize {
    var closest: usize = std.math.maxInt(usize);
    for (known) |candidate| closest = @min(closest, closeness(name, candidate));
    return closest;
}

/// Whether any of `known` is close enough to `name` to suggest: at most `allowed` edits away.
pub fn hasClose(name: []const u8, known: []const []const u8, allowed: usize) bool {
    return closestDistance(name, known) <= allowed;
}

/// Prints `did you mean 'kitty'?` naming every one of `known` closest to `name` when that is at
/// most `allowed` edits away, else `otherwise` (`its fields are kitty, foot`). Print with `{f}`.
pub const Hint = struct {
    name: []const u8,
    known: []const []const u8,
    otherwise: []const u8,
    allowed: usize,

    pub fn format(shown: Hint, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const closest = closestDistance(shown.name, shown.known);
        if (closest > shown.allowed) return writer.writeAll(shown.otherwise);
        try writeChoices(writer, shown.known, Within{ .name = shown.name, .edits = closest });
    }
};

/// A `Hint` allowing as many edits as `allowedEdits` gives for `name`.
pub fn hint(name: []const u8, known: []const []const u8, otherwise: []const u8) Hint {
    return .{ .name = name, .known = known, .otherwise = otherwise, .allowed = allowedEdits(name.len) };
}

/// Picks the names exactly `edits` away from `name`.
const Within = struct {
    name: []const u8,
    edits: usize,

    fn picks(within: Within, candidate: []const u8) bool {
        return closeness(within.name, candidate) == within.edits;
    }
};

/// `did you mean 'a'?`, `'a' or 'b'`, `'a', 'b' or 'c'`: every one of `known` that
/// `filter.picks(name)` is true for, in their order.
pub fn writeChoices(writer: *std.Io.Writer, known: []const []const u8, filter: anytype) std.Io.Writer.Error!void {
    var total: usize = 0;
    for (known) |candidate| {
        if (filter.picks(candidate)) total += 1;
    }
    try writer.writeAll("did you mean ");
    var written: usize = 0;
    for (known) |candidate| {
        if (!filter.picks(candidate)) continue;
        if (written != 0) try writer.writeAll(if (written + 1 == total) " or " else ", ");
        try writer.print("'{s}'", .{candidate});
        written += 1;
    }
    try writer.writeAll("?");
}

/// The edits (insert, delete, substitute or swap two neighbours) turning `left` into `right`.
/// Works at compile time too.
pub fn distance(left: []const u8, right: []const u8) usize {
    // Three rows of the optimal string alignment table; names are short, so a fixed bound
    // keeps this allocation-free and longer names simply count as far apart.
    const max_length = 128;
    if (left.len > max_length or right.len > max_length) return std.math.maxInt(usize);
    var before_previous: [max_length + 1]usize = undefined;
    var previous: [max_length + 1]usize = undefined;
    var current: [max_length + 1]usize = undefined;
    for (0..right.len + 1) |column| previous[column] = column;
    for (left, 1..) |left_byte, row| {
        current[0] = row;
        for (right, 1..) |right_byte, column| {
            const substitution: usize = if (left_byte == right_byte) 0 else 1;
            var best = @min(previous[column] + 1, current[column - 1] + 1, previous[column - 1] + substitution);
            if (row > 1 and column > 1 and left_byte == right[column - 2] and left[row - 2] == right_byte) {
                best = @min(best, before_previous[column - 2] + 1);
            }
            current[column] = best;
        }
        before_previous = previous;
        previous = current;
    }
    return previous[right.len];
}

const testing = std.testing;

fn testHint(name: []const u8, known: []const []const u8) ![]u8 {
    return testing.allocator.print("{f}", .{hint(name, known, "fields are ...")});
}

test "swapped neighbours count as one edit" {
    try testing.expectEqual(1, distance("kyanso", "kyanos"));
    try testing.expectEqual(2, distance("kyanso", "kyanxx"));
    try testing.expectEqual(3, distance("frost", "frozen"));
    try testing.expectEqual(0, distance("", ""));
    try testing.expectEqual(5, distance("", "frost"));
}

test "a name allows one edit per two bytes, rounded up, and at least one" {
    try testing.expectEqual(1, allowedEdits(0));
    try testing.expectEqual(1, allowedEdits(2));
    try testing.expectEqual(2, allowedEdits(3));
    try testing.expectEqual(2, allowedEdits(4));
    try testing.expectEqual(3, allowedEdits(5));
}

test "a close name is suggested, and every name equally close" {
    const one = try testHint("kity", &.{ "foot", "kitty" });
    defer testing.allocator.free(one);
    try testing.expectEqualStrings("did you mean 'kitty'?", one);
    const two = try testHint("kity", &.{ "kitty", "foot", "kitt" });
    defer testing.allocator.free(two);
    try testing.expectEqualStrings("did you mean 'kitty' or 'kitt'?", two);
    const three = try testHint("hued", &.{ "hues", "huer", "hue" });
    defer testing.allocator.free(three);
    try testing.expectEqualStrings("did you mean 'hues', 'huer' or 'hue'?", three);
}

test "a name replacing all of the shorter one is never suggested" {
    try testing.expectEqual(std.math.maxInt(usize), closeness("alacritty", "kitty"));
    try testing.expectEqual(std.math.maxInt(usize), closeness("shade", "hue"));
    try testing.expectEqual(3, closeness("frost", "frozen"));
    const far = try testHint("shade", &.{ "color", "hue" });
    defer testing.allocator.free(far);
    try testing.expectEqualStrings("fields are ...", far);
}

test "a far-off name, a short one and no names at all fall back" {
    const far = try testHint("zzzzzz", &.{ "red", "blue" });
    defer testing.allocator.free(far);
    try testing.expectEqualStrings("fields are ...", far);
    const short = try testHint("ab", &.{ "xy", "frost" });
    defer testing.allocator.free(short);
    try testing.expectEqualStrings("fields are ...", short);
    const none = try testHint("kity", &.{});
    defer testing.allocator.free(none);
    try testing.expectEqualStrings("fields are ...", none);
}

test "distance works at compile time" {
    comptime {
        @setEvalBranchQuota(10_000);
        std.debug.assert(distance("rde", "red") == 1);
    }
}
