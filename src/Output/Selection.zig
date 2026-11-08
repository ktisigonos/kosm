//! The files `output.edit` picked (D79), and the calls that set values in them by path (D31).
//! Paths are text (`general."col.active_border"`, D32) or a tuple of keys. Every call only
//! plans; nothing is written until kosm commits (D36). Kosm sets the fields.

const Selection = @This();

const std = @import("std");
const Adapter = @import("../Adapter.zig");
const Format = @import("../Format.zig");
const Output = @import("../Output.zig");
const Path = @import("../Path.zig");
const value_tree = @import("../value.zig");
const planning = @import("planning.zig");
const Match = @import("Match.zig");
const Cardinality = @import("Cardinality.zig").Cardinality;
const Locations = @import("Selection/Locations.zig");

output: *Output,
/// The `files` glob as the app wrote it, for messages.
selector: []const u8,
adapter: Adapter,
/// How values are spelled in these files, every layer applied (D70).
format: Format.Resolved,
/// The picked files, sorted by path.
files: []const File,

/// One picked file.
pub const File = @import("Selection/File.zig");

/// Options for `setOptions`.
pub const SetOptions = struct {
    /// Which matches to set; by default exactly one must exist.
    match: Cardinality = .one,
};

const Error = Output.Error;

/// Sets the one value at `path`; zero or several matches is an error (D31).
pub fn set(selection: *Selection, path: anytype, value: anytype) Error!void {
    return selection.setOptions(path, value, .{});
}

/// Sets the first value at `path`.
pub fn setFirst(selection: *Selection, path: anytype, value: anytype) Error!void {
    return selection.setOptions(path, value, .{ .match = .first });
}

/// Sets every value at `path`.
pub fn setAll(selection: *Selection, path: anytype, value: anytype) Error!void {
    return selection.setOptions(path, value, .{ .match = .all });
}

/// Sets the value at `path` with 0-based match index `index`.
pub fn setNth(selection: *Selection, path: anytype, index: usize, value: anytype) Error!void {
    return selection.setOptions(path, value, .{ .match = .{ .nth = index } });
}

/// Sets the values at `path` with these match indices, each of which must exist.
pub fn setIndices(selection: *Selection, path: anytype, indices: []const usize, value: anytype) Error!void {
    return selection.setOptions(path, value, .{ .match = .{ .indices = indices } });
}

/// Sets the values at `path` with match indices `start` up to but not including `end`.
pub fn setRange(selection: *Selection, path: anytype, start: usize, end: usize, value: anytype) Error!void {
    return selection.setOptions(path, value, .{ .match = .{ .range = .{ .start = start, .end = end } } });
}

/// Sets the matches of `path` that `options.match` picks to `value`, formatted by the adapter
/// (D42) in the files' format. Only the value's bytes change (D35); a key is never inserted (D28).
pub fn setOptions(selection: *Selection, path: anytype, value: anytype, options: SetOptions) Error!void {
    const parsed = try selection.parsePath(path);
    const matches = try selection.find(parsed);
    if (matches.len == 0)
        return selection.fail(error.NoMatch, "path '{f}' matches nothing; kosm never inserts keys (D28)", .{parsed});
    const chosen = try selection.choose(parsed, matches, options.match);
    const text = try selection.formatValue(try selection.output.allocator.print("path '{f}'", .{parsed}), value);
    for (chosen) |match| try selection.write(match, text);
}

/// Every value at `path`, in match order; empty when there is none (D34). For reading, for
/// `elements`, and for `replace`. The empty path `""` is each file's top-level value (D80).
pub fn nodes(selection: *Selection, path: anytype) Error![]const Match {
    if (comptime Path.isText(@TypeOf(path))) {
        if (path.len == 0) return selection.roots();
    }
    return selection.find(try selection.parsePath(path));
}

fn roots(selection: *Selection) Error![]const Match {
    const result = try selection.output.allocator.alloc(Match, selection.files.len);
    for (selection.files, result, 0..) |*file, *match, file_index| match.* = toMatch(file.*, file_index, &file.root);
    return result;
}

/// The elements of list `match`, in file order (D80): a list's values, or a table's entries
/// without a key (`{ "a", key = 1 }`, D90). Paths never step into lists (D77).
pub fn elements(selection: *Selection, match: Match) Error![]const Match {
    const file = selection.files[match.file_index];
    var result: std.ArrayList(Match) = .empty;
    if (match.kind != .scalar) {
        for (match.node.children) |*node| {
            if (node.key == null) try result.append(selection.output.allocator, toMatch(file, match.file_index, node));
        }
    }
    if (match.kind != .list and result.items.len == 0)
        return planning.fail(selection.output, error.NotAList, match.file, "the value on line {d} is a {s}, not a list", .{ match.line, @tagName(match.kind) });
    return result.items;
}

/// Sets `match`, from `nodes` or `elements`, to `value`, formatted like `set` does (D80).
pub fn replace(selection: *Selection, match: Match, value: anytype) Error!void {
    const about = try selection.output.allocator.print("the value on line {d} of {s}", .{ match.line, match.file });
    try selection.write(match, try selection.formatValue(about, value));
}

fn parsePath(selection: *Selection, path: anytype) Error!Path {
    var failure: Path.Failure = .{};
    return Path.fromAny(selection.output.allocator, path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidKeyPath => {
            const text: []const u8 = if (comptime Path.isText(@TypeOf(path))) path else "";
            return selection.fail(error.InvalidKeyPath, "path '{s}', column {d}: {s}", .{ text, failure.column, failure.problem.describe() });
        },
    };
}

fn find(selection: *Selection, path: Path) Error![]const Match {
    const allocator = selection.output.allocator;
    var matches: std.ArrayList(Match) = .empty;
    for (selection.files, 0..) |*file, file_index| {
        const found = try path.find(allocator, &file.root);
        const ordered = try allocator.dupe(*const Adapter.Node, found);
        std.mem.sort(*const Adapter.Node, ordered, {}, positionLessThan);
        for (ordered) |node| try matches.append(allocator, toMatch(file.*, file_index, node));
    }
    return matches.items;
}

fn positionLessThan(_: void, left: *const Adapter.Node, right: *const Adapter.Node) bool {
    return left.position < right.position;
}

fn toMatch(file: File, file_index: usize, node: *const Adapter.Node) Match {
    return .{
        .file = file.display_path,
        .line = planning.lineOf(file.source, node.position),
        .kind = node.kind,
        .value = node.value,
        .text = if (node.value) |range| file.source[range.start..range.end] else "",
        .file_index = file_index,
        .node = node,
    };
}

fn choose(selection: *Selection, path: Path, matches: []const Match, cardinality: Cardinality) Error![]const Match {
    const count = matches.len;
    switch (cardinality) {
        .one => {
            if (count == 1) return matches;
            return selection.fail(error.TooManyMatches, "path '{f}' matches {d} values ({f}); narrow .files, or pick with setFirst, setAll or setNth (D31)", .{ path, count, Locations{ .matches = matches } });
        },
        .first => return matches[0..1],
        .all => return matches,
        .nth => |index| {
            try selection.checkIndex(path, count, index);
            return matches[index .. index + 1];
        },
        .indices => |indices| {
            if (indices.len == 0) return selection.fail(error.InvalidIndices, "path '{f}': setIndices needs at least one index", .{path});
            const chosen = try selection.output.allocator.alloc(Match, indices.len);
            for (indices, chosen, 0..) |index, *slot, position| {
                try selection.checkIndex(path, count, index);
                if (std.mem.indexOfScalar(usize, indices[0..position], index) != null)
                    return selection.fail(error.InvalidIndices, "path '{f}': index {d} is listed twice", .{ path, index });
                slot.* = matches[index];
            }
            return chosen;
        },
        .range => |range| {
            if (range.start >= range.end)
                return selection.fail(error.InvalidIndices, "path '{f}': the range [{d}, {d}) holds no index", .{ path, range.start, range.end });
            try selection.checkIndex(path, count, range.end - 1);
            return matches[range.start..range.end];
        },
    }
}

fn checkIndex(selection: *Selection, path: Path, count: usize, index: usize) Error!void {
    if (index < count) return;
    return selection.fail(error.IndexOutOfRange, "path '{f}' matches {d} values, so index {d} does not exist (indices start at 0)", .{ path, count, index });
}

/// `value` as source text, through the adapter's `format` (D42). `about` names what is set.
fn formatValue(selection: *Selection, about: []const u8, value: anytype) Error![]const u8 {
    const allocator = selection.output.allocator;
    var context: Adapter.Context = .{ .format = selection.format };
    const tree = value_tree.from(allocator, &context.clipped, value) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.IntegerTooLarge => return selection.fail(error.UnsupportedValue, "{s}: the integer is too large for a file value", .{about}),
        error.NullInList => return selection.fail(error.UnsupportedValue, "{s}: the value is null, or a list holding null; kosm never removes keys", .{about}),
    };
    var content: std.Io.Writer.Allocating = .init(allocator);
    errdefer content.deinit();
    selection.adapter.format.?(&content.writer, tree, &context) catch |err| switch (err) {
        // An allocating writer fails only when it runs out of memory.
        error.WriteFailed => return error.OutOfMemory,
        error.UnsupportedValue => return selection.fail(error.UnsupportedValue, "{s}: adapter '{s}': {s}", .{ about, selection.adapter.name, context.message() }),
    };
    try planning.warnClipped(selection.output, selection.selector, about, &context.clipped);
    return content.toOwnedSlice();
}

fn write(selection: *Selection, match: Match, text: []const u8) Error!void {
    const range = match.value orelse
        return planning.fail(selection.output, error.NoValue, match.file, "line {d}: this table has no value of its own to replace, since headers or dotted keys spell it; set its keys instead", .{match.line});
    const file = selection.files[match.file_index];
    const planned = selection.output.plan.load(file.path, file.display_path) catch |err| return planning.failRead(selection.output, file.display_path, err);
    try planning.addEdit(selection.output, planned, .{ .target = .value, .start = range.start, .end = range.end, .content = text, .owner = selection.output.app });
}

fn fail(selection: *Selection, err: Error, comptime format: []const u8, arguments: anytype) Error {
    return planning.fail(selection.output, err, selection.selector, format, arguments);
}
