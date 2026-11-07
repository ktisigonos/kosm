//! Turns the app's sections into what Hyprland's Lua config reads: nested tables shaped like
//! `hl.config` (`general.col.active_border`). An option is an optional field, a section a
//! struct field; null options and sections holding none are left out (D27).

const std = @import("std");
const kosm = @import("kosm");

const Allocator = std.mem.Allocator;

/// One set option, or an extra (D99).
pub const Setting = struct {
    /// Dot-separated keys, e.g. `decoration.blur.size`, as the user wrote it.
    path: []const u8,
    /// The keys of `path`, outermost first. Null in an extra's means `*`, any one key.
    keys: []const ?[]const u8,
    value: kosm.Value,
    /// Why Hyprland can't read the value, if it can't.
    problem: ?[]const u8 = null,
    /// Whether it came from the app's `extra` rather than one of its fields.
    extra: bool = false,
};

/// Two settings where one would write over the other.
pub const Overlap = struct { extra: Setting, other: Setting };

/// Every set option of `sections` (the app, or one section) with its path, in declaration
/// order, so the options of one section are next to each other. Fields named in `skipped` are
/// not Hyprland's.
pub fn list(allocator: Allocator, sections: anytype, comptime skipped: []const []const u8) Allocator.Error![]const Setting {
    var found: std.ArrayList(Setting) = .empty;
    try collect(allocator, sections, "", skipped, &found);
    return found.items;
}

/// The first extra whose keys equal, contain or lie inside those of another setting or an
/// earlier extra (D99), which would write one value over the other.
pub fn overlap(settings: []const Setting) ?Overlap {
    for (settings, 0..) |setting, index| {
        if (!setting.extra) continue;
        for (settings[0..index]) |other| {
            if (nested(setting.keys, other.keys)) return .{ .extra = setting, .other = other };
        }
    }
    return null;
}

/// Whether the shorter of `a` and `b` starts the longer, `*` matching any key.
fn nested(a: []const ?[]const u8, b: []const ?[]const u8) bool {
    for (a[0..@min(a.len, b.len)], b[0..@min(a.len, b.len)]) |a_key, b_key| {
        const a_name = a_key orelse continue;
        const b_name = b_key orelse continue;
        if (!std.mem.eql(u8, a_name, b_name)) return false;
    }
    return true;
}

/// `settings` as nested tables: `general.border_size` is the table `general` holding
/// `border_size`. Settings sharing a table land in it in order, wherever they are in the list.
/// Asserts no two overlap (`overlap`) and no key is `*`.
pub fn tree(allocator: Allocator, settings: []const Setting) Allocator.Error!kosm.Value {
    return nest(allocator, settings, 0);
}

fn nest(allocator: Allocator, settings: []const Setting, depth: usize) Allocator.Error!kosm.Value {
    var entries: std.ArrayList(kosm.Value.Entry) = .empty;
    const placed = try allocator.alloc(bool, settings.len);
    @memset(placed, false);
    for (settings, 0..) |setting, index| {
        if (placed[index]) continue;
        const key = setting.keys[depth].?;
        if (setting.keys.len == depth + 1) {
            try entries.append(allocator, .{ .key = key, .value = setting.value });
            continue;
        }
        var inside: std.ArrayList(Setting) = .empty;
        for (settings[index..], placed[index..]) |other, *other_placed| {
            if (other.keys.len > depth + 1 and std.mem.eql(u8, other.keys[depth].?, key)) {
                try inside.append(allocator, other);
                other_placed.* = true;
            }
        }
        try entries.append(allocator, .{ .key = key, .value = try nest(allocator, inside.items, depth + 1) });
    }
    return .{ .table = entries.items };
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
                .path = path,
                .keys = try fieldKeys(allocator, path),
                .value = try value(allocator, option),
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
