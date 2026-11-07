//! The value tree `generate` hands to an adapter's `serialize` (D64), built from a plain struct.

const std = @import("std");
const Color = @import("Color.zig");
const Raw = @import("Raw.zig");
const ClippedColors = @import("ClippedColors.zig");

/// A value an adapter can write. Strings are quoted by the adapter, `raw` text is not (D42).
pub const Value = union(enum) {
    /// Named values in declaration order.
    table: []const Entry,
    /// Values in order.
    list: []const Value,
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    /// Printed in the file's color format (D61).
    color: Color,
    /// Written verbatim.
    raw: []const u8,
    /// Parts written back to back with no separator, each the way the adapter writes it (D89):
    /// text with numbers or colors in it (`2pt`) that still follows the file's format.
    joined: []const Value,

    /// One key and its value in a `table`.
    pub const Entry = @import("value/Entry.zig");
};

/// Errors from `from`.
pub const FromError = std.mem.Allocator.Error || error{ IntegerTooLarge, NullInList };

/// Converts a plain struct by reflection: strings, integers, floats, bools, enums (by tag name),
/// colors, `color.format(...)` text (a string), `kosm.raw` text, nested structs (tables), and arrays, slices or tuples (lists).
/// A `null` optional field is left out of its table. A `Value`, at any depth, is taken as it
/// is, for apps that build the tree themselves (D64). Everything lives in `allocator`. Text an app
/// formatted with a clipped color (D48) is noted in `clipped`, for kosm to warn about (D88).
pub fn from(allocator: std.mem.Allocator, clipped: *ClippedColors, values: anytype) FromError!Value {
    const T = @TypeOf(values);
    if (T == Value) return values;
    if (T == Color) return .{ .color = values };
    if (T == Raw) return .{ .raw = values.text };
    // `values` is a copy, so its bytes must outlive this call.
    if (T == Color.Text) {
        if (values.clipped) |color| clipped.add(color, 0);
        return .{ .string = try allocator.dupe(u8, values.slice()) };
    }
    if (comptime isString(T)) return .{ .string = values };
    switch (@typeInfo(T)) {
        .bool => return .{ .boolean = values },
        .int, .comptime_int => return .{ .integer = std.math.cast(i64, values) orelse return error.IntegerTooLarge },
        .float, .comptime_float => return .{ .float = values },
        .@"enum" => return .{ .string = @tagName(values) },
        .enum_literal => return .{ .string = @tagName(values) },
        .optional => return if (values) |present| from(allocator, clipped, present) else error.NullInList,
        .@"struct" => |info| {
            if (info.is_tuple) return fromList(allocator, clipped, values);
            return fromStruct(allocator, clipped, values);
        },
        .array => return fromList(allocator, clipped, values),
        .pointer => |pointer| switch (pointer.size) {
            .slice => return fromList(allocator, clipped, values),
            .one => if (@typeInfo(pointer.child) == .array) return fromList(allocator, clipped, values.*),
            else => {},
        },
        else => {},
    }
    @compileError("kosm.generate: values of type " ++ @typeName(T) ++ " cannot be written to a file");
}

fn fromStruct(allocator: std.mem.Allocator, clipped: *ClippedColors, values: anytype) FromError!Value {
    const info = @typeInfo(@TypeOf(values)).@"struct";
    var entries: std.ArrayList(Value.Entry) = try .initCapacity(allocator, info.field_names.len);
    inline for (info.field_names, info.field_types) |name, Field| {
        const field = @field(values, name);
        if (@typeInfo(Field) == .optional) {
            if (field) |present| entries.appendAssumeCapacity(.{ .key = name, .value = try from(allocator, clipped, present) });
        } else {
            entries.appendAssumeCapacity(.{ .key = name, .value = try from(allocator, clipped, field) });
        }
    }
    return .{ .table = entries.items };
}

fn fromList(allocator: std.mem.Allocator, clipped: *ClippedColors, values: anytype) FromError!Value {
    const T = @TypeOf(values);
    if (@typeInfo(T) == .@"struct") {
        const items = try allocator.alloc(Value, values.len);
        inline for (0..values.len) |index| items[index] = try from(allocator, clipped, values[index]);
        return .{ .list = items };
    }
    const items = try allocator.alloc(Value, values.len);
    for (values, items) |item, *slot| slot.* = try from(allocator, clipped, item);
    return .{ .list = items };
}

fn isString(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    const pointer = info.pointer;
    if (pointer.size == .slice) return pointer.child == u8;
    if (pointer.size == .one) {
        const child = @typeInfo(pointer.child);
        return child == .array and child.array.child == u8;
    }
    return false;
}

const testing = std.testing;

test "from writes formatted color text as a string, not as its buffer" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var clipped: ClippedColors = .{};
    const color = try Color.parseHex("#5e81ac");
    const tree = try from(arena.allocator(), &clipped, .{ .border = color.format("rgba({})", &.{.hex8}) });
    try testing.expectEqualStrings("rgba(5e81acff)", tree.table[0].value.string);
    try testing.expectEqual(0, clipped.list().len);
}

test "from notes text an app formatted from a clipped color" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var clipped: ClippedColors = .{};
    const vivid: Color = .{ .lightness = 0.9, .chroma = 0.4, .hue = 140 };
    _ = try from(arena.allocator(), &clipped, .{ .border = vivid.format("rgba({})", &.{.hex8}), .glow = vivid });
    try testing.expectEqual(1, clipped.list().len);
    try testing.expectEqual(vivid, clipped.list()[0].color);
}

test "from turns a nested struct into tables in declaration order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var clipped: ClippedColors = .{};
    const Mode = enum { dark, light };
    const blur: ?u8 = null;
    const tree = try from(arena.allocator(), &clipped, .{
        .name = "frost",
        .size = @as(u16, 12),
        .opacity = 0.5,
        .enabled = true,
        .mode = Mode.dark,
        .accent = try Color.parseHex("#5e81ac"),
        .literal = Raw{ .text = "rgba(0, 0, 0, 0)" },
        .blur = blur,
        .nested = .{ .first = 1, .second = "two" },
        .list = [_]u8{ 1, 2 },
    });
    const entries = tree.table;
    try testing.expectEqual(9, entries.len);
    try testing.expectEqualStrings("name", entries[0].key);
    try testing.expectEqualStrings("frost", entries[0].value.string);
    try testing.expectEqual(12, entries[1].value.integer);
    try testing.expectEqual(0.5, entries[2].value.float);
    try testing.expect(entries[3].value.boolean);
    try testing.expectEqualStrings("dark", entries[4].value.string);
    try testing.expectEqualStrings("#5e81ac", entries[5].value.color.hex().slice());
    try testing.expectEqualStrings("rgba(0, 0, 0, 0)", entries[6].value.raw);
    try testing.expectEqualStrings("nested", entries[7].key);
    try testing.expectEqualStrings("two", entries[7].value.table[1].value.string);
    try testing.expectEqual(2, entries[8].value.list[1].integer);
}

test "from takes an already built value as it is" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var clipped: ClippedColors = .{};
    const built: Value = .{ .raw = "0.5pt" };
    const tree = try from(arena.allocator(), &clipped, .{ .border = built, .size = 2 });
    try testing.expectEqualStrings("0.5pt", tree.table[0].value.raw);
    try testing.expectEqualStrings("0.5pt", (try from(arena.allocator(), &clipped, built)).raw);
}

test "from rejects integers that do not fit and nulls inside lists" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var clipped: ClippedColors = .{};
    try testing.expectError(error.IntegerTooLarge, from(arena.allocator(), &clipped, @as(u64, std.math.maxInt(u64))));
    const list = [_]?u8{ 1, null };
    try testing.expectError(error.NullInList, from(arena.allocator(), &clipped, list));
}
