//! A path to values in a file: dot-separated keys, `"quoted.keys"` for keys holding a dot,
//! and `*` for any one key. Paths name keys only, never list elements.

const Path = @This();

const std = @import("std");
const Node = @import("Adapter/Node.zig");

/// The keys to step through, outermost first.
segments: []const Segment,

/// One step of a path.
pub const Segment = union(enum) {
    /// Exactly this key.
    key: []const u8,
    /// Any one key (`*`).
    any,
};

/// Why `parse` failed.
pub const Failure = @import("Path/Failure.zig");

/// Errors from `parse` and `fromAny`.
pub const ParseError = std.mem.Allocator.Error || error{InvalidKeyPath};

/// Reads path text: `general."col.active_border"`, `decoration.*.enabled`. Segments point into `text`.
pub fn parse(allocator: std.mem.Allocator, text: []const u8, failure: *Failure) ParseError!Path {
    if (text.len == 0) return fail(failure, 0, .empty_path);
    var segments: std.ArrayList(Segment) = .empty;
    var index: usize = 0;
    while (true) {
        if (index < text.len and text[index] == '"') {
            const close = std.mem.indexOfScalarPos(u8, text, index + 1, '"') orelse return fail(failure, index, .unterminated_quote);
            try segments.append(allocator, .{ .key = text[index + 1 .. close] });
            index = close + 1;
            if (index < text.len and text[index] != '.') return fail(failure, index, .text_after_quote);
        } else {
            const end = std.mem.indexOfScalarPos(u8, text, index, '.') orelse text.len;
            if (end == index) return fail(failure, index, .empty_segment);
            const segment = text[index..end];
            try segments.append(allocator, if (std.mem.eql(u8, segment, "*")) .any else .{ .key = segment });
            index = end;
        }
        if (index == text.len) break;
        index += 1;
        if (index == text.len) return fail(failure, index, .empty_segment);
    }
    return .{ .segments = segments.items };
}

fn fail(failure: *Failure, index: usize, problem: Failure.Problem) error{InvalidKeyPath} {
    failure.* = .{ .column = index + 1, .problem = problem };
    return error.InvalidKeyPath;
}

/// A path from what an app passes: path text, a tuple of keys taken literally
/// (`.{ "general", "col.active_border" }`), or a `Path`.
pub fn fromAny(allocator: std.mem.Allocator, path: anytype, failure: *Failure) ParseError!Path {
    const T = @TypeOf(path);
    if (T == Path) return path;
    if (comptime isText(T)) return parse(allocator, path, failure);
    const info = @typeInfo(T);
    if (info != .@"struct" or !info.@"struct".is_tuple)
        @compileError("a path is text (\"general.border_size\") or a tuple of keys (.{ \"general\", \"col.active_border\" }), not " ++ @typeName(T));
    if (path.len == 0) return fail(failure, 0, .empty_path);
    const segments = try allocator.alloc(Segment, path.len);
    inline for (0..path.len) |index| {
        if (comptime !isText(@TypeOf(path[index]))) @compileError("every key of a path tuple is text");
        segments[index] = .{ .key = path[index] };
    }
    return .{ .segments = segments };
}

/// Whether `T` is path text rather than a tuple of keys.
/// Sentinel-terminated slices count, so `@tagName` and comptime field names work as they are.
pub fn isText(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    if (info.pointer.size == .slice) return info.pointer.child == u8;
    if (info.pointer.size != .one) return false;
    const child = @typeInfo(info.pointer.child);
    return child == .array and child.array.child == u8;
}

/// Every node under `root` the path leads to, in tree order. Lists are never stepped into.
pub fn find(path: Path, allocator: std.mem.Allocator, root: *const Node) std.mem.Allocator.Error![]const *const Node {
    var found: std.ArrayList(*const Node) = .empty;
    try collect(allocator, root, path.segments, &found);
    return found.items;
}

fn collect(allocator: std.mem.Allocator, node: *const Node, segments: []const Segment, found: *std.ArrayList(*const Node)) std.mem.Allocator.Error!void {
    if (segments.len == 0) return found.append(allocator, node);
    if (node.kind != .table) return;
    for (node.children) |*child| {
        const matches = switch (segments[0]) {
            .any => true,
            .key => |key| std.mem.eql(u8, child.key orelse continue, key),
        };
        if (matches) try collect(allocator, child, segments[1..], found);
    }
}

/// Prints the path as text, quoting segments that hold a dot.
pub fn format(path: Path, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (path.segments, 0..) |segment, index| {
        if (index != 0) try writer.writeByte('.');
        switch (segment) {
            .any => try writer.writeByte('*'),
            .key => |key| if (std.mem.indexOfScalar(u8, key, '.') != null or key.len == 0 or std.mem.eql(u8, key, "*"))
                try writer.print("\"{s}\"", .{key})
            else
                try writer.writeAll(key),
        }
    }
}

const testing = std.testing;

fn expectSegments(text: []const u8, expected: []const Segment) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failure: Failure = .{};
    const path = try parse(arena.allocator(), text, &failure);
    try testing.expectEqual(expected.len, path.segments.len);
    for (expected, path.segments) |want, got| {
        try testing.expectEqual(std.meta.activeTag(want), std.meta.activeTag(got));
        if (want == .key) try testing.expectEqualStrings(want.key, got.key);
    }
}

fn expectFailure(text: []const u8, column: usize, problem: Failure.Problem) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failure: Failure = .{};
    try testing.expectError(error.InvalidKeyPath, parse(arena.allocator(), text, &failure));
    try testing.expectEqual(problem, failure.problem);
    try testing.expectEqual(column, failure.column);
}

test "parse splits on dots, keeps quoted dots and reads * as any key" {
    try expectSegments("decoration.blur.enabled", &.{ .{ .key = "decoration" }, .{ .key = "blur" }, .{ .key = "enabled" } });
    try expectSegments("general.\"col.active_border\"", &.{ .{ .key = "general" }, .{ .key = "col.active_border" } });
    try expectSegments("\"a.b\"", &.{.{ .key = "a.b" }});
    try expectSegments("decoration.*.enabled", &.{ .{ .key = "decoration" }, .any, .{ .key = "enabled" } });
    try expectSegments("\"*\".\"\"", &.{ .{ .key = "*" }, .{ .key = "" } });
}

test "parse names the column and problem of a bad path" {
    try expectFailure("", 1, .empty_path);
    try expectFailure("a..b", 3, .empty_segment);
    try expectFailure(".a", 1, .empty_segment);
    try expectFailure("a.", 3, .empty_segment);
    try expectFailure("a.\"b", 3, .unterminated_quote);
    try expectFailure("\"a\"b", 4, .text_after_quote);
}

test "a tuple path takes every key literally" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failure: Failure = .{};
    const path = try fromAny(arena.allocator(), .{ "general", "col.active_border", "*" }, &failure);
    try testing.expectEqualStrings("*", path.segments[2].key);
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try writer.print("{f}", .{path});
    try testing.expectEqualStrings("general.\"col.active_border\".\"*\"", writer.buffered());
}

test "sentinel-terminated text is path text, at runtime and inside a tuple" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failure: Failure = .{};
    var mode: enum { dark, light } = .dark;
    _ = &mode;
    const name: [:0]const u8 = @tagName(mode);
    const path = try fromAny(arena.allocator(), name, &failure);
    try testing.expectEqualStrings("dark", path.segments[0].key);
    const tuple = try fromAny(arena.allocator(), .{ "theme", name, "name" }, &failure);
    try testing.expectEqual(3, tuple.segments.len);
    try testing.expect(!isText([]const u16));
}

fn scalar(key: []const u8, position: usize) Node {
    return .{ .key = key, .kind = .scalar, .position = position, .value = .{ .start = position, .end = position + 1 } };
}

test "find follows every matching key, * any one, and never enters a list" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const blur = [_]Node{ scalar("enabled", 1), scalar("size", 2) };
    const shadow = [_]Node{scalar("enabled", 3)};
    const list = [_]Node{.{ .key = null, .kind = .table, .position = 5, .value = null, .children = &.{scalar("enabled", 6)} }};
    const decoration = [_]Node{
        .{ .key = "blur", .kind = .table, .position = 0, .value = null, .children = &blur },
        .{ .key = "shadow", .kind = .table, .position = 3, .value = null, .children = &shadow },
        .{ .key = "blur", .kind = .table, .position = 4, .value = null, .children = &.{scalar("enabled", 4)} },
        .{ .key = "items", .kind = .list, .position = 5, .value = null, .children = &list },
    };
    const root_children = [_]Node{.{ .key = "decoration", .kind = .table, .position = 0, .value = null, .children = &decoration }};
    const root: Node = .{ .key = null, .kind = .table, .position = 0, .value = null, .children = &root_children };
    var failure: Failure = .{};

    const twice = try (try parse(arena.allocator(), "decoration.blur.enabled", &failure)).find(arena.allocator(), &root);
    try testing.expectEqual(2, twice.len);
    try testing.expectEqual(4, twice[1].position);
    const any = try (try parse(arena.allocator(), "decoration.*.enabled", &failure)).find(arena.allocator(), &root);
    try testing.expectEqual(3, any.len);
    const none = try (try parse(arena.allocator(), "decoration.blur.enabled.deeper", &failure)).find(arena.allocator(), &root);
    try testing.expectEqual(0, none.len);
}
