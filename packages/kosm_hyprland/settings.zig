//! Turns the app's sections into what Hyprland's Lua config reads: nested tables shaped like
//! `hl.config` (`general.col.active_border`). An option is an optional field, a section a
//! struct field; null options and sections holding none are left out (D27).

const std = @import("std");
const kosm = @import("kosm");

const Allocator = std.mem.Allocator;

/// One set option.
pub const Setting = struct {
    /// Dot-separated keys, e.g. `decoration.blur.size`.
    path: []const u8,
    value: kosm.Value,
    /// Why Hyprland can't read the value, if it can't.
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

/// `settings`, from `list`, as nested tables: `general.border_size` is the table `general`
/// holding `border_size`.
pub fn tree(allocator: Allocator, settings: []const Setting) Allocator.Error!kosm.Value {
    return nest(allocator, settings, 0);
}

fn nest(allocator: Allocator, settings: []const Setting, depth: usize) Allocator.Error!kosm.Value {
    var entries: std.ArrayList(kosm.Value.Entry) = .empty;
    var index: usize = 0;
    while (index < settings.len) {
        const key = segment(settings[index].path, depth);
        if (segment(settings[index].path, depth + 1).len == 0) {
            try entries.append(allocator, .{ .key = key, .value = settings[index].value });
            index += 1;
            continue;
        }
        var end = index + 1;
        while (end < settings.len and std.mem.eql(u8, segment(settings[end].path, depth), key)) end += 1;
        try entries.append(allocator, .{ .key = key, .value = try nest(allocator, settings[index..end], depth + 1) });
        index = end;
    }
    return .{ .table = entries.items };
}

/// The `depth`-th key of `path`, or empty past its end.
fn segment(path: []const u8, depth: usize) []const u8 {
    var keys = std.mem.splitScalar(u8, path, '.');
    for (0..depth) |_| _ = keys.next() orelse return "";
    return keys.next() orelse "";
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
