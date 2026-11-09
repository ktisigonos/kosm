//! Unified diffs of a plan, for `kosm apply --diff`.

const std = @import("std");
const Plan = @import("Plan.zig");

/// Unchanged lines shown around each change.
const context_lines = 3;
/// Past this many differing lines the diff stops searching for a shortest edit and shows the
/// changed middle as removed and re-added, which keeps memory bounded (Myers needs D^2).
const max_edit_distance = 2000;

/// Prints every file the plan would change, in plan order. Unchanged files print nothing.
/// `terminal.mode` decides whether lines are colored like git's.
pub fn writePlan(allocator: std.mem.Allocator, terminal: std.Io.Terminal, plan: *const Plan) !void {
    for (plan.files.items) |file| {
        if (!file.changed()) continue;
        try writeFile(allocator, terminal, file.display_path, file.old, file.new);
    }
}

/// Prints a unified diff of one file; `old` is null for a file that does not exist yet.
pub fn writeFile(allocator: std.mem.Allocator, terminal: std.Io.Terminal, path: []const u8, old: ?[]const u8, new: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const old_lines = try splitLines(arena.allocator(), old orelse "");
    const new_lines = try splitLines(arena.allocator(), new);
    const edits = try editScript(arena.allocator(), old_lines, new_lines);

    try terminal.setColor(.bold);
    if (old == null) try terminal.writer.writeAll("--- /dev/null") else try terminal.writer.print("--- {s}", .{path});
    try endLine(terminal);
    try terminal.setColor(.bold);
    try terminal.writer.print("+++ {s}", .{path});
    try endLine(terminal);
    try writeHunks(terminal, edits, old_lines, new_lines);
}

const Operation = enum { equal, delete, insert };

/// One step of the edit script, with the position in each file before the step.
const Edit = struct {
    operation: Operation,
    old_index: usize,
    new_index: usize,
};

/// Lines including their `\n`, so a missing final newline counts as a difference.
fn splitLines(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    while (start < text.len) {
        const end = if (std.mem.indexOfScalarPos(u8, text, start, '\n')) |newline| newline + 1 else text.len;
        try lines.append(allocator, text[start..end]);
        start = end;
    }
    return lines.items;
}

fn editScript(allocator: std.mem.Allocator, old: []const []const u8, new: []const []const u8) ![]const Edit {
    var prefix: usize = 0;
    while (prefix < old.len and prefix < new.len and std.mem.eql(u8, old[prefix], new[prefix])) prefix += 1;
    var suffix: usize = 0;
    while (suffix < old.len - prefix and suffix < new.len - prefix and
        std.mem.eql(u8, old[old.len - 1 - suffix], new[new.len - 1 - suffix])) suffix += 1;

    var edits: std.ArrayList(Edit) = .empty;
    for (0..prefix) |index| try edits.append(allocator, .{ .operation = .equal, .old_index = index, .new_index = index });
    const old_middle = old[prefix .. old.len - suffix];
    const new_middle = new[prefix .. new.len - suffix];
    const middle = try shortestMiddle(allocator, old_middle, new_middle) orelse try replaceAll(allocator, old_middle.len, new_middle.len);
    for (middle) |edit| try edits.append(allocator, .{
        .operation = edit.operation,
        .old_index = edit.old_index + prefix,
        .new_index = edit.new_index + prefix,
    });
    for (0..suffix) |index| try edits.append(allocator, .{
        .operation = .equal,
        .old_index = old.len - suffix + index,
        .new_index = new.len - suffix + index,
    });
    return edits.items;
}

fn replaceAll(allocator: std.mem.Allocator, old_count: usize, new_count: usize) ![]const Edit {
    const edits = try allocator.alloc(Edit, old_count + new_count);
    for (0..old_count) |index| edits[index] = .{ .operation = .delete, .old_index = index, .new_index = 0 };
    for (0..new_count) |index| edits[old_count + index] = .{ .operation = .insert, .old_index = old_count, .new_index = index };
    return edits;
}

/// Myers' shortest edit script, or null when it needs more than `max_edit_distance` edits.
fn shortestMiddle(allocator: std.mem.Allocator, old: []const []const u8, new: []const []const u8) !?[]const Edit {
    const old_count: isize = @intCast(old.len);
    const new_count: isize = @intCast(new.len);
    const max: isize = @min(old_count + new_count, max_edit_distance);
    const offset: isize = max + 1;
    // furthest[k + offset] is the furthest x reached on diagonal k = x - y.
    const furthest = try allocator.alloc(isize, @intCast(2 * max + 3));
    @memset(furthest, 0);
    // trace[d] keeps diagonals -d-1..d+1 as they were before step d, for backtracking.
    var trace: std.ArrayList([]const isize) = .empty;

    var distance: isize = 0;
    const final_distance: isize = search: while (distance <= max) : (distance += 1) {
        const low: usize = @intCast(offset - distance - 1);
        const high: usize = @intCast(offset + distance + 2);
        try trace.append(allocator, try allocator.dupe(isize, furthest[low..high]));
        var diagonal = -distance;
        while (diagonal <= distance) : (diagonal += 2) {
            const index: usize = @intCast(diagonal + offset);
            var x = if (diagonal == -distance or (diagonal != distance and furthest[index - 1] < furthest[index + 1]))
                furthest[index + 1]
            else
                furthest[index - 1] + 1;
            var y = x - diagonal;
            while (x < old_count and y < new_count and std.mem.eql(u8, old[@intCast(x)], new[@intCast(y)])) {
                x += 1;
                y += 1;
            }
            furthest[index] = x;
            if (x >= old_count and y >= new_count) break :search distance;
        }
    } else return null;

    return try backtrack(allocator, trace.items, final_distance, old_count, new_count);
}

fn backtrack(allocator: std.mem.Allocator, trace: []const []const isize, final_distance: isize, old_count: isize, new_count: isize) ![]const Edit {
    var reversed: std.ArrayList(Edit) = .empty;
    var x = old_count;
    var y = new_count;
    var distance = final_distance;
    while (distance > 0) : (distance -= 1) {
        const before = trace[@intCast(distance)];
        const diagonal = x - y;
        const went_down = diagonal == -distance or
            (diagonal != distance and traced(before, distance, diagonal - 1) < traced(before, distance, diagonal + 1));
        const previous_diagonal = if (went_down) diagonal + 1 else diagonal - 1;
        const previous_x = traced(before, distance, previous_diagonal);
        const previous_y = previous_x - previous_diagonal;
        while (x > previous_x and y > previous_y) {
            x -= 1;
            y -= 1;
            try reversed.append(allocator, .{ .operation = .equal, .old_index = @intCast(x), .new_index = @intCast(y) });
        }
        if (x == previous_x) {
            try reversed.append(allocator, .{ .operation = .insert, .old_index = @intCast(x), .new_index = @intCast(previous_y) });
        } else {
            try reversed.append(allocator, .{ .operation = .delete, .old_index = @intCast(previous_x), .new_index = @intCast(y) });
        }
        x = previous_x;
        y = previous_y;
    }
    while (x > 0 and y > 0) {
        x -= 1;
        y -= 1;
        try reversed.append(allocator, .{ .operation = .equal, .old_index = @intCast(x), .new_index = @intCast(y) });
    }
    std.mem.reverse(Edit, reversed.items);
    return reversed.items;
}

fn traced(before: []const isize, distance: isize, diagonal: isize) isize {
    return before[@intCast(diagonal + distance + 1)];
}

fn writeHunks(terminal: std.Io.Terminal, edits: []const Edit, old_lines: []const []const u8, new_lines: []const []const u8) !void {
    var next: usize = 0;
    while (nextChange(edits, next)) |first_change| {
        var last_change = first_change;
        var index = first_change;
        while (index < edits.len and index - last_change <= 2 * context_lines + 1) : (index += 1) {
            if (edits[index].operation != .equal) last_change = index;
        }
        const start = @max(next, first_change -| context_lines);
        const end = @min(edits.len, last_change + 1 + context_lines);
        try writeHunk(terminal, edits[start..end], old_lines, new_lines);
        next = end;
    }
}

fn nextChange(edits: []const Edit, from: usize) ?usize {
    for (edits[from..], from..) |edit, index| {
        if (edit.operation != .equal) return index;
    }
    return null;
}

fn writeHunk(terminal: std.Io.Terminal, hunk: []const Edit, old_lines: []const []const u8, new_lines: []const []const u8) !void {
    var old_count: usize = 0;
    var new_count: usize = 0;
    for (hunk) |edit| switch (edit.operation) {
        .equal => {
            old_count += 1;
            new_count += 1;
        },
        .delete => old_count += 1,
        .insert => new_count += 1,
    };
    const old_start = if (old_count == 0) hunk[0].old_index else hunk[0].old_index + 1;
    const new_start = if (new_count == 0) hunk[0].new_index else hunk[0].new_index + 1;
    try terminal.setColor(.cyan);
    try terminal.writer.print("@@ -{d},{d} +{d},{d} @@", .{ old_start, old_count, new_start, new_count });
    try endLine(terminal);
    for (hunk) |edit| switch (edit.operation) {
        .equal => try writeLine(terminal, ' ', old_lines[edit.old_index]),
        .delete => try writeLine(terminal, '-', old_lines[edit.old_index]),
        .insert => try writeLine(terminal, '+', new_lines[edit.new_index]),
    };
}

fn writeLine(terminal: std.Io.Terminal, marker: u8, line: []const u8) !void {
    const text = std.mem.trimEnd(u8, line, "\n");
    const color: ?std.Io.Terminal.Color = switch (marker) {
        '-' => .red,
        '+' => .green,
        else => null,
    };
    if (color) |set| try terminal.setColor(set);
    try terminal.writer.writeByte(marker);
    try terminal.writer.writeAll(text);
    if (color != null) try endLine(terminal) else try terminal.writer.writeByte('\n');
    if (text.len == line.len) try terminal.writer.writeAll("\\ No newline at end of file\n");
}

/// Resets the color before the newline, as git does, so a pager never carries it onto the next line.
fn endLine(terminal: std.Io.Terminal) !void {
    try terminal.setColor(.reset);
    try terminal.writer.writeByte('\n');
}

const testing = std.testing;

fn expectDiff(expected: []const u8, old: ?[]const u8, new: []const u8) !void {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try writeFile(testing.allocator, .{ .writer = &output.writer, .mode = .no_color }, "~/a.conf", old, new);
    try testing.expectEqualStrings(expected, output.written());
}

test "on a terminal, headers are bold, hunk lines cyan, removals red and additions green, each reset before its newline" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try writeFile(testing.allocator, .{ .writer = &output.writer, .mode = .escape_codes }, "~/a.conf", "a\nb", "a\nc\n");
    try testing.expectEqualStrings(
        "\x1b[1m--- ~/a.conf\x1b[0m\n\x1b[1m+++ ~/a.conf\x1b[0m\n" ++
            "\x1b[36m@@ -1,2 +1,2 @@\x1b[0m\n" ++
            " a\n" ++
            "\x1b[31m-b\x1b[0m\n\\ No newline at end of file\n" ++
            "\x1b[32m+c\x1b[0m\n",
        output.written(),
    );
}

test "a new file is all additions" {
    try expectDiff("--- /dev/null\n+++ ~/a.conf\n@@ -0,0 +1,2 @@\n+one\n+two\n", null, "one\ntwo\n");
}

test "a change shows three lines of context" {
    try expectDiff(
        \\--- ~/a.conf
        \\+++ ~/a.conf
        \\@@ -2,7 +2,7 @@
        \\ 2
        \\ 3
        \\ 4
        \\-5
        \\+five
        \\ 6
        \\ 7
        \\ 8
        \\
    , "1\n2\n3\n4\n5\n6\n7\n8\n9\n", "1\n2\n3\n4\nfive\n6\n7\n8\n9\n");
}

test "changes far apart get separate hunks, close ones share one" {
    const old = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n";
    try expectDiff(
        \\--- ~/a.conf
        \\+++ ~/a.conf
        \\@@ -1,4 +1,4 @@
        \\-1
        \\+one
        \\ 2
        \\ 3
        \\ 4
        \\@@ -9,4 +9,4 @@
        \\ 9
        \\ 10
        \\ 11
        \\-12
        \\+twelve
        \\
    , old, "one\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\ntwelve\n");
    try expectDiff(
        \\--- ~/a.conf
        \\+++ ~/a.conf
        \\@@ -1,11 +1,11 @@
        \\-1
        \\+one
        \\ 2
        \\ 3
        \\ 4
        \\ 5
        \\ 6
        \\ 7
        \\-8
        \\+eight
        \\ 9
        \\ 10
        \\ 11
        \\
    , old, "one\n2\n3\n4\n5\n6\n7\neight\n9\n10\n11\n12\n");
}

test "a missing final newline is shown" {
    try expectDiff(
        \\--- ~/a.conf
        \\+++ ~/a.conf
        \\@@ -1,2 +1,2 @@
        \\ a
        \\-b
        \\\ No newline at end of file
        \\+b
        \\
    , "a\nb", "a\nb\n");
}

test "insertions and deletions point at the right lines" {
    try expectDiff(
        \\--- ~/a.conf
        \\+++ ~/a.conf
        \\@@ -1,4 +1,4 @@
        \\ a
        \\+new
        \\ b
        \\ c
        \\-d
        \\
    , "a\nb\nc\nd\n", "a\nnew\nb\nc\n");
}

test "random edit scripts rebuild both files with the fewest edits" {
    var prng: std.Random.DefaultPrng = .init(0x6b6f736d);
    const random = prng.random();
    const alphabet = [_][]const u8{ "a\n", "b\n", "c\n", "d\n" };
    for (0..300) |_| {
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const old = try allocator.alloc([]const u8, random.uintLessThan(usize, 12));
        const new = try allocator.alloc([]const u8, random.uintLessThan(usize, 12));
        for (old) |*line| line.* = alphabet[random.uintLessThan(usize, alphabet.len)];
        for (new) |*line| line.* = alphabet[random.uintLessThan(usize, alphabet.len)];

        const edits = try editScript(allocator, old, new);
        var old_seen: usize = 0;
        var new_seen: usize = 0;
        var changes: usize = 0;
        for (edits) |edit| switch (edit.operation) {
            .equal => {
                try testing.expectEqualStrings(old[edit.old_index], new[edit.new_index]);
                try testing.expectEqual(old_seen, edit.old_index);
                try testing.expectEqual(new_seen, edit.new_index);
                old_seen += 1;
                new_seen += 1;
            },
            .delete => {
                try testing.expectEqual(old_seen, edit.old_index);
                old_seen += 1;
                changes += 1;
            },
            .insert => {
                try testing.expectEqual(new_seen, edit.new_index);
                new_seen += 1;
                changes += 1;
            },
        };
        try testing.expectEqual(old.len, old_seen);
        try testing.expectEqual(new.len, new_seen);
        try testing.expectEqual(old.len + new.len - 2 * try longestCommonSubsequence(allocator, old, new), changes);
    }
}

fn longestCommonSubsequence(allocator: std.mem.Allocator, old: []const []const u8, new: []const []const u8) !usize {
    const width = new.len + 1;
    const table = try allocator.alloc(usize, (old.len + 1) * width);
    @memset(table, 0);
    for (old, 1..) |old_line, row| {
        for (new, 1..) |new_line, column| {
            table[row * width + column] = if (std.mem.eql(u8, old_line, new_line))
                table[(row - 1) * width + column - 1] + 1
            else
                @max(table[(row - 1) * width + column], table[row * width + column - 1]);
        }
    }
    return table[old.len * width + new.len];
}
