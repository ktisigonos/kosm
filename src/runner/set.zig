//! `--set path=value`: assigns one field of the tree a kosmos returned, by reflection (D20).
//! Values parse like `Params` flags (D19, D55); `null` clears an optional.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const params = @import("params.zig");

/// Errors from `assign`; `diagnostics` holds the message.
pub const Error = error{InvalidAssignment};

/// The value that clears an optional field.
const null_text = "null";

/// Assigns `assignment` (`terminal.kitty.window.opacity=0.9`) inside `tree`, a pointer to the
/// returned tree. Strings in the tree point into `assignment` afterwards.
pub fn assign(tree: anytype, assignment: []const u8, diagnostics: *kosm.Diagnostics) Error!void {
    const equals = std.mem.findScalar(u8, assignment, '=') orelse
        return fail(diagnostics, "--set '{s}' needs the form path=value", .{assignment});
    if (equals == 0) return fail(diagnostics, "--set '{s}' needs the form path=value", .{assignment});
    const target: Target = .{ .path = assignment[0..equals], .text = assignment[equals + 1 ..], .diagnostics = diagnostics };
    try assignTo(@TypeOf(tree.*), tree, target.path, target);
}

/// One `--set`, split up.
const Target = struct {
    /// `terminal.kitty.window.opacity`
    path: []const u8,
    /// The text after `=`.
    text: []const u8,
    diagnostics: *kosm.Diagnostics,

    /// The part of `path` already walked when `rest` is what is left.
    fn walked(target: Target, rest: []const u8) []const u8 {
        if (rest.len == target.path.len) return "";
        return target.path[0 .. target.path.len - rest.len - 1];
    }
};

/// Walks `rest` (null once the path is used up) down from `field`, a value of type `T`.
fn assignTo(comptime T: type, field: *T, rest: ?[]const u8, target: Target) Error!void {
    @setEvalBranchQuota(discovery.branch_quota);
    const diagnostics = target.diagnostics;
    if (@typeInfo(T) == .optional) {
        const Child = @typeInfo(T).optional.child;
        if (rest == null and std.mem.eql(u8, target.text, null_text)) {
            field.* = null;
            return;
        }
        if (field.*) |*present| return assignTo(Child, present, rest, target);
        if (rest) |remaining| return fail(diagnostics, "--set {s}: '{s}' is null, so it has no field '{s}'", .{
            target.path, target.walked(remaining), firstSegment(remaining),
        });
        if (comptime !params.isParseable(Child))
            return fail(diagnostics, "--set {s}: it is null, so it can only be set to null", .{target.path});
        field.* = try parse(Child, target);
        return;
    }
    if (comptime params.isParseable(T)) {
        if (rest) |remaining| return fail(diagnostics, "--set {s}: '{s}' is {s}, so it has no field '{s}'", .{
            target.path, target.walked(remaining), comptime params.describe(T), firstSegment(remaining),
        });
        field.* = try parse(T, target);
        return;
    }
    if (@typeInfo(T) == .@"struct") {
        const remaining = rest orelse return fail(diagnostics, "--set {s} is a group of fields, not a value; set one of: {s}", .{
            target.path, comptime fieldList(T),
        });
        const segment = firstSegment(remaining);
        const after = if (segment.len == remaining.len) null else remaining[segment.len + 1 ..];
        const fields = @typeInfo(T).@"struct";
        inline for (fields.field_names, fields.field_types, fields.field_attrs) |name, Field, attributes| {
            if (!attributes.@"comptime" and std.mem.eql(u8, name, segment))
                return assignTo(Field, &@field(field.*, name), after, target);
        }
        const parent = target.walked(remaining);
        return fail(diagnostics, "--set {s}: '{s}' is not a field of {s}{s}{s}; its fields are {s}", .{
            target.path,                                segment,
            if (parent.len == 0) "the kosmos" else "'", parent,
            if (parent.len == 0) "" else "'",           comptime fieldList(T),
        });
    }
    return fail(diagnostics, "--set {s}: a {s} cannot be set from the command line", .{ target.path, @typeName(T) });
}

fn parse(comptime T: type, target: Target) Error!T {
    return params.parseValue(T, target.text) catch
        fail(target.diagnostics, "--set {s} '{s}' is not {s}", .{ target.path, target.text, comptime params.describe(T) });
}

fn firstSegment(path: []const u8) []const u8 {
    return path[0 .. std.mem.findScalar(u8, path, '.') orelse path.len];
}

fn fieldList(comptime T: type) []const u8 {
    comptime var list: []const u8 = "";
    inline for (@typeInfo(T).@"struct".field_names, 0..) |name, index| {
        list = list ++ (if (index == 0) "" else ", ") ++ name;
    }
    return list;
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
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try testing.expectError(error.InvalidAssignment, assign(&tree, assignment, &diagnostics));
    try testing.expectEqualStrings(expected_message, diagnostics.message());
}

test "nested fields of every kind take their value" {
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try assign(&tree, "terminal.kitty.opacity=0.5", &diagnostics);
    try assign(&tree, "terminal.kitty.blur.size=20", &diagnostics);
    try assign(&tree, "terminal.kitty.blur.enabled=false", &diagnostics);
    try assign(&tree, "terminal.kitty.border=rgb(255, 0, 0)", &diagnostics);
    try assign(&tree, "terminal.kitty.font=Fira Code=Mono", &diagnostics);
    const kitty = tree.terminal.kitty.?;
    try testing.expectEqual(0.5, kitty.opacity);
    try testing.expectEqual(20, kitty.blur.size);
    try testing.expectEqual(false, kitty.blur.enabled);
    try testing.expectEqualStrings("#ff0000", kitty.border.?.hex().slice());
    try testing.expectEqualStrings("Fira Code=Mono", kitty.font.?);
}

test "null clears an optional, and a whole app" {
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try assign(&tree, "terminal.kitty.font=null", &diagnostics);
    try testing.expectEqual(null, tree.terminal.kitty.?.font);
    try assign(&tree, "terminal.kitty=null", &diagnostics);
    try testing.expectEqual(null, tree.terminal.kitty);
}

test "a null optional takes a value, but a path through it is an error" {
    var tree: TestTree = .{};
    var diagnostics: kosm.Diagnostics = .{};
    try assign(&tree, "terminal.kitty.border=#00ff00", &diagnostics);
    try testing.expectEqualStrings("#00ff00", tree.terminal.kitty.?.border.?.hex().slice());
    try expectFailure("terminal.foot.opacity=1", "--set terminal.foot.opacity: 'terminal.foot' is null, so it has no field 'opacity'");
    try expectFailure("terminal.kitty.cursor.blink=true", "--set terminal.kitty.cursor.blink: 'terminal.kitty.cursor' is null, so it has no field 'blink'");
    try expectFailure("terminal.kitty.cursor=true", "--set terminal.kitty.cursor: it is null, so it can only be set to null");
}

test "unknown fields name their parent and list its fields" {
    try expectFailure("termnal.kitty=null", "--set termnal.kitty: 'termnal' is not a field of the kosmos; its fields are terminal");
    try expectFailure("terminal.kity.opacity=1", "--set terminal.kity.opacity: 'kity' is not a field of 'terminal'; its fields are kitty, foot");
    try expectFailure("terminal.kitty.opacity.alpha=1", "--set terminal.kitty.opacity.alpha: 'terminal.kitty.opacity' is a number, so it has no field 'alpha'");
}

test "bad values, groups and unsupported types are errors" {
    try expectFailure("terminal.kitty.opacity=dim", "--set terminal.kitty.opacity 'dim' is not a number");
    try expectFailure("terminal.kitty.blur.enabled=yes", "--set terminal.kitty.blur.enabled 'yes' is not true or false");
    try expectFailure("terminal.kitty.border=sky", "--set terminal.kitty.border 'sky' is not a color (#rrggbb, rgb(...), hsl(...) or oklch(...))");
    try expectFailure("terminal.kitty.blur=1", "--set terminal.kitty.blur is a group of fields, not a value; set one of: enabled, size");
    try expectFailure("terminal.kitty.pointer=1", "--set terminal.kitty.pointer: a *const u8 cannot be set from the command line");
    try expectFailure("terminal.kitty.opacity", "--set 'terminal.kitty.opacity' needs the form path=value");
    try expectFailure("=1", "--set '=1' needs the form path=value");
}
