//! Turns `Prefs` into the flat table of prefs the `userjs` adapter writes (D96).

const std = @import("std");
const kosm = @import("kosm");
const Prefs = @import("Prefs.zig");

/// Every set pref as one entry named by its whole name (`zen.theme.accent-color`), in field order.
pub fn table(allocator: std.mem.Allocator, prefs: Prefs) std.mem.Allocator.Error!kosm.Value {
    var entries: std.ArrayList(kosm.Value.Entry) = .empty;
    try appendGroup(allocator, &entries, "", prefs);
    return .{ .table = entries.items };
}

fn appendGroup(allocator: std.mem.Allocator, entries: *std.ArrayList(kosm.Value.Entry), prefix: []const u8, group: anytype) std.mem.Allocator.Error!void {
    const Group = @TypeOf(group);
    const info = @typeInfo(Group).@"struct";
    inline for (info.field_names, info.field_types) |field_name, Field| {
        const segment = comptime prefName(Group, field_name);
        const name = if (prefix.len == 0) segment else try std.mem.concat(allocator, u8, &.{ prefix, ".", segment });
        const field = @field(group, field_name);
        switch (@typeInfo(Field)) {
            .@"struct" => try appendGroup(allocator, entries, name, field),
            .optional => if (field) |set| try entries.append(allocator, .{ .key = name, .value = prefValue(set) }),
            else => @compileError("pref groups hold groups and optional prefs, not " ++ @typeName(Field)),
        }
    }
}

/// A field's segment of the pref name: its `pref_names` entry, or the field name with `_` as `-`.
fn prefName(comptime Group: type, comptime field_name: []const u8) []const u8 {
    if (@hasDecl(Group, "pref_names") and @hasField(@TypeOf(Group.pref_names), field_name)) return @field(Group.pref_names, field_name);
    comptime {
        var name: [field_name.len]u8 = field_name[0..].*;
        std.mem.replaceScalar(u8, &name, '_', '-');
        const final = name;
        return &final;
    }
}

fn prefValue(value: anytype) kosm.Value {
    const T = @TypeOf(value);
    if (T == kosm.Color) return .{ .color = value };
    return switch (@typeInfo(T)) {
        .bool => .{ .boolean = value },
        .int => .{ .integer = value },
        .@"enum" => .{ .integer = @backingInt(value) },
        else => @compileError("a pref is a bool, an integer, an enum or a color, not " ++ @typeName(T)),
    };
}

const testing = std.testing;

test "set prefs get their whole Firefox names, null ones are left out" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var prefs: Prefs = .{};
    prefs.zen.theme.accent_color = kosm.hex("268078");
    prefs.zen.theme.border_radius = -1;
    prefs.zen.view.window.scheme = .light;
    prefs.zen.view.compact.hide_toolbar = true;
    prefs.browser.display.background_color = kosm.hex("041c26");
    prefs.browser.tabs.allow_transparent_browser = false;
    prefs.toolkit.legacy_user_profile_customizations.stylesheets = true;

    const entries = (try table(arena.allocator(), prefs)).table;
    const expected = [_][]const u8{
        "zen.theme.accent-color",
        "zen.theme.border-radius",
        "zen.view.window.scheme",
        "zen.view.compact.hide-toolbar",
        "browser.display.background_color",
        "browser.tabs.allow_transparent_browser",
        "toolkit.legacyUserProfileCustomizations.stylesheets",
    };
    try testing.expectEqual(expected.len, entries.len);
    for (expected, entries) |name, entry| try testing.expectEqualStrings(name, entry.key);
    try testing.expectEqual(1, entries[2].value.integer);
    try testing.expectEqual(-1, entries[1].value.integer);
}
