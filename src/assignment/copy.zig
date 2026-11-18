//! Deep copies of typed values, so a value a script holds owns every list it reaches.

const std = @import("std");

const branch_quota = 100_000;

/// `value` with every list and pointed-to value inside it copied into `arena`, so changing an
/// item of the copy never changes the original, and the copy outlives what the original
/// pointed into. Text is shared, as nothing changes it in place; functions and opaque
/// pointers are kept as they are.
pub fn deep(comptime T: type, arena: std.mem.Allocator, value: T) std.mem.Allocator.Error!T {
    @setEvalBranchQuota(branch_quota);
    if (comptime !holdsPointers(T)) return value;
    switch (@typeInfo(T)) {
        .optional => |optional| return if (value) |present| try deep(optional.child, arena, present) else null,
        .@"struct" => |info| {
            var result = value;
            inline for (info.field_names, info.field_types, info.field_attrs) |name, Field, attributes| {
                if (attributes.@"comptime") continue;
                @field(result, name) = try deep(Field, arena, @field(value, name));
            }
            return result;
        },
        .@"union" => |info| {
            if (info.tag_type == null) return value;
            switch (value) {
                inline else => |payload, tag| return @unionInit(T, @tagName(tag), try deep(@TypeOf(payload), arena, payload)),
            }
        },
        .array => |array| {
            var result: T = undefined;
            for (&result, value) |*slot, item| slot.* = try deep(array.child, arena, item);
            return result;
        },
        .pointer => |pointer| switch (pointer.size) {
            .slice => {
                if (pointer.child == u8) return value;
                const items = if (pointer.sentinel()) |sentinel|
                    try arena.allocSentinel(pointer.child, value.len, sentinel)
                else
                    try arena.alloc(pointer.child, value.len);
                for (items, value) |*slot, item| slot.* = try deep(pointer.child, arena, item);
                return items;
            },
            .one => {
                if (comptime !isData(pointer.child)) return value;
                const copy = try arena.create(pointer.child);
                copy.* = try deep(pointer.child, arena, value.*);
                return copy;
            },
            .many, .c => return value,
        },
        else => return value,
    }
}

/// Whether a value of `T` may point anywhere, so copying it shallowly could share memory.
fn holdsPointers(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => true,
        .optional => |optional| holdsPointers(optional.child),
        .array => |array| holdsPointers(array.child),
        .@"struct" => |info| inline for (info.field_types, info.field_attrs) |Field, attributes| {
            if (!attributes.@"comptime" and holdsPointers(Field)) break true;
        } else false,
        .@"union" => |info| inline for (info.field_types) |Field| {
            if (holdsPointers(Field)) break true;
        } else false,
        else => false,
    };
}

/// Whether `T` is a value that can be copied, not code or something opaque.
fn isData(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"opaque", .@"fn" => false,
        else => true,
    };
}

const testing = std.testing;

test "a deep copy owns its lists, items of items and pointed-to values" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const Inner = struct { values: []const u16 };
    const Outer = struct { inner: []const Inner, one: *const u16, name: []const u8, maybe: ?[]const u16 };
    var values = [_]u16{ 1, 2 };
    var inner = [_]Inner{.{ .values = &values }};
    var number: u16 = 7;
    const original: Outer = .{ .inner = &inner, .one = &number, .name = "kept", .maybe = &values };
    const copy = try deep(Outer, arena_state.allocator(), original);
    values[0] = 9;
    number = 8;
    try testing.expectEqualSlices(u16, &.{ 1, 2 }, copy.inner[0].values);
    try testing.expectEqualSlices(u16, &.{ 1, 2 }, copy.maybe.?);
    try testing.expectEqual(7, copy.one.*);
    try testing.expect(copy.name.ptr == original.name.ptr);
}

test "a deep copy of a union copies the list of its active tag" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const Choice = union(enum) { none, some: []const u8, many: []const u32 };
    var items = [_]u32{ 3, 4 };
    const copy = try deep(Choice, arena_state.allocator(), .{ .many = &items });
    items[1] = 0;
    try testing.expectEqualSlices(u32, &.{ 3, 4 }, copy.many);
}
