//! Turns the app's sections into what Hyprland's Lua config reads: nested tables shaped like
//! `hl.config` (`general.col.active_border`). An option is an optional field, a section a
//! struct field; null options and sections holding none are left out.

const std = @import("std");
const kosm = @import("kosm");

const Allocator = std.mem.Allocator;

/// One set option, and why Hyprland can't read it, if it can't.
pub const Setting = struct {
    keyed: kosm.Setting.Keyed,
    problem: ?[]const u8 = null,
};

/// Every set option of `sections` (the app, or one section) with its path, in declaration
/// order, so the options of one section are next to each other. Fields named in `skipped` are
/// not Hyprland's.
pub fn list(allocator: Allocator, sections: anytype, comptime skipped: []const []const u8) Allocator.Error![]const Setting {
    var found: std.ArrayList(Setting) = .empty;
    try collect(allocator, sections, "", skipped, &found);
    return found.items;
}

/// The options of `found` alone, for `kosm.Setting.withExtras`.
pub fn keyed(allocator: Allocator, found: []const Setting) Allocator.Error![]const kosm.Setting.Keyed {
    const result = try allocator.alloc(kosm.Setting.Keyed, found.len);
    for (found, result) |setting, *slot| slot.* = setting.keyed;
    return result;
}

/// The keys of a field path, which never holds quotes or `*`.
fn fieldKeys(allocator: Allocator, path: []const u8) Allocator.Error![]const ?[]const u8 {
    var keys: std.ArrayList(?[]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, path, '.');
    while (parts.next()) |part| try keys.append(allocator, part);
    return keys.items;
}

fn collect(allocator: Allocator, sections: anytype, comptime prefix: []const u8, comptime skipped: []const []const u8, found: *std.ArrayList(Setting)) Allocator.Error!void {
    // Walking Hyprland's 407 options takes more than the default quota.
    @setEvalBranchQuota(100_000);
    const Section = @TypeOf(sections);
    inline for (@typeInfo(Section).@"struct".field_names, @typeInfo(Section).@"struct".field_types) |name, Field| {
        if (comptime isSkipped(name, skipped)) continue;
        const field = @field(sections, name);
        const path = prefix ++ name;
        if (@typeInfo(Field) == .optional) {
            if (field) |option| try found.append(allocator, .{
                .keyed = .{ .path = path, .keys = try fieldKeys(allocator, path), .value = try value(allocator, option) },
                .problem = try problem(allocator, option),
            });
        } else {
            try collect(allocator, field, path ++ ".", &.{}, found);
        }
    }
}

/// One option's value: types with a `value` method write themselves, enums their tag name or,
/// when they declare `numbered`, their number.
fn value(allocator: Allocator, option: anytype) Allocator.Error!kosm.Value {
    const T = @TypeOf(option);
    if (T == kosm.Color) return .{ .color = option };
    if (T == []const u8) return .{ .string = option };
    if (comptime std.meta.hasMethod(T, "value")) return option.value(allocator);
    return switch (@typeInfo(T)) {
        .bool => .{ .boolean = option },
        .int => .{ .integer = option },
        .float => .{ .float = option },
        .@"enum" => if (@hasDecl(T, "numbered")) .{ .integer = @backingInt(option) } else .{ .string = @tagName(option) },
        else => @compileError("kosm_hyprland: an option of type " ++ @typeName(T) ++ " needs a value method"),
    };
}

fn problem(allocator: Allocator, option: anytype) Allocator.Error!?[]const u8 {
    if (comptime std.meta.hasMethod(@TypeOf(option), "problem")) return option.problem(allocator);
    return null;
}

fn isSkipped(comptime name: []const u8, comptime skipped: []const []const u8) bool {
    for (skipped) |skip| {
        if (std.mem.eql(u8, skip, name)) return true;
    }
    return false;
}
