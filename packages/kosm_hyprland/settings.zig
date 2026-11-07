//! Turns the app's sections into what Hyprland's Lua config reads: nested tables shaped like
//! `hl.config` (`general.col.active_border`). An option is an optional field, a section a
//! struct field; null options and sections holding none are left out (D27).

const std = @import("std");
const kosm = @import("kosm");

const Allocator = std.mem.Allocator;

/// One set option: its path in `hl.config` and its value.
pub const Setting = struct {
    /// Dot-separated keys, e.g. `decoration.blur.size`.
    path: []const u8,
    value: kosm.Value,
};

/// Every set option of `sections` (the app, or one section), as nested tables. Fields named in
/// `skipped` are not Hyprland's.
pub fn tree(allocator: Allocator, sections: anytype, comptime skipped: []const []const u8) Allocator.Error!kosm.Value {
    @setEvalBranchQuota(100_000);
    var entries: std.ArrayList(kosm.Value.Entry) = .empty;
    const Section = @TypeOf(sections);
    inline for (@typeInfo(Section).@"struct".field_names, @typeInfo(Section).@"struct".field_types) |name, Field| {
        if (comptime isSkipped(name, skipped)) continue;
        const field = @field(sections, name);
        if (@typeInfo(Field) == .optional) {
            if (field) |option| try entries.append(allocator, .{ .key = name, .value = try value(allocator, option) });
        } else {
            const inner = try tree(allocator, field, &.{});
            if (inner.table.len != 0) try entries.append(allocator, .{ .key = name, .value = inner });
        }
    }
    return .{ .table = entries.items };
}

/// Every set option of `sections` with its path, in declaration order.
pub fn list(allocator: Allocator, sections: anytype, comptime skipped: []const []const u8) Allocator.Error![]const Setting {
    var found: std.ArrayList(Setting) = .empty;
    try collect(allocator, sections, "", skipped, &found);
    return found.items;
}

fn collect(allocator: Allocator, sections: anytype, comptime prefix: []const u8, comptime skipped: []const []const u8, found: *std.ArrayList(Setting)) Allocator.Error!void {
    @setEvalBranchQuota(100_000);
    const Section = @TypeOf(sections);
    inline for (@typeInfo(Section).@"struct".field_names, @typeInfo(Section).@"struct".field_types) |name, Field| {
        if (comptime isSkipped(name, skipped)) continue;
        const field = @field(sections, name);
        const path = prefix ++ name;
        if (@typeInfo(Field) == .optional) {
            if (field) |option| try found.append(allocator, .{ .path = path, .value = try value(allocator, option) });
        } else {
            try collect(allocator, field, path ++ ".", &.{}, found);
        }
    }
}

/// One option's value: types with a `value` method write themselves, enums their tag name.
fn value(allocator: Allocator, option: anytype) Allocator.Error!kosm.Value {
    const T = @TypeOf(option);
    if (T == kosm.Color) return .{ .color = option };
    if (T == []const u8) return .{ .string = option };
    if (comptime std.meta.hasMethod(T, "value")) return option.value(allocator);
    return switch (@typeInfo(T)) {
        .bool => .{ .boolean = option },
        .int => .{ .integer = option },
        .float => .{ .float = option },
        .@"enum" => .{ .string = @tagName(option) },
        else => @compileError("kosm_hyprland: an option of type " ++ @typeName(T) ++ " needs a value method"),
    };
}

fn isSkipped(comptime name: []const u8, comptime skipped: []const []const u8) bool {
    for (skipped) |skip| {
        if (std.mem.eql(u8, skip, name)) return true;
    }
    return false;
}
