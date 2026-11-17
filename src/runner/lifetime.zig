//! Finds lists in a kosmos tree that point into the stack of functions that have returned,
//! like `&.{ theme.palette.blue }` written with a run-time theme. Their items are garbage by
//! the time kosm reads them, so kosm refuses the tree instead of writing what they hold.

const std = @import("std");
const discovery = @import("discovery.zig");

/// The part of the stack the kosmos ran in, dead once it returned: from `low` up to, not
/// including, `high`.
pub const Stack = struct {
    low: usize,
    high: usize,

    /// The stack below `high`, as deep as the process' stack may grow.
    pub fn below(high: usize) Stack {
        return .{ .low = high -| stackLimit(), .high = high };
    }

    fn holds(stack: Stack, address: usize) bool {
        return address >= stack.low and address < stack.high;
    }
};

/// How deep the stack may grow when its limit is unlimited or cannot be read: Linux' default.
const default_stack_limit = 8 * 1024 * 1024;

fn stackLimit() usize {
    const limit = std.posix.getrlimit(.STACK) catch return default_stack_limit;
    if (limit.cur == std.posix.RLIM.INFINITY) return default_stack_limit;
    return @intCast(limit.cur);
}

pub const Error = std.mem.Allocator.Error;

/// The path in `tree` of the first list pointing into `stack` (`base.icons.colors.only`,
/// `base.hyprpaper.wallpapers[0].path`), or null when there is none.
pub fn findDeadList(arena: std.mem.Allocator, tree: anytype, stack: Stack) Error!?[]const u8 {
    var walker: Walker = .{ .arena = arena, .stack = stack };
    if (try walker.visit(@TypeOf(tree), &tree)) return try walker.path();
    return null;
}

const Walker = struct {
    arena: std.mem.Allocator,
    stack: Stack,
    /// The fields and indices leading to the value being visited.
    segments: std.ArrayList([]const u8) = .empty,

    /// Whether `value` or anything inside it is a list pointing into the stack; on a find,
    /// `segments` leads to it.
    fn visit(walker: *Walker, comptime T: type, value: *const T) Error!bool {
        @setEvalBranchQuota(discovery.branch_quota);
        switch (@typeInfo(T)) {
            .optional => |optional| if (value.*) |*present| return walker.visit(optional.child, present),
            .@"struct" => |info| inline for (info.field_names, info.field_types, info.field_attrs) |name, Field, attributes| {
                if (attributes.@"comptime") continue;
                if (try walker.visitChild(Field, &@field(value.*, name), name)) return true;
            },
            .@"union" => |info| if (info.tag_type != null) switch (value.*) {
                inline else => |*payload, tag| return walker.visitChild(@TypeOf(payload.*), payload, @tagName(tag)),
            },
            .array => |array| for (value, 0..) |*item, index| {
                if (try walker.visitChild(array.child, item, try walker.indexSegment(index))) return true;
            },
            .pointer => |pointer| switch (pointer.size) {
                .slice => {
                    if (value.len == 0) return false;
                    if (walker.stack.holds(@intFromPtr(value.ptr))) return true;
                    if (comptime !mayHoldLists(pointer.child)) return false;
                    for (value.*, 0..) |*item, index| {
                        if (try walker.visitChild(pointer.child, item, try walker.indexSegment(index))) return true;
                    }
                },
                .one => if (comptime !isOpaque(pointer.child)) return walker.stack.holds(@intFromPtr(value.*)),
                .many, .c => {},
            },
            else => {},
        }
        return false;
    }

    fn visitChild(walker: *Walker, comptime T: type, value: *const T, segment: []const u8) Error!bool {
        try walker.segments.append(walker.arena, segment);
        if (try walker.visit(T, value)) return true;
        _ = walker.segments.pop();
        return false;
    }

    fn indexSegment(walker: *Walker, position: usize) Error![]const u8 {
        return walker.arena.print("[{d}]", .{position});
    }

    /// The segments joined as `--set` spells a path, indices glued to their list.
    fn path(walker: *Walker) Error![]const u8 {
        var joined: std.ArrayList(u8) = .empty;
        for (walker.segments.items, 0..) |segment, position| {
            if (position != 0 and segment[0] != '[') try joined.append(walker.arena, '.');
            try joined.appendSlice(walker.arena, segment);
        }
        return joined.items;
    }
};

/// Whether a value of `T` can hold a list or a pointer itself, so a list of them is walked.
fn mayHoldLists(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum", .comptime_int, .comptime_float, .void, .type, .null => false,
        else => true,
    };
}

/// Pointers to functions and opaque types point into code or foreign memory, never a stack.
fn isOpaque(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"fn", .@"opaque" => true,
        else => false,
    };
}

const testing = std.testing;

const Wallpaper = struct { path: []const u8, fit: ?u8 = null };
const Choice = union(enum) { none, colors: []const u32 };
const Tree = struct {
    name: []const u8 = "kosm",
    wallpapers: []const Wallpaper = &.{},
    icons: ?struct { choice: Choice = .none } = null,
    layers: [2][]const u32 = .{ &.{}, &.{} },
    reload: ?*const fn () void = null,
};

/// A tree built the wrong way: a list of run-time values written in a function that returns.
noinline fn deadTree(value: u32, comptime field: enum { colors, wallpaper_path, layers }) Tree {
    var items = [_]u32{ value, value };
    std.mem.doNotOptimizeAway(&items);
    var path_buffer: [8]u8 = @splat('a');
    std.mem.doNotOptimizeAway(&path_buffer);
    var tree: Tree = .{};
    switch (field) {
        .colors => tree.icons = .{ .choice = .{ .colors = &items } },
        .wallpaper_path => tree.wallpapers = keepForTest(&.{.{ .path = &path_buffer }}),
        .layers => tree.layers[1] = &items,
    }
    return tree;
}

var kept_wallpapers: [1]Wallpaper = undefined;

fn keepForTest(wallpapers: []const Wallpaper) []const Wallpaper {
    kept_wallpapers[0] = wallpapers[0];
    return &kept_wallpapers;
}

test "a list written in a returned function is found by its path, inside unions, lists and arrays" {
    var marker: u8 = 0;
    std.mem.doNotOptimizeAway(&marker);
    const stack: Stack = .below(@intFromPtr(&marker));
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("icons.choice.colors", (try findDeadList(arena, deadTree(3, .colors), stack)).?);
    try testing.expectEqualStrings("wallpapers[0].path", (try findDeadList(arena, deadTree(3, .wallpaper_path), stack)).?);
    try testing.expectEqualStrings("layers[1]", (try findDeadList(arena, deadTree(3, .layers), stack)).?);
}

const constant_colors = [_]u32{ 1, 2 };

fn reloadNothing() void {}

test "constants, kept lists and live memory are no dead lists" {
    var marker: u8 = 0;
    std.mem.doNotOptimizeAway(&marker);
    const stack: Stack = .below(@intFromPtr(&marker));
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const heap_colors = try arena.dupe(u32, &.{ 5, 6 });
    const tree: Tree = .{
        .name = "constant",
        .wallpapers = &.{.{ .path = "~/a.jxl" }},
        .icons = .{ .choice = .{ .colors = heap_colors } },
        .layers = .{ &constant_colors, &.{} },
        .reload = reloadNothing,
    };
    try testing.expectEqual(null, try findDeadList(arena, tree, stack));
}
