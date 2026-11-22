//! `assign`: puts loose values (a script's tables, `--set`'s text) into a kosmos' typed tree by
//! reflection, and the text reading it shares with `Params` flags.

const std = @import("std");
const Color = @import("Color.zig");
const ColorChoice = @import("color_choice.zig").ColorChoice;
const Diagnostics = @import("Diagnostics.zig");
const Loose = @import("Loose.zig");
const Value = @import("value.zig").Value;
const Raw = @import("Raw.zig");
const app = @import("app.zig");
const Handle = @import("Frontend/Handle.zig");
const Image = @import("Image.zig");
const File = @import("File.zig");
const kosmos = @import("kosmos.zig");

/// Deep copies, so a value copied from a handle owns its lists.
pub const copy = @import("assignment/copy.zig");

/// Values read from text, and how types are described in messages.
pub const text = @import("assignment/text.zig");

/// Errors from `assign`; on `InvalidAssignment`, `diagnostics` says why.
pub const Error = error{ InvalidAssignment, OutOfMemory };

/// The text that clears an optional, as `Loose.text`.
const null_text = "null";

const branch_quota = 100_000;

/// Sets what `loose` names inside `tree`, all or nothing: a table sets the fields it names and
/// keeps the others, a list replaces a whole list, null clears an optional. A table given to an
/// app that is null (not chosen) is checked against the app's fields, then dropped; given to any
/// other null struct, it starts from that struct's defaults. A union takes a tag's name, or a
/// table of one tag and its value. Strings and lists are copied into `arena`. On an error,
/// `tree` is unchanged and the message names the value's origin and path.
pub fn assign(comptime T: type, arena: std.mem.Allocator, tree: *T, loose: Loose, diagnostics: *Diagnostics) Error!void {
    return assignNamed(T, arena, tree, loose, diagnostics, "the kosmos");
}

/// `assign`, with `name` standing for `tree` in messages about it as a whole: "argument 1",
/// "kosm_kitty.App". A handle given for a value of its own type sets a deep copy of it.
pub fn assignNamed(comptime T: type, arena: std.mem.Allocator, tree: *T, loose: Loose, diagnostics: *Diagnostics, name: []const u8) Error!void {
    // Trees are large, so the copy lives in the arena; lists are replaced, never changed in place,
    // so a shallow copy keeps `tree` intact until it is overwritten.
    const working = try arena.create(T);
    working.* = tree.*;
    var walker: Walker = .{ .arena = arena, .diagnostics = diagnostics, .name = name };
    try walker.overlay(T, working, loose);
    tree.* = working.*;
}

/// A `T` built from `loose` alone, starting from the type's defaults, the way a function's
/// argument is: a field without a default must be given. `name` stands for the value in
/// messages about it as a whole: "argument 1".
pub fn build(comptime T: type, arena: std.mem.Allocator, loose: Loose, diagnostics: *Diagnostics, name: []const u8) Error!T {
    const built = try arena.create(T);
    var walker: Walker = .{ .arena = arena, .diagnostics = diagnostics, .name = name };
    try walker.fresh(T, built, loose);
    return built.*;
}

const Walker = struct {
    arena: std.mem.Allocator,
    diagnostics: *Diagnostics,
    /// Field names, tags and `[index]`es leading to the value being set.
    segments: std.ArrayList([]const u8) = .empty,
    /// The origin of the innermost value that has one.
    origin: ?[]const u8 = null,
    /// What messages call the value as a whole.
    name: []const u8,

    /// Sets `target` from `loose`, keeping what `loose` leaves out.
    fn overlay(walker: *Walker, comptime T: type, target: *T, loose: Loose) Error!void {
        @setEvalBranchQuota(branch_quota);
        const outer_origin = walker.enter(loose);
        defer walker.origin = outer_origin;
        if (loose.value == .handle) return walker.fromHandle(T, target, loose);
        if (comptime isLeaf(T) or kosmos.is(T)) return walker.fresh(T, target, loose);
        if (comptime isLoaded(T)) {
            if (pathOf(loose)) |_| return walker.fresh(T, target, loose);
        }
        switch (@typeInfo(T)) {
            .optional => |optional| {
                if (isNull(loose)) {
                    target.* = null;
                    return;
                }
                if (target.*) |*present| return walker.overlay(optional.child, present, loose);
                const value = try walker.arena.create(optional.child);
                try walker.fresh(optional.child, value, loose);
                // An app that is not chosen keeps its values out of the tree, so they apply
                // only once it is chosen; they were still checked above.
                if (comptime !app.is(optional.child)) target.* = value.*;
            },
            .@"struct" => |info| {
                const entries = try walker.table(T, loose);
                for (entries) |entry| {
                    inline for (info.field_names, info.field_types, info.field_attrs) |name, Field, attributes| {
                        if (!attributes.@"comptime" and std.mem.eql(u8, name, entry.key)) {
                            try walker.push(name);
                            defer walker.pop();
                            try walker.overlay(Field, &@field(target.*, name), entry.value);
                            break;
                        }
                    } else return walker.unknownField(T, entry);
                }
            },
            .@"union" => try walker.setUnion(T, target, loose, .overlay),
            .array => |array| {
                const items = try walker.list(T, loose);
                if (items.len != array.len) return walker.expected(T, loose);
                for (items, target, 0..) |item, *slot, index| {
                    try walker.pushIndex(index);
                    defer walker.pop();
                    try walker.overlay(array.child, slot, item);
                }
            },
            else => try walker.fresh(T, target, loose),
        }
    }

    /// Sets `target` from `loose` alone, starting from the type's defaults; `target` may be
    /// undefined.
    fn fresh(walker: *Walker, comptime T: type, target: *T, loose: Loose) Error!void {
        @setEvalBranchQuota(branch_quota);
        const outer_origin = walker.enter(loose);
        defer walker.origin = outer_origin;
        if (loose.value == .handle) return walker.fromHandle(T, target, loose);
        if (comptime kosmos.is(T)) {
            const name = pathOf(loose) orelse return walker.expected(T, loose);
            target.* = .{ .name = try walker.arena.dupe(u8, name) };
            return;
        }
        if (comptime isLoaded(T)) {
            if (pathOf(loose)) |path| {
                target.* = .{ .path = try walker.arena.dupe(u8, path) };
                return;
            }
        }
        if (T == Value) {
            target.* = try walker.toValue(loose);
            return;
        }
        if (comptime text.isParseable(T)) {
            target.* = try walker.scalar(T, loose);
            return;
        }
        switch (@typeInfo(T)) {
            .optional => |optional| {
                if (isNull(loose)) {
                    target.* = null;
                    return;
                }
                const value = try walker.arena.create(optional.child);
                try walker.fresh(optional.child, value, loose);
                target.* = value.*;
            },
            .@"struct" => |info| {
                if (info.is_tuple) return walker.unsupported(T);
                const entries = try walker.table(T, loose);
                for (entries) |entry| {
                    inline for (info.field_names, info.field_attrs) |name, attributes| {
                        if (!attributes.@"comptime" and std.mem.eql(u8, name, entry.key)) break;
                    } else return walker.unknownField(T, entry);
                }
                inline for (info.field_names, info.field_types, info.field_attrs) |name, Field, attributes| {
                    if (attributes.@"comptime") continue;
                    const field = &@field(target.*, name);
                    const default = comptime attributes.defaultValue(Field);
                    if (default) |default_value| field.* = default_value;
                    if (try walker.merged(entries, name)) |given| {
                        try walker.push(name);
                        defer walker.pop();
                        if (default == null) try walker.fresh(Field, field, given) else try walker.overlay(Field, field, given);
                    } else if (default == null) {
                        return walker.fail("missing '{s}', which has no default", .{name});
                    }
                }
            },
            .@"union" => try walker.setUnion(T, target, loose, .fresh),
            .array => |array| {
                const items = try walker.list(T, loose);
                if (items.len != array.len) return walker.expected(T, loose);
                for (items, target, 0..) |item, *slot, index| {
                    try walker.pushIndex(index);
                    defer walker.pop();
                    try walker.fresh(array.child, slot, item);
                }
            },
            .pointer => |pointer| {
                if (pointer.size != .slice or pointer.sentinel_ptr != null) return walker.unsupported(T);
                const items = try walker.list(T, loose);
                const slots = try walker.arena.alloc(pointer.child, items.len);
                for (items, slots, 0..) |item, *slot, index| {
                    try walker.pushIndex(index);
                    defer walker.pop();
                    try walker.fresh(pointer.child, slot, item);
                }
                target.* = slots;
            },
            else => return walker.unsupported(T),
        }
    }

    /// The value `entries` give `key`, or null. A key given several times as tables is one table
    /// of all their entries in order, so a field with no default can be built from parts;
    /// otherwise the last one wins, as `overlay` sets them in order.
    fn merged(walker: *Walker, entries: []const Loose.Entry, key: []const u8) Error!?Loose {
        var found: ?Loose = null;
        var count: usize = 0;
        var all_tables = true;
        for (entries) |entry| {
            if (!std.mem.eql(u8, entry.key, key)) continue;
            if (found == null) found = entry.value;
            count += 1;
            if (entry.value.value != .table) all_tables = false;
        }
        if (count <= 1) return found;
        if (!all_tables) return findLastEntry(entries, key);
        var combined: std.ArrayList(Loose.Entry) = .empty;
        for (entries) |entry| {
            if (!std.mem.eql(u8, entry.key, key)) continue;
            // An inner value without an origin of its own keeps its table's.
            for (entry.value.value.table) |inner| {
                var kept = inner;
                if (kept.value.origin == null) kept.value.origin = entry.value.origin;
                try combined.append(walker.arena, kept);
            }
        }
        return .{ .value = .{ .table = combined.items }, .origin = found.?.origin };
    }

    /// Sets `target` to a deep copy of the value a handle holds, which must be a `T`, or the
    /// value inside an optional `T`.
    fn fromHandle(walker: *Walker, comptime T: type, target: *T, loose: Loose) Error!void {
        const handle = loose.value.handle;
        if (handle.as(T)) |value| {
            target.* = try copy.deep(T, walker.arena, value.*);
            return;
        }
        if (@typeInfo(T) == .optional) {
            const Child = @typeInfo(T).optional.child;
            if (handle.as(Child)) |value| {
                target.* = try copy.deep(Child, walker.arena, value.*);
                return;
            }
        }
        return walker.expected(T, loose);
    }

    const UnionMode = enum { overlay, fresh };

    /// A tag's name for a tag without a value, or a table of one tag and its value; `.overlay`
    /// keeps the value already there when the tag stays the same.
    fn setUnion(walker: *Walker, comptime T: type, target: *T, loose: Loose, mode: UnionMode) Error!void {
        const info = @typeInfo(T).@"union";
        const Tag = info.tag_type orelse return walker.unsupported(T);
        switch (loose.value) {
            .string, .text => |name| {
                inline for (info.field_names, info.field_types) |tag_name, Payload| {
                    if (Payload == void and std.mem.eql(u8, tag_name, name)) {
                        target.* = @unionInit(T, tag_name, {});
                        return;
                    }
                }
                return walker.expected(T, loose);
            },
            .table => |entries| {
                if (entries.len != 1) return walker.expected(T, loose);
                const entry = entries[0];
                inline for (info.field_names, info.field_types) |tag_name, Payload| {
                    if (std.mem.eql(u8, tag_name, entry.key)) {
                        try walker.push(tag_name);
                        defer walker.pop();
                        if (mode == .overlay and std.meta.activeTag(target.*) == @field(Tag, tag_name)) {
                            return walker.overlay(Payload, &@field(target.*, tag_name), entry.value);
                        }
                        const payload = try walker.arena.create(Payload);
                        try walker.fresh(Payload, payload, entry.value);
                        target.* = @unionInit(T, tag_name, payload.*);
                        return;
                    }
                }
                return walker.expected(T, loose);
            },
            else => return walker.expected(T, loose),
        }
    }

    fn scalar(walker: *Walker, comptime T: type, loose: Loose) Error!T {
        switch (loose.value) {
            .text => |given| {
                const parsed = text.parse(T, given) catch return walker.expected(T, loose);
                return if (T == []const u8) try walker.arena.dupe(u8, parsed) else parsed;
            },
            .string => |given| {
                if (T == []const u8) return walker.arena.dupe(u8, given);
                if (T == Color) return Color.parse(given) catch walker.expected(T, loose);
                if (T == ColorChoice) return ColorChoice.parse(given) catch walker.expected(T, loose);
                if (@typeInfo(T) == .@"enum") return std.meta.stringToEnum(T, given) orelse walker.expected(T, loose);
            },
            .integer => |integer| switch (@typeInfo(T)) {
                .int => return std.math.cast(T, integer) orelse walker.expected(T, loose),
                .float => return @floatFromInt(integer),
                else => {},
            },
            .float => |float| switch (@typeInfo(T)) {
                .float => {
                    const narrowed: T = @floatCast(float);
                    if (std.math.isFinite(narrowed)) return narrowed;
                },
                .int => if (isWholeNumber(float)) {
                    return std.math.cast(T, @as(i64, @intFromFloat(float))) orelse walker.expected(T, loose);
                },
                else => {},
            },
            .boolean => |boolean| if (T == bool) return boolean,
            .table, .list, .null, .handle, .function => {},
        }
        return walker.expected(T, loose);
    }

    fn toValue(walker: *Walker, loose: Loose) Error!Value {
        const outer_origin = walker.enter(loose);
        defer walker.origin = outer_origin;
        switch (loose.value) {
            .table => |entries| {
                const converted = try walker.arena.alloc(Value.Entry, entries.len);
                for (entries, converted) |entry, *slot| {
                    try walker.push(entry.key);
                    defer walker.pop();
                    slot.* = .{ .key = try walker.arena.dupe(u8, entry.key), .value = try walker.toValue(entry.value) };
                }
                return .{ .table = converted };
            },
            .list => |items| {
                const converted = try walker.arena.alloc(Value, items.len);
                for (items, converted, 0..) |item, *slot, index| {
                    try walker.pushIndex(index);
                    defer walker.pop();
                    slot.* = try walker.toValue(item);
                }
                return .{ .list = converted };
            },
            .string => |given| return .{ .string = try walker.arena.dupe(u8, given) },
            .integer => |integer| return .{ .integer = integer },
            .float => |float| return .{ .float = float },
            .boolean => |boolean| return .{ .boolean = boolean },
            .handle => |handle| {
                if (handle.as(Color)) |color| return .{ .color = color.* };
                if (handle.as(Raw)) |raw| return .{ .raw = try walker.arena.dupe(u8, raw.text) };
                if (handle.as(Value)) |value| return copy.deep(Value, walker.arena, value.*);
                return walker.expected(Value, loose);
            },
            .text, .null, .function => return walker.expected(Value, loose),
        }
    }

    fn table(walker: *Walker, comptime T: type, loose: Loose) Error![]const Loose.Entry {
        return switch (loose.value) {
            .table => |entries| entries,
            else => walker.expected(T, loose),
        };
    }

    fn list(walker: *Walker, comptime T: type, loose: Loose) Error![]const Loose {
        return switch (loose.value) {
            .list => |items| items,
            else => walker.expected(T, loose),
        };
    }

    /// Takes `loose`'s origin if it has one; returns the origin to restore after it.
    fn enter(walker: *Walker, loose: Loose) ?[]const u8 {
        const outer = walker.origin;
        if (loose.origin) |origin| walker.origin = origin;
        return outer;
    }

    fn push(walker: *Walker, segment: []const u8) Error!void {
        try walker.segments.append(walker.arena, segment);
    }

    fn pushIndex(walker: *Walker, index: usize) Error!void {
        try walker.push(try walker.arena.print("[{d}]", .{index}));
    }

    fn pop(walker: *Walker) void {
        _ = walker.segments.pop();
    }

    fn unknownField(walker: *Walker, comptime T: type, entry: Loose.Entry) Error {
        _ = walker.enter(entry.value);
        return walker.fail("no field '{s}'; its fields are {s}", .{ entry.key, comptime text.fieldList(T) });
    }

    fn unsupported(walker: *Walker, comptime T: type) Error {
        return walker.fail("a {s} cannot be set this way", .{@typeName(T)});
    }

    fn expected(walker: *Walker, comptime T: type, loose: Loose) Error {
        var buffer: [96]u8 = undefined;
        return walker.fail("expected {s}, got {s}", .{ comptime text.describe(T), describeGiven(&buffer, loose) });
    }

    fn fail(walker: *Walker, comptime format: []const u8, arguments: anytype) Error {
        const problem = try walker.arena.print(format, arguments);
        var path: std.Io.Writer.Allocating = .init(walker.arena);
        for (walker.segments.items) |segment| {
            const separator = if (path.written().len == 0 or segment[0] == '[') "" else ".";
            path.writer.print("{s}{s}", .{ separator, segment }) catch return error.OutOfMemory;
        }
        const shown_path = if (path.written().len == 0) walker.name else path.written();
        if (walker.origin) |origin| {
            walker.diagnostics.set("", "", "{s}: {s}: {s}", .{ origin, shown_path, problem });
        } else {
            walker.diagnostics.set("", "", "{s}: {s}", .{ shown_path, problem });
        }
        return error.InvalidAssignment;
    }
};

/// Types kosm loads before the kosmos runs, which a path given as text alone names.
fn isLoaded(comptime T: type) bool {
    return T == Image or T == File;
}

/// The text of a string or `--set`'s text, or null.
fn pathOf(loose: Loose) ?[]const u8 {
    return switch (loose.value) {
        .string, .text => |given| given,
        else => null,
    };
}

/// Types set as one value, never field by field.
fn isLeaf(comptime T: type) bool {
    return T == Value or text.isParseable(T);
}

fn isNull(loose: Loose) bool {
    return switch (loose.value) {
        .null => true,
        .text => |given| std.mem.eql(u8, given, null_text),
        else => false,
    };
}

fn isWholeNumber(float: f64) bool {
    // Beyond 2^63 a float no longer converts to an i64.
    const limit = 9.2e18;
    return float == @trunc(float) and @abs(float) < limit;
}

fn findLastEntry(entries: []const Loose.Entry, key: []const u8) ?Loose {
    var found: ?Loose = null;
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, key)) found = entry.value;
    }
    return found;
}

/// From here on a number given is shown in scientific notation, not as all its digits.
const large_number = 1e15;

/// `a table`, `the string 'x'`, `the number 2.5`: what was given, for "expected ..., got ...".
fn describeGiven(buffer: []u8, loose: Loose) []const u8 {
    return switch (loose.value) {
        .table => "a table",
        .list => |items| std.fmt.bufPrint(buffer, "a list of {d} items", .{items.len}) catch "a list",
        .string => |given| std.fmt.bufPrint(buffer, "the string '{s}'", .{given}) catch "a string",
        .text => |given| std.fmt.bufPrint(buffer, "'{s}'", .{given}) catch "text",
        .integer => |integer| std.fmt.bufPrint(buffer, "the integer {d}", .{integer}) catch "an integer",
        .float => |float| (if (@abs(float) < large_number)
            std.fmt.bufPrint(buffer, "the number {d}", .{float})
        else
            std.fmt.bufPrint(buffer, "the number {e}", .{float})) catch "a number",
        .boolean => |boolean| if (boolean) "true" else "false",
        .null => "null",
        .handle => |handle| std.fmt.bufPrint(buffer, "a {s}", .{handle.type.name}) catch "a Zig value",
        .function => "a function",
    };
}

const testing = std.testing;
const Output = @import("Output.zig");

const Style = union(enum) { disabled, bold, size: u16, font: struct { family: []const u8, weight: u16 = 400 } };

const Layout = struct {
    layout: []const u8,
    variant: ?[]const u8 = null,
};

const TestApp = struct {
    opacity: f32 = 1,
    size: u8 = 8,
    border: ?Color = null,
    accent: ColorChoice = .{ .hue = .cyan },
    mode: enum { dark, light } = .dark,
    font: ?[]const u8 = "Iosevka",
    blur: struct { enabled: bool = true, passes: u16 = 2 } = .{},
    cursor: ?struct { blink: bool = false, rate: u16 = 500 } = null,
    style: Style = .bold,
    layouts: []const Layout = &.{},
    corners: [2]u8 = .{ 4, 4 },
    extra: []const struct { path: []const u8, value: Value } = &.{},
    pointer: *const u8 = &test_byte,

    pub fn apply(self: TestApp, output: *Output) !void {
        _ = self;
        _ = output;
    }
};

const test_byte: u8 = 0;

const TestTree = struct {
    terminal: struct { kitty: ?TestApp = .{}, foot: ?TestApp = null } = .{},
};

fn looseOf(kind: Loose.Kind) Loose {
    return .{ .value = kind };
}

fn entryOf(key: []const u8, kind: Loose.Kind) Loose.Entry {
    return .{ .key = key, .value = looseOf(kind) };
}

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    tree: TestTree = .{},
    diagnostics: Diagnostics = .{},

    fn init() Fixture {
        return .{ .arena = .init(testing.allocator) };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.arena.deinit();
    }

    fn assignLoose(fixture: *Fixture, value: Loose) Error!void {
        return assign(TestTree, fixture.arena.allocator(), &fixture.tree, value, &fixture.diagnostics);
    }

    fn expectFailure(fixture: *Fixture, value: Loose, expected_message: []const u8) !void {
        const before = fixture.tree;
        try testing.expectError(error.InvalidAssignment, fixture.assignLoose(value));
        try testing.expectEqualStrings(expected_message, fixture.diagnostics.message());
        try testing.expectEqualDeep(before, fixture.tree);
    }

    /// A table setting `terminal.kitty.<key>` to `kind`, in the fixture's arena.
    fn kitty(fixture: *Fixture, key: []const u8, kind: Loose.Kind) Loose {
        var current = looseOf(kind);
        for ([_][]const u8{ key, "kitty", "terminal" }) |name| {
            const entries = fixture.arena.allocator().dupe(Loose.Entry, &.{.{ .key = name, .value = current }}) catch @panic("out of memory in a test");
            current = looseOf(.{ .table = entries });
        }
        return current;
    }

    fn kittyApp(fixture: *Fixture) TestApp {
        return fixture.tree.terminal.kitty.?;
    }
};

test "typed values of every kind take their place, and the rest keep theirs" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.assignLoose(fixture.kitty("opacity", .{ .float = 0.5 }));
    try fixture.assignLoose(fixture.kitty("size", .{ .integer = 12 }));
    try fixture.assignLoose(fixture.kitty("border", .{ .string = "#ff0000" }));
    try fixture.assignLoose(fixture.kitty("accent", .{ .string = "sky" }));
    try fixture.assignLoose(fixture.kitty("mode", .{ .string = "light" }));
    try fixture.assignLoose(fixture.kitty("font", .{ .string = "Fira Code" }));
    try fixture.assignLoose(fixture.kitty("blur", .{ .table = &.{entryOf("passes", .{ .integer = 4 })} }));
    const app_values = fixture.kittyApp();
    try testing.expectEqual(0.5, app_values.opacity);
    try testing.expectEqual(12, app_values.size);
    try testing.expectEqualStrings("#ff0000", app_values.border.?.hex().slice());
    try testing.expectEqual(.sky, app_values.accent.hue);
    try testing.expectEqual(.light, app_values.mode);
    try testing.expectEqualStrings("Fira Code", app_values.font.?);
    try testing.expectEqual(4, app_values.blur.passes);
    try testing.expectEqual(true, app_values.blur.enabled);
}

test "text is read as the field's type, and null text clears an optional" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.assignLoose(fixture.kitty("opacity", .{ .text = "0.25" }));
    try fixture.assignLoose(fixture.kitty("border", .{ .text = "rgb(0, 255, 0)" }));
    try fixture.assignLoose(fixture.kitty("style", .{ .text = "disabled" }));
    try testing.expectEqual(0.25, fixture.kittyApp().opacity);
    try testing.expectEqualStrings("#00ff00", fixture.kittyApp().border.?.hex().slice());
    try testing.expectEqual(.disabled, std.meta.activeTag(fixture.kittyApp().style));
    try fixture.assignLoose(fixture.kitty("font", .{ .text = "null" }));
    try testing.expectEqual(null, fixture.kittyApp().font);
}

test "numbers convert between integer and float fields only when exact" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.assignLoose(fixture.kitty("opacity", .{ .integer = 1 }));
    try fixture.assignLoose(fixture.kitty("size", .{ .float = 16.0 }));
    try testing.expectEqual(1, fixture.kittyApp().opacity);
    try testing.expectEqual(16, fixture.kittyApp().size);
    try fixture.expectFailure(fixture.kitty("size", .{ .float = 2.5 }), "terminal.kitty.size: expected an integer that fits u8, got the number 2.5");
    try fixture.expectFailure(fixture.kitty("size", .{ .integer = 256 }), "terminal.kitty.size: expected an integer that fits u8, got the integer 256");
    try fixture.expectFailure(fixture.kitty("size", .{ .integer = -1 }), "terminal.kitty.size: expected an integer that fits u8, got the integer -1");
    try fixture.expectFailure(fixture.kitty("opacity", .{ .float = 1e300 }), "terminal.kitty.opacity: expected a number, got the number 1e300");
}

test "null clears optionals, and a whole app" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.assignLoose(fixture.kitty("border", .{ .string = "#ffffff" }));
    try fixture.assignLoose(fixture.kitty("border", .null));
    try testing.expectEqual(null, fixture.kittyApp().border);
    try fixture.assignLoose(looseOf(.{ .table = &.{entryOf("terminal", .{ .table = &.{entryOf("kitty", .null)} })} }));
    try testing.expectEqual(null, fixture.tree.terminal.kitty);
}

test "an app that is not chosen checks its values, then drops them" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const foot = looseOf(.{ .table = &.{entryOf("terminal", .{ .table = &.{entryOf("foot", .{ .table = &.{entryOf("opacity", .{ .float = 0.5 })} })} })} });
    try fixture.assignLoose(foot);
    try testing.expectEqual(null, fixture.tree.terminal.foot);
    const typo = looseOf(.{ .table = &.{entryOf("terminal", .{ .table = &.{entryOf("foot", .{ .table = &.{entryOf("opacty", .{ .float = 0.5 })} })} })} });
    try fixture.expectFailure(typo, "terminal.foot: no field 'opacty'; its fields are opacity, size, border, accent, mode, font, blur, cursor, style, layouts, corners, extra, pointer");
}

test "a null group of settings starts from its defaults" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.assignLoose(fixture.kitty("cursor", .{ .table = &.{entryOf("blink", .{ .boolean = true })} }));
    try testing.expectEqual(true, fixture.kittyApp().cursor.?.blink);
    try testing.expectEqual(500, fixture.kittyApp().cursor.?.rate);
}

test "a union takes a tag's name or a table of one tag, keeping its value when the tag stays" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.assignLoose(fixture.kitty("style", .{ .string = "disabled" }));
    try testing.expectEqual(.disabled, std.meta.activeTag(fixture.kittyApp().style));
    try fixture.assignLoose(fixture.kitty("style", .{ .table = &.{entryOf("font", .{ .table = &.{entryOf("family", .{ .string = "Iosevka" })} })} }));
    try testing.expectEqualStrings("Iosevka", fixture.kittyApp().style.font.family);
    try testing.expectEqual(400, fixture.kittyApp().style.font.weight);
    try fixture.assignLoose(fixture.kitty("style", .{ .table = &.{entryOf("font", .{ .table = &.{entryOf("weight", .{ .integer = 700 })} })} }));
    try testing.expectEqualStrings("Iosevka", fixture.kittyApp().style.font.family);
    try testing.expectEqual(700, fixture.kittyApp().style.font.weight);
    const union_message = "terminal.kitty.style: expected one of disabled, bold, or a table holding one of size, font, got ";
    try fixture.expectFailure(fixture.kitty("style", .{ .string = "size" }), union_message ++ "the string 'size'");
    try fixture.expectFailure(fixture.kitty("style", .{ .table = &.{ entryOf("size", .{ .integer = 1 }), entryOf("bold", .null) } }), union_message ++ "a table");
    try fixture.assignLoose(fixture.kitty("style", .{ .string = "bold" }));
    try fixture.expectFailure(fixture.kitty("style", .{ .table = &.{entryOf("font", .{ .table = &.{entryOf("weight", .{ .integer = 700 })} })} }), "terminal.kitty.style.font: missing 'family', which has no default");
}

test "lists replace the whole list, and each item needs the fields without defaults" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const layouts: []const Loose = &.{
        looseOf(.{ .table = &.{entryOf("layout", .{ .string = "us" })} }),
        looseOf(.{ .table = &.{ entryOf("layout", .{ .string = "rs" }), entryOf("variant", .{ .string = "latin" }) } }),
    };
    try fixture.assignLoose(fixture.kitty("layouts", .{ .list = layouts }));
    try testing.expectEqual(2, fixture.kittyApp().layouts.len);
    try testing.expectEqualStrings("us", fixture.kittyApp().layouts[0].layout);
    try testing.expectEqual(null, fixture.kittyApp().layouts[0].variant);
    try testing.expectEqualStrings("latin", fixture.kittyApp().layouts[1].variant.?);
    try fixture.assignLoose(fixture.kitty("corners", .{ .list = &.{ looseOf(.{ .integer = 1 }), looseOf(.{ .integer = 2 }) } }));
    try testing.expectEqual([2]u8{ 1, 2 }, fixture.kittyApp().corners);
    const missing: []const Loose = &.{ layouts[0], looseOf(.{ .table = &.{entryOf("variant", .{ .string = "latin" })} }) };
    try fixture.expectFailure(fixture.kitty("layouts", .{ .list = missing }), "terminal.kitty.layouts[1]: missing 'layout', which has no default");
    try fixture.expectFailure(fixture.kitty("corners", .{ .list = &.{looseOf(.{ .integer = 1 })} }), "terminal.kitty.corners: expected a list of 2 items, got a list of 1 items");
    try fixture.expectFailure(fixture.kitty("layouts", .{ .string = "us" }), "terminal.kitty.layouts: expected a list, got the string 'us'");
}

test "a key given twice as tables builds a field without a default from both, other values keep the last" {
    const Pair = struct { first: u8, second: u8 };
    const Holder = struct { pair: Pair, name: []const u8 };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostics: Diagnostics = .{};
    var holder: ?Holder = null;
    const given = looseOf(.{ .table = &.{
        entryOf("pair", .{ .table = &.{entryOf("first", .{ .integer = 1 })} }),
        entryOf("name", .{ .string = "a" }),
        entryOf("pair", .{ .table = &.{entryOf("second", .{ .integer = 2 })} }),
        entryOf("name", .{ .string = "b" }),
    } });
    try assign(?Holder, arena.allocator(), &holder, given, &diagnostics);
    try testing.expectEqual(1, holder.?.pair.first);
    try testing.expectEqual(2, holder.?.pair.second);
    try testing.expectEqualStrings("b", holder.?.name);
}

test "a kosm.Value takes any value but text and null" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const extra = looseOf(.{ .table = &.{ entryOf("path", .{ .string = "a.b" }), entryOf("value", .{ .list = &.{ looseOf(.{ .integer = 1 }), looseOf(.{ .string = "two" }) } }) } });
    try fixture.assignLoose(fixture.kitty("extra", .{ .list = &.{extra} }));
    const written = fixture.kittyApp().extra[0].value.list;
    try testing.expectEqual(1, written[0].integer);
    try testing.expectEqualStrings("two", written[1].string);
    const bad = looseOf(.{ .table = &.{ entryOf("path", .{ .string = "a" }), entryOf("value", .null) } });
    try fixture.expectFailure(fixture.kitty("extra", .{ .list = &.{bad} }), "terminal.kitty.extra[0].value: expected a value to write (a table, list, string, number or boolean), got null");
}

test "a kosm.Value takes a color or raw text a script holds" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    var color = try Color.parseHex("ff0000");
    var raw: Raw = .{ .text = "2pt" };
    const color_handle: Handle = .{ .pointer = &color, .type = &.{ .id = Handle.id(Color), .name = "kosm.Color", .get = undefined, .set = undefined, .length = undefined } };
    const raw_handle: Handle = .{ .pointer = &raw, .type = &.{ .id = Handle.id(Raw), .name = "kosm.Raw", .get = undefined, .set = undefined, .length = undefined } };
    const extra = looseOf(.{ .table = &.{ entryOf("path", .{ .string = "a" }), entryOf("value", .{ .list = &.{ looseOf(.{ .handle = color_handle }), looseOf(.{ .handle = raw_handle }) } }) } });
    try fixture.assignLoose(fixture.kitty("extra", .{ .list = &.{extra} }));
    const written = fixture.kittyApp().extra[0].value.list;
    try testing.expectEqual(color, written[0].color);
    try testing.expectEqualStrings("2pt", written[1].raw);
}

test "wrong kinds of values name the path and what was expected" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.expectFailure(fixture.kitty("opacity", .{ .string = "0.5" }), "terminal.kitty.opacity: expected a number, got the string '0.5'");
    try fixture.expectFailure(fixture.kitty("opacity", .{ .text = "dim" }), "terminal.kitty.opacity: expected a number, got 'dim'");
    try fixture.expectFailure(fixture.kitty("opacity", .null), "terminal.kitty.opacity: expected a number, got null");
    try fixture.expectFailure(fixture.kitty("border", .{ .string = "sky" }), "terminal.kitty.border: expected a color (#rrggbb, rgb(...), hsl(...) or oklch(...)), got the string 'sky'");
    try fixture.expectFailure(fixture.kitty("mode", .{ .string = "dim" }), "terminal.kitty.mode: expected one of dark, light, got the string 'dim'");
    try fixture.expectFailure(fixture.kitty("blur", .{ .boolean = false }), "terminal.kitty.blur: expected a table of its fields (enabled, passes), got false");
    try fixture.expectFailure(fixture.kitty("pointer", .{ .integer = 1 }), "terminal.kitty.pointer: a *const u8 cannot be set this way");
    try fixture.expectFailure(looseOf(.{ .integer = 1 }), "the kosmos: expected a table of its fields (terminal), got the integer 1");
}

test "unknown fields name their parent's path and list its fields" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    try fixture.expectFailure(looseOf(.{ .table = &.{entryOf("termnal", .null)} }), "the kosmos: no field 'termnal'; its fields are terminal");
    try fixture.expectFailure(looseOf(.{ .table = &.{entryOf("terminal", .{ .table = &.{entryOf("kity", .null)} })} }), "terminal: no field 'kity'; its fields are kitty, foot");
}

test "messages start with the innermost origin" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const blur: Loose = .{ .value = .{ .table = &.{.{ .key = "passes", .value = .{ .value = .{ .string = "many" }, .origin = "personal.lua:9" } }} }, .origin = "personal.lua:8" };
    const tree: Loose = .{ .value = .{ .table = &.{entryOf("terminal", .{ .table = &.{entryOf("kitty", .{ .table = &.{.{ .key = "blur", .value = blur }} })} })} }, .origin = "personal.lua" };
    try fixture.expectFailure(tree, "personal.lua:9: terminal.kitty.blur.passes: expected an integer that fits u16, got the string 'many'");
    const unknown: Loose = .{ .value = .{ .table = &.{entryOf("terminal", .{ .table = &.{.{ .key = "foo", .value = .{ .value = .null, .origin = "personal.lua:3" } }} })} }, .origin = "personal.lua" };
    try fixture.expectFailure(unknown, "personal.lua:3: terminal: no field 'foo'; its fields are kitty, foot");
}

test "a failure half way leaves the whole tree as it was" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const both = looseOf(.{ .table = &.{entryOf("terminal", .{ .table = &.{entryOf("kitty", .{ .table = &.{
        entryOf("opacity", .{ .float = 0.5 }),
        entryOf("blur", .{ .table = &.{ entryOf("passes", .{ .integer = 9 }), entryOf("enabled", .{ .string = "no" }) } }),
    } })} })} });
    try fixture.expectFailure(both, "terminal.kitty.blur.enabled: expected true or false, got the string 'no'");
    try testing.expectEqual(1, fixture.kittyApp().opacity);
    try testing.expectEqual(2, fixture.kittyApp().blur.passes);
}

test "strings are copied, so they outlive the script's buffers" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    var buffer = "Iosevka".*;
    try fixture.assignLoose(fixture.kitty("font", .{ .string = &buffer }));
    buffer[0] = 'X';
    try testing.expectEqualStrings("Iosevka", fixture.kittyApp().font.?);
}

/// A handle's table for tests that only check its type.
fn testHandleType(comptime T: type, name: []const u8) Handle.Type {
    const Stub = struct {
        fn get(call: *@import("Frontend/Call.zig"), pointer: *anyopaque, key: Handle.Key) @import("Frontend/Call.zig").Error!Loose {
            _ = .{ pointer, key };
            return call.fail("not in tests", .{});
        }
        fn set(call: *@import("Frontend/Call.zig"), pointer: *anyopaque, key: Handle.Key, value: Loose) @import("Frontend/Call.zig").Error!void {
            _ = .{ pointer, key, value };
            return call.fail("not in tests", .{});
        }
        fn length(pointer: *anyopaque) usize {
            _ = pointer;
            return 0;
        }
    };
    return .{ .id = Handle.id(T), .name = name, .get = Stub.get, .set = Stub.set, .length = Stub.length };
}

test "a handle sets a deep copy of its value into a field of its type, optional or not" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const layout_type = testHandleType(Layout, "Layout");
    var variant = "latin".*;
    var layout: Layout = .{ .layout = "rs", .variant = &variant };
    const handle: Handle = .{ .pointer = &layout, .type = &layout_type };
    try fixture.assignLoose(fixture.kitty("layouts", .{ .list = &.{looseOf(.{ .handle = handle })} }));
    layout.layout = "us";
    try testing.expectEqualStrings("rs", fixture.kittyApp().layouts[0].layout);

    const color_type = testHandleType(Color, "kosm.Color");
    var color = try Color.parse("#ff0000");
    try fixture.assignLoose(fixture.kitty("border", .{ .handle = .{ .pointer = &color, .type = &color_type } }));
    try testing.expectEqualStrings("#ff0000", fixture.kittyApp().border.?.hex().slice());
    try fixture.expectFailure(fixture.kitty("font", .{ .handle = handle }), "terminal.kitty.font: expected text or null, got a Layout");
}

test "an image or file is named by its path alone, or set field by field" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const Params = struct { wallpaper: Image = .{ .path = "default.png" }, notes: ?File = null };
    var params: Params = .{};
    try assign(Params, fixture.arena.allocator(), &params, looseOf(.{ .table = &.{ entryOf("wallpaper", .{ .string = "dune.png" }), entryOf("notes", .{ .text = "notes.txt" }) } }), &fixture.diagnostics);
    try testing.expectEqualStrings("dune.png", params.wallpaper.path);
    try testing.expectEqualStrings("notes.txt", params.notes.?.path);
    try assign(Params, fixture.arena.allocator(), &params, looseOf(.{ .table = &.{entryOf("wallpaper", .{ .table = &.{entryOf("path", .{ .string = "sea.png" })} })} }), &fixture.diagnostics);
    try testing.expectEqualStrings("sea.png", params.wallpaper.path);
}

test "a kosmos to build on is named by its name alone" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const Tree = struct { size: u32 = 0 };
    const Params = struct { on: kosmos.Kosmos(Tree) = .{ .name = "personal" }, also: ?kosmos.Kosmos(Tree) = null };
    var params: Params = .{};
    try assign(Params, fixture.arena.allocator(), &params, looseOf(.{ .table = &.{ entryOf("on", .{ .string = "personal.nord" }), entryOf("also", .{ .text = "frost" }) } }), &fixture.diagnostics);
    try testing.expectEqualStrings("personal.nord", params.on.name);
    try testing.expectEqualStrings("frost", params.also.?.name);
    try testing.expectEqual(null, params.on.built);
    try testing.expectError(error.InvalidAssignment, assign(Params, fixture.arena.allocator(), &params, looseOf(.{ .table = &.{entryOf("on", .{ .table = &.{entryOf("name", .{ .string = "x" })} })} }), &fixture.diagnostics));
    try testing.expect(std.mem.endsWith(u8, fixture.diagnostics.message(), "on: expected the name of a kosmos giving a assignment.test.a kosmos to build on is named by its name alone.Tree, got a table"));
}

test "build starts from the type's defaults and names the value as a whole" {
    var fixture: Fixture = .init();
    defer fixture.deinit();
    const built = try build(Layout, fixture.arena.allocator(), looseOf(.{ .table = &.{entryOf("layout", .{ .string = "us" })} }), &fixture.diagnostics, "argument 1");
    try testing.expectEqualStrings("us", built.layout);
    try testing.expectEqual(null, built.variant);
    try testing.expectError(error.InvalidAssignment, build(Layout, fixture.arena.allocator(), looseOf(.{ .integer = 3 }), &fixture.diagnostics, "argument 1"));
    try testing.expectEqualStrings("argument 1: expected a table of its fields (layout, variant), got the integer 3", fixture.diagnostics.message());
}
