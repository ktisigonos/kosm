//! Kosm-owned blocks inside hand-written files: finding them between their
//! `kosm:begin <id>` and `kosm:end` comment lines, and writing new ones (D72).

const std = @import("std");
const Comment = @import("Adapter.zig").Comment;

/// The byte range of a block's contents.
pub const Contents = @import("block/Contents.zig");
/// Why markers were rejected, and on which line.
pub const Failure = @import("block/Failure.zig");

/// Errors from reading markers; `Failure` says which and where.
pub const Error = std.mem.Allocator.Error || error{InvalidBlock};

const marker_prefix = "kosm:";
const begin_word = "begin";
const end_word = "end";

/// Whether `id` is a valid block id: letters, digits, `_`, `-` and `.`, at least one.
pub fn isValidId(id: []const u8) bool {
    if (id.len == 0) return false;
    for (id) |character| {
        const allowed = std.ascii.isAlphanumeric(character) or character == '_' or character == '-' or character == '.';
        if (!allowed) return false;
    }
    return true;
}

/// The contents of block `id` in `text`, or null when it has none. Checks every marker in the
/// file, not only `id`'s. `allocator` holds scratch memory, freed before returning.
pub fn find(allocator: std.mem.Allocator, text: []const u8, comment: Comment, id: []const u8, failure: *Failure) Error!?Contents {
    var seen_ids: std.ArrayList([]const u8) = .empty;
    defer seen_ids.deinit(allocator);
    var open: ?OpenBlock = null;
    var found: ?Contents = null;
    var lines: Lines = .{ .text = text };
    while (lines.next()) |line| {
        switch (classify(line.bytes, comment)) {
            .none => {},
            .unknown => return reject(failure, line.number, .unknown_marker),
            .begin => |begin_id| {
                if (open != null) return reject(failure, line.number, .nested_begin);
                for (seen_ids.items) |seen| {
                    if (std.mem.eql(u8, seen, begin_id)) return reject(failure, line.number, .duplicate_id);
                }
                try seen_ids.append(allocator, begin_id);
                open = .{ .id = begin_id, .line = line.number, .contents_start = line.next_start };
            },
            .end => {
                const block = open orelse return reject(failure, line.number, .unopened_end);
                if (std.mem.eql(u8, block.id, id)) found = .{ .start = block.contents_start, .end = line.start };
                open = null;
            },
        }
    }
    if (open) |block| return reject(failure, block.line, .unclosed_begin);
    return found;
}

/// Rejects `content` when one of its lines is a marker, which would break the file for the next
/// apply.
pub fn checkContent(content: []const u8, comment: Comment, failure: *Failure) error{InvalidBlock}!void {
    var lines: Lines = .{ .text = content };
    while (lines.next()) |line| {
        if (classify(line.bytes, comment) != .none) return reject(failure, line.number, .marker_in_content);
    }
}

/// Writes block `id` holding `content`, markers included. A newline is added after `content`
/// when it lacks one.
pub fn write(writer: *std.Io.Writer, comment: Comment, id: []const u8, content: []const u8) std.Io.Writer.Error!void {
    try writeMarker(writer, comment, begin_word ++ " ", id);
    try writer.writeAll(content);
    if (content.len != 0 and content[content.len - 1] != '\n') try writer.writeByte('\n');
    try writeMarker(writer, comment, end_word, "");
}

fn writeMarker(writer: *std.Io.Writer, comment: Comment, word: []const u8, id: []const u8) std.Io.Writer.Error!void {
    switch (comment) {
        .line => |start| try writer.print("{s} " ++ marker_prefix ++ "{s}{s}\n", .{ start, word, id }),
        .block => |delimiters| try writer.print("{s} " ++ marker_prefix ++ "{s}{s} {s}\n", .{ delimiters.open, word, id, delimiters.close }),
    }
}

fn reject(failure: *Failure, line: usize, problem: Failure.Problem) error{InvalidBlock} {
    failure.* = .{ .line = line, .problem = problem };
    return error.InvalidBlock;
}

const OpenBlock = struct {
    id: []const u8,
    line: usize,
    contents_start: usize,
};

const Marker = union(enum) {
    none,
    begin: []const u8,
    end,
    /// A comment starting with `kosm:` that is not exactly a marker.
    unknown,
};

const whitespace = " \t\r";

fn classify(line: []const u8, comment: Comment) Marker {
    const trimmed = std.mem.trim(u8, line, whitespace);
    const inner = switch (comment) {
        .line => |start| if (std.mem.startsWith(u8, trimmed, start)) trimmed[start.len..] else return .none,
        .block => |delimiters| blk: {
            const wrapped = trimmed.len >= delimiters.open.len + delimiters.close.len and
                std.mem.startsWith(u8, trimmed, delimiters.open) and std.mem.endsWith(u8, trimmed, delimiters.close);
            if (!wrapped) return .none;
            break :blk trimmed[delimiters.open.len .. trimmed.len - delimiters.close.len];
        },
    };
    const text = std.mem.trim(u8, inner, whitespace);
    if (!std.mem.startsWith(u8, text, marker_prefix)) return .none;
    const marker = text[marker_prefix.len..];
    if (std.mem.eql(u8, marker, end_word)) return .end;
    if (!std.mem.startsWith(u8, marker, begin_word)) return .unknown;
    const after = marker[begin_word.len..];
    if (after.len == 0 or (after[0] != ' ' and after[0] != '\t')) return .unknown;
    const id = std.mem.trim(u8, after, whitespace);
    if (!isValidId(id)) return .unknown;
    return .{ .begin = id };
}

/// Splits text into lines, keeping each one's offsets.
const Lines = struct {
    text: []const u8,
    start: usize = 0,
    number: usize = 0,

    const Line = struct {
        bytes: []const u8,
        number: usize,
        start: usize,
        /// First byte of the following line, or the text's length.
        next_start: usize,
    };

    fn next(lines: *Lines) ?Line {
        if (lines.start >= lines.text.len) return null;
        const start = lines.start;
        const newline = std.mem.indexOfScalarPos(u8, lines.text, start, '\n');
        const end = newline orelse lines.text.len;
        lines.start = if (newline) |index| index + 1 else lines.text.len;
        lines.number += 1;
        return .{ .bytes = lines.text[start..end], .number = lines.number, .start = start, .next_start = lines.start };
    }
};

const testing = std.testing;
const hash: Comment = .{ .line = "#" };
const css: Comment = .{ .block = .{ .open = "/*", .close = "*/" } };

fn expectContents(text: []const u8, comment: Comment, id: []const u8, expected: ?[]const u8) !void {
    var failure: Failure = .{};
    const contents = try find(testing.allocator, text, comment, id, &failure);
    if (expected) |bytes| {
        try testing.expectEqualStrings(bytes, text[contents.?.start..contents.?.end]);
    } else {
        try testing.expectEqual(null, contents);
    }
}

fn expectProblem(text: []const u8, comment: Comment, line: usize, problem: Failure.Problem) !void {
    var failure: Failure = .{};
    try testing.expectError(error.InvalidBlock, find(testing.allocator, text, comment, "colors", &failure));
    try testing.expectEqual(line, failure.line);
    try testing.expectEqual(problem, failure.problem);
}

test "find returns the bytes between the markers, whatever their indentation" {
    const text = "font 12\n  #   kosm:begin colors  \nforeground #fff\n# kosm:end\n# kosm:begin tabs\ntab red\n\t# kosm:end";
    try expectContents(text, hash, "colors", "foreground #fff\n");
    try expectContents(text, hash, "tabs", "tab red\n");
    try expectContents(text, hash, "missing", null);
    try expectContents("# kosm:begin colors\n# kosm:end\n", hash, "colors", "");
    try expectContents("a {}\n/* kosm:begin colors */\n:root {}\n/*kosm:end*/\n", css, "colors", ":root {}\n");
}

test "comments that do not start with kosm: are plain text" {
    try expectContents("# begin colors\n#kosmos\n-- kosm:end\n/* kosm:begin x\n", hash, "colors", null);
    try expectContents("# kosm:begin colors\n", css, "colors", null);
}

test "find rejects malformed and duplicate markers with their line" {
    try expectProblem("a\n# kosm:begin colors\nb\n", hash, 2, .unclosed_begin);
    try expectProblem("a\n# kosm:end\n", hash, 2, .unopened_end);
    try expectProblem("# kosm:begin colors\n# kosm:begin tabs\n# kosm:end\n", hash, 2, .nested_begin);
    try expectProblem("# kosm:begin a\n# kosm:end\n# kosm:begin a\n# kosm:end\n", hash, 3, .duplicate_id);
    try expectProblem("# kosm:begin colors\n# kosm:end\n# kosm:begin colors\n# kosm:end\n", hash, 3, .duplicate_id);
    try expectProblem("# kosm:start colors\n", hash, 1, .unknown_marker);
    try expectProblem("# kosm:begin\n", hash, 1, .unknown_marker);
    try expectProblem("# kosm:begin two words\n", hash, 1, .unknown_marker);
    try expectProblem("# kosm:beginning\n", hash, 1, .unknown_marker);
    try expectProblem("/* kosm:end colors */\n", css, 1, .unknown_marker);
}

test "write produces markers that find reads back" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try write(&output.writer, css, "colors", ":root {}");
    try testing.expectEqualStrings("/* kosm:begin colors */\n:root {}\n/* kosm:end */\n", output.written());
    try expectContents(output.written(), css, "colors", ":root {}\n");
}

test "checkContent rejects a marker line inside the content" {
    var failure: Failure = .{};
    try checkContent("a 1\n# a comment\n", hash, &failure);
    try testing.expectError(error.InvalidBlock, checkContent("# kosm:begin x\n", hash, &failure));
    try testing.expectError(error.InvalidBlock, checkContent("a 1\n# kosm:end\n", hash, &failure));
    try testing.expectEqual(2, failure.line);
    try testing.expectEqual(.marker_in_content, failure.problem);
}

test "ids are letters, digits, _, - and ." {
    try testing.expect(isValidId("kitty.colors-2_a"));
    try testing.expect(!isValidId(""));
    try testing.expect(!isValidId("two words"));
    try testing.expect(!isValidId("a/b"));
}
