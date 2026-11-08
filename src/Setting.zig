//! A setting an app doesn't cover, written by path through the app's `extra` (D99), and what an
//! app needs to write its extras beside its own settings: `withExtras` checks them, `tree` nests
//! them for `generate`.

const Setting = @This();

const std = @import("std");
const Value = @import("value.zig").Value;
const Path = @import("Path.zig");
const Output = @import("Output.zig");

const Allocator = std.mem.Allocator;

/// Where it goes: dot-separated keys, `"quoted.keys"` for a key holding a dot (D32), e.g.
/// `plugin.dynamic_cursors.length`.
path: []const u8,
/// What to write there, formatted like the app's own settings: `.{ .integer = 24 }`.
value: Value,

/// A setting with its path split into keys.
pub const Keyed = @import("Setting/Keyed.zig");
/// How a file names its settings.
pub const Rules = @import("Setting/Rules.zig");

/// `own` followed by `extras`, read by `rules`. An extra whose path is bad, or whose keys equal,
/// contain or lie inside those of an own setting or an earlier extra, fails the apply naming
/// both (D99, G6). `file` is the file the extras go to, for the message.
pub fn withExtras(output: *Output, file: []const u8, own: []const Keyed, extras: []const Setting, rules: Rules) Output.Error![]const Keyed {
    var all: std.ArrayList(Keyed) = .empty;
    try all.appendSlice(output.allocator, own);
    for (extras) |extra| {
        const keys = try extraKeys(output, file, extra.path, rules);
        try all.append(output.allocator, .{ .path = extra.path, .keys = keys, .value = extra.value, .extra = true });
    }
    for (all.items, 0..) |setting, index| {
        if (!setting.extra) continue;
        for (all.items[0..index]) |other| {
            if (!clash(setting.keys, other.keys, rules.repeatable)) continue;
            const kind = if (other.extra) "extra" else "setting";
            return output.fail(file, "extra '{s}' and {s} '{s}' write the same key, or one inside the other; keep one (D99)", .{ setting.path, kind, other.path });
        }
    }
    return all.items;
}

fn extraKeys(output: *Output, file: []const u8, text: []const u8, rules: Rules) Output.Error![]const ?[]const u8 {
    if (rules.paths == .whole_name) {
        if (text.len == 0) return output.fail(file, "an extra's name is empty", .{});
        return output.allocator.dupe(?[]const u8, &.{text});
    }
    var failure: Path.Failure = .{};
    const path = Path.parse(output.allocator, text, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidKeyPath => return output.fail(file, "extra '{s}', column {d}: {s}", .{ text, failure.column, failure.problem.describe() }),
    };
    if (rules.paths == .one_key and path.segments.len != 1)
        return output.fail(file, "extra '{s}': this file's keys don't nest, so a path is one key", .{text});
    const keys = try output.allocator.alloc(?[]const u8, path.segments.len);
    for (path.segments, keys) |segment, *key| key.* = switch (segment) {
        .key => |name| name,
        .any => if (rules.any_key)
            null
        else
            return output.fail(file, "extra '{s}': '*' matches keys only in files kosm edits, not in one it generates", .{text}),
    };
    return keys;
}

/// Whether the shorter of `a` and `b` starts the longer, `*` matching any key, unless both are
/// the same repeatable top-level key.
fn clash(a: []const ?[]const u8, b: []const ?[]const u8, repeatable: []const []const u8) bool {
    const shorter = @min(a.len, b.len);
    for (a[0..shorter], b[0..shorter]) |a_key, b_key| {
        const a_name = a_key orelse continue;
        const b_name = b_key orelse continue;
        if (!std.mem.eql(u8, a_name, b_name)) return false;
    }
    if (a.len == 1 and b.len == 1) if (a[0]) |name| {
        for (repeatable) |key| if (std.mem.eql(u8, key, name)) return false;
    };
    return true;
}

/// Every value of `root`, a table, with the keys leading to it: tables are stepped into, every
/// other value is one setting. Paths quote keys holding a dot (D32).
pub fn leaves(allocator: Allocator, root: Value) Allocator.Error![]const Keyed {
    var found: std.ArrayList(Keyed) = .empty;
    var keys: std.ArrayList(?[]const u8) = .empty;
    try collectLeaves(allocator, root.table, &keys, &found);
    return found.items;
}

fn collectLeaves(allocator: Allocator, entries: []const Value.Entry, keys: *std.ArrayList(?[]const u8), found: *std.ArrayList(Keyed)) Allocator.Error!void {
    for (entries) |entry| {
        try keys.append(allocator, entry.key);
        defer _ = keys.pop();
        if (entry.value == .table) {
            try collectLeaves(allocator, entry.value.table, keys, found);
            continue;
        }
        const own_keys = try allocator.dupe(?[]const u8, keys.items);
        try found.append(allocator, .{ .path = try pathText(allocator, own_keys), .keys = own_keys, .value = entry.value });
    }
}

fn pathText(allocator: Allocator, keys: []const ?[]const u8) Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    for (keys, 0..) |key, index| {
        if (index != 0) text.writer.writeByte('.') catch return error.OutOfMemory;
        const name = key.?;
        const quoted = std.mem.indexOfScalar(u8, name, '.') != null;
        const written = if (quoted) text.writer.print("\"{s}\"", .{name}) else text.writer.writeAll(name);
        written catch return error.OutOfMemory;
    }
    return text.written();
}

/// `settings` as nested tables: `general.border_size` is the table `general` holding
/// `border_size`. Settings sharing a table land in it in order, wherever they are in the list;
/// a repeated key is written once per setting. Asserts no key is `*` and none clash
/// (`withExtras`).
pub fn tree(allocator: Allocator, settings: []const Keyed) Allocator.Error!Value {
    return nest(allocator, settings, 0);
}

fn nest(allocator: Allocator, settings: []const Keyed, depth: usize) Allocator.Error!Value {
    var entries: std.ArrayList(Value.Entry) = .empty;
    const placed = try allocator.alloc(bool, settings.len);
    @memset(placed, false);
    for (settings, 0..) |setting, index| {
        if (placed[index]) continue;
        const key = setting.keys[depth].?;
        if (setting.keys.len == depth + 1) {
            try entries.append(allocator, .{ .key = key, .value = setting.value });
            continue;
        }
        var inside: std.ArrayList(Keyed) = .empty;
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

const testing = std.testing;
const Diagnostics = @import("Diagnostics.zig");
const Warnings = @import("Warnings.zig");
const Plan = @import("Plan.zig");

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    plan: Plan,
    diagnostics: Diagnostics = .{},
    warnings: Warnings = undefined,
    output: Output = undefined,

    fn init(fixture: *Fixture) void {
        fixture.* = .{ .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        fixture.warnings = .init(fixture.arena.allocator());
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = "/home/test",
            .adapters = &.{},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "test",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
    }

    fn own(fixture: *Fixture, root: Value) ![]const Keyed {
        return leaves(fixture.arena.allocator(), root);
    }
};

const own_tree: Value = .{ .table = &.{
    .{ .key = "general", .value = .{ .table = &.{.{ .key = "border_size", .value = .{ .integer = 2 } }} } },
    .{ .key = "map", .value = .{ .string = "ctrl+a new_tab" } },
} };

test "extras that clash with a setting or an earlier extra fail naming both (D99)" {
    const cases = [_]struct { extras: []const Setting, rules: Rules = .{}, message: []const u8 }{
        .{ .extras = &.{.{ .path = "general.border_size", .value = .{ .integer = 3 } }}, .message = "extra 'general.border_size' and setting 'general.border_size' write the same key, or one inside the other; keep one (D99)" },
        .{ .extras = &.{.{ .path = "general.border_size.width", .value = .{ .integer = 3 } }}, .message = "extra 'general.border_size.width' and setting 'general.border_size' write the same key, or one inside the other; keep one (D99)" },
        .{ .extras = &.{.{ .path = "general", .value = .{ .table = &.{} } }}, .message = "extra 'general' and setting 'general.border_size' write the same key, or one inside the other; keep one (D99)" },
        .{ .extras = &.{ .{ .path = "plugin.a", .value = .{ .integer = 1 } }, .{ .path = "plugin.\"a\".b", .value = .{ .integer = 2 } } }, .message = "extra 'plugin.\"a\".b' and extra 'plugin.a' write the same key, or one inside the other; keep one (D99)" },
        .{ .extras = &.{.{ .path = "*.border_size", .value = .{ .integer = 1 } }}, .rules = .{ .any_key = true }, .message = "extra '*.border_size' and setting 'general.border_size' write the same key, or one inside the other; keep one (D99)" },
        .{ .extras = &.{.{ .path = "map", .value = .{ .string = "x" } }}, .message = "extra 'map' and setting 'map' write the same key, or one inside the other; keep one (D99)" },
        .{ .extras = &.{.{ .path = "plugin.*.length", .value = .{ .integer = 1 } }}, .message = "extra 'plugin.*.length': '*' matches keys only in files kosm edits, not in one it generates" },
        .{ .extras = &.{.{ .path = "plugin..length", .value = .{ .integer = 1 } }}, .message = "extra 'plugin..length', column 8: a segment is empty (two dots, or a dot at an end)" },
        .{ .extras = &.{.{ .path = "font.size", .value = .{ .integer = 1 } }}, .rules = .{ .paths = .one_key }, .message = "extra 'font.size': this file's keys don't nest, so a path is one key" },
        .{ .extras = &.{.{ .path = "", .value = .{ .integer = 1 } }}, .rules = .{ .paths = .whole_name }, .message = "an extra's name is empty" },
    };
    for (cases) |case| {
        var fixture: Fixture = undefined;
        fixture.init();
        defer fixture.deinit();
        try testing.expectError(error.AppFailed, withExtras(&fixture.output, "f", try fixture.own(own_tree), case.extras, case.rules));
        try testing.expectEqualStrings(case.message, fixture.diagnostics.message());
    }
}

test "repeatable keys and flat names never clash with their neighbours" {
    var fixture: Fixture = undefined;
    fixture.init();
    defer fixture.deinit();
    const repeated = try withExtras(&fixture.output, "f", try fixture.own(own_tree), &.{
        .{ .path = "map", .value = .{ .string = "ctrl+b close_tab" } },
        .{ .path = "map", .value = .{ .string = "ctrl+c copy" } },
    }, .{ .paths = .one_key, .repeatable = &.{"map"} });
    try testing.expectEqual(4, repeated.len);

    const prefs: []const Keyed = &.{.{ .path = "zen.theme.gradient", .keys = &.{"zen.theme.gradient"}, .value = .{ .boolean = false } }};
    const flat = try withExtras(&fixture.output, "f", prefs, &.{
        .{ .path = "zen.theme.gradient.show-custom-colors", .value = .{ .boolean = true } },
        .{ .path = "zen.theme", .value = .{ .boolean = true } },
    }, .{ .paths = .whole_name });
    try testing.expectEqualStrings("zen.theme.gradient.show-custom-colors", flat[1].keys[0].?);

    try testing.expectError(error.AppFailed, withExtras(&fixture.output, "f", prefs, &.{
        .{ .path = "zen.theme.gradient", .value = .{ .boolean = true } },
    }, .{ .paths = .whole_name }));
}

test "leaves and tree round trip, extras joining the tables they share" {
    var fixture: Fixture = undefined;
    fixture.init();
    defer fixture.deinit();
    const allocator = fixture.arena.allocator();
    const root: Value = .{ .table = &.{
        .{ .key = "a", .value = .{ .table = &.{.{ .key = "b.c", .value = .{ .integer = 1 } }} } },
        .{ .key = "d", .value = .{ .integer = 2 } },
    } };
    const own = try leaves(allocator, root);
    try testing.expectEqualStrings("a.\"b.c\"", own[0].path);
    const all = try withExtras(&fixture.output, "f", own, &.{.{ .path = "a.e", .value = .{ .integer = 3 } }}, .{});
    const result = try tree(allocator, all);
    try testing.expectEqual(2, result.table.len);
    try testing.expectEqualStrings("b.c", result.table[0].value.table[0].key);
    try testing.expectEqualStrings("e", result.table[0].value.table[1].key);
    try testing.expectEqual(3, result.table[0].value.table[1].value.integer);
    try testing.expectEqualStrings("d", result.table[1].key);
}
