//! Values read from text the way a command-line flag or `--set` gives them, and how a type is
//! described in messages about a wrong value.

const std = @import("std");
const Color = @import("../Color.zig");
const ColorChoice = @import("../color_choice.zig").ColorChoice;
const Palette = @import("../Palette.zig");
const Value = @import("../value.zig").Value;
const Image = @import("../Image.zig");
const File = @import("../File.zig");
const kosmos = @import("../kosmos.zig");

/// Reads one value of `T` from text: a color, text, bool, number or enum, or an optional of one.
/// The returned text points into `text`.
pub fn parse(comptime T: type, text: []const u8) !T {
    if (T == Color) return Color.parse(text);
    if (T == ColorChoice) return ColorChoice.parse(text);
    if (T == []const u8) return text;
    return switch (@typeInfo(T)) {
        .optional => |optional| try parse(optional.child, text),
        .bool => if (std.mem.eql(u8, text, "true")) true else if (std.mem.eql(u8, text, "false")) false else error.InvalidBool,
        .int => try std.fmt.parseInt(T, text, 10),
        .float => blk: {
            const number = try std.fmt.parseFloat(T, text);
            if (!std.math.isFinite(number)) return error.InvalidFloat;
            break :blk number;
        },
        .@"enum" => std.meta.stringToEnum(T, text) orelse error.InvalidEnum,
        else => @compileError("a " ++ @typeName(T) ++ " cannot be read from text; use a bool, number, enum, string or color"),
    };
}

/// Whether `parse` reads a `T` (not counting optionals): a color, text, bool, number or enum.
pub fn isParseable(comptime T: type) bool {
    if (T == Color or T == ColorChoice or T == []const u8) return true;
    return switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum" => true,
        else => false,
    };
}

/// What a value of `T` looks like, for "expected ...".
pub fn describe(comptime T: type) []const u8 {
    @setEvalBranchQuota(100_000);
    if (T == Color) return "a color (#rrggbb, rgb(...), hsl(...) or oklch(...))";
    if (T == ColorChoice) return "a color (#rrggbb, rgb(...), hsl(...) or oklch(...)) or a hue (" ++ enumList(Palette.Hue) ++ ")";
    if (T == Value) return "a value to write (a table, list, string, number or boolean)";
    if (T == []const u8) return "text";
    if (T == Image or T == File) return "a path, or a table of its fields (" ++ comptime fieldList(T) ++ ")";
    if (comptime kosmos.is(T)) return "the name of a kosmos giving a " ++ @typeName(T.Tree);
    return switch (@typeInfo(T)) {
        .optional => |optional| comptime describe(optional.child) ++ " or null",
        .bool => "true or false",
        .int => "an integer that fits " ++ @typeName(T),
        .float => "a number",
        .@"enum" => "one of " ++ enumList(T),
        .@"struct" => "a table of its fields (" ++ comptime fieldList(T) ++ ")",
        .@"union" => comptime describeUnion(T),
        .array => |array| std.fmt.comptimePrint("a list of {d} items", .{array.len}),
        .pointer => |pointer| if (pointer.size == .slice) "a list" else @typeName(T),
        else => @typeName(T),
    };
}

fn describeUnion(comptime T: type) []const u8 {
    const info = @typeInfo(T).@"union";
    comptime var plain: []const u8 = "";
    comptime var with_value: []const u8 = "";
    inline for (info.field_names, info.field_types) |name, Payload| {
        if (Payload == void) {
            plain = plain ++ (if (plain.len == 0) "" else ", ") ++ name;
        } else {
            with_value = with_value ++ (if (with_value.len == 0) "" else ", ") ++ name;
        }
    }
    if (with_value.len == 0) return "one of " ++ plain;
    const table = "a table holding one of " ++ with_value;
    if (plain.len == 0) return table;
    return "one of " ++ plain ++ ", or " ++ table;
}

/// `dark, light`
pub fn enumList(comptime Enum: type) []const u8 {
    comptime var list: []const u8 = "";
    inline for (@typeInfo(Enum).@"enum".field_names, 0..) |name, index| {
        list = list ++ (if (index == 0) "" else ", ") ++ name;
    }
    return list;
}

/// The names of a struct's fields that can be set, comma-separated.
pub fn fieldList(comptime T: type) []const u8 {
    const info = @typeInfo(T).@"struct";
    comptime var list: []const u8 = "";
    inline for (info.field_names, info.field_attrs) |name, attributes| {
        if (attributes.@"comptime") continue;
        list = list ++ (if (list.len == 0) "" else ", ") ++ name;
    }
    return list;
}

const testing = std.testing;

test "parse reads every kind of value and rejects what is not one" {
    try testing.expectEqual(true, try parse(bool, "true"));
    try testing.expectError(error.InvalidBool, parse(bool, "yes"));
    try testing.expectEqual(-3, try parse(i8, "-3"));
    try testing.expectError(error.Overflow, parse(u8, "256"));
    try testing.expectEqual(0.5, try parse(?f32, "0.5"));
    try testing.expectError(error.InvalidFloat, parse(f64, "inf"));
    try testing.expectEqualStrings("#ff0000", (try parse(Color, "rgb(255, 0, 0)")).hex().slice());
    try testing.expectEqual(Palette.Hue.sky, (try parse(ColorChoice, "sky")).hue);
}

test "describe names unions by their tags, with and without values" {
    const Style = union(enum) { disabled, bold, size: u16 };
    try testing.expectEqualStrings("one of disabled, bold, or a table holding one of size", describe(Style));
    try testing.expectEqualStrings("a list of 3 items", describe([3]u8));
    try testing.expectEqualStrings("a table of its fields (a, b) or null", describe(?struct { a: u8, b: u8 }));
}
