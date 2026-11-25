//! `--set path=value`: assigns one field of the tree a kosmos returned, through `kosm.assign`.
//! Values are read as the field's type, like `Params` flags; `null` clears an optional.

const std = @import("std");
const kosm = @import("kosm");

/// Errors from `assign`; on `InvalidAssignment`, `diagnostics` holds the message.
pub const Error = kosm.assignment.Error;

/// Put before every message about a `--set`.
const origin = "--set";

/// Assigns `assignment` (`terminal.kitty.window.opacity=0.9`) inside `tree`, a pointer to the
/// returned tree. Strings in the tree are copied into `arena`.
pub fn assign(arena: std.mem.Allocator, tree: anytype, assignment: []const u8, diagnostics: *kosm.Diagnostics) Error!void {
    const equals = std.mem.findScalar(u8, assignment, '=') orelse
        return fail(diagnostics, "--set '{s}' needs the form path=value", .{assignment});
    if (equals == 0) return fail(diagnostics, "--set '{s}' needs the form path=value", .{assignment});
    const loose = try nested(arena, assignment[0..equals], .{ .value = .{ .text = assignment[equals + 1 ..] } });
    try kosm.assign(@TypeOf(tree.*), arena, tree, loose, diagnostics);
}

/// `leaf` inside one-key tables, one per segment of `path` (`a.b` gives `{ a = { b = leaf } }`).
fn nested(arena: std.mem.Allocator, path: []const u8, leaf: kosm.Loose) std.mem.Allocator.Error!kosm.Loose {
    var current = leaf;
    var segments = std.mem.splitBackwardsScalar(u8, path, '.');
    while (segments.next()) |segment| {
        const entries = try arena.dupe(kosm.Loose.Entry, &.{.{ .key = segment, .value = current }});
        current = .{ .value = .{ .table = entries } };
    }
    current.origin = origin;
    return current;
}

fn fail(diagnostics: *kosm.Diagnostics, comptime format: []const u8, arguments: anytype) Error {
    diagnostics.set("", "", format, arguments);
    return error.InvalidAssignment;
}

const testing = std.testing;

const TestApp = struct {
    opacity: f32 = 1,
    border: ?kosm.Color = null,
    font: ?[]const u8 = "Iosevka",
    blur: struct { enabled: bool = true, size: u16 = 8 } = .{},
    cursor: ?struct { blink: bool = false } = null,
    modifier: kosm.Modifier = .{},
    pointer: *const u8 = &test_byte,

    pub fn apply(self: TestApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

const test_byte: u8 = 0;

const TestTree = struct {
    terminal: struct { kitty: ?TestApp = .{}, foot: ?TestApp = null } = .{},
};

fn expectFailure(assignment: []const u8, expected_message: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectError(error.InvalidAssignment, assign(arena.allocator(), &tree, assignment, &diagnostics));
    try testing.expectEqualStrings(expected_message, diagnostics.message());
}

test "nested fields of every kind take their value" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try assign(arena.allocator(), &tree, "terminal.kitty.opacity=0.5", &diagnostics);
    try assign(arena.allocator(), &tree, "terminal.kitty.blur.size=20", &diagnostics);
    try assign(arena.allocator(), &tree, "terminal.kitty.blur.enabled=false", &diagnostics);
    try assign(arena.allocator(), &tree, "terminal.kitty.border=rgb(255, 0, 0)", &diagnostics);
    try assign(arena.allocator(), &tree, "terminal.kitty.font=Fira Code=Mono", &diagnostics);
    try assign(arena.allocator(), &tree, "terminal.kitty.cursor.blink=true", &diagnostics);
    const kitty = tree.terminal.kitty.?;
    try testing.expectEqual(0.5, kitty.opacity);
    try testing.expectEqual(20, kitty.blur.size);
    try testing.expectEqual(false, kitty.blur.enabled);
    try testing.expectEqualStrings("#ff0000", kitty.border.?.hex().slice());
    try testing.expectEqualStrings("Fira Code=Mono", kitty.font.?);
    try testing.expectEqual(true, kitty.cursor.?.blink);
}

test "null clears an optional, and a whole app" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try assign(arena.allocator(), &tree, "terminal.kitty.font=null", &diagnostics);
    try testing.expectEqual(null, tree.terminal.kitty.?.font);
    try assign(arena.allocator(), &tree, "terminal.kitty=null", &diagnostics);
    try testing.expectEqual(null, tree.terminal.kitty);
}

test "a value for an app that is not chosen is checked, then dropped" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try assign(arena.allocator(), &tree, "terminal.foot.opacity=0.5", &diagnostics);
    try testing.expectEqual(null, tree.terminal.foot);
    try expectFailure("terminal.foot.opacity=dim", "--set: terminal.foot.opacity: expected a number, got 'dim'");
}

test "unknown fields name their parent and suggest the closest, or else list its fields" {
    try expectFailure("termnal.kitty=null", "--set: the kosmos: no field 'termnal'; did you mean 'terminal'?");
    try expectFailure("terminal.kity.opacity=1", "--set: terminal: no field 'kity'; did you mean 'kitty'?");
    try expectFailure("terminal.alacritty.opacity=1", "--set: terminal: no field 'alacritty'; its fields are kitty, foot");
    try expectFailure("terminal.kitty.opacity.alpha=1", "--set: terminal.kitty.opacity: expected a number, got a table");
}

test "bad values, groups and unsupported types are errors" {
    try expectFailure("terminal.kitty.opacity=dim", "--set: terminal.kitty.opacity: expected a number, got 'dim'");
    try expectFailure("terminal.kitty.blur.enabled=yes", "--set: terminal.kitty.blur.enabled: expected true or false, got 'yes'");
    try expectFailure("terminal.kitty.border=sky", "--set: terminal.kitty.border: expected a color (#rrggbb, rgb(...), hsl(...) or oklch(...)), got 'sky'");
    try expectFailure("terminal.kitty.blur=1", "--set: terminal.kitty.blur: expected a table of its fields (enabled, size), got '1'");
    try expectFailure("terminal.kitty.pointer=1", "--set: terminal.kitty.pointer: a *const u8 cannot be set this way");
    try expectFailure("terminal.kitty.opacity", "--set 'terminal.kitty.opacity' needs the form path=value");
    try expectFailure("=1", "--set '=1' needs the form path=value");
}
