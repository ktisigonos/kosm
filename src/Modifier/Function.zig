//! A modifier's own code: a function changing a color, written in Zig or through a frontend,
//! with the fields it was given. Made by `of`, or by the `modifier` function of a module kosm
//! generates for a modifier written through a frontend; never set by hand.

const Function = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const keep = @import("../keep.zig");
const failure = @import("../failure.zig");

/// The type whose `apply` runs, for messages: "sepia.Modifier".
name: []const u8,
/// Which function of the run it is, in the order `of` made them.
id: usize,

/// A function `of` kept: its `apply` and the kept copy of its fields.
const Entry = struct {
    run: *const fn (fields: *const anyopaque, color: Color) Color,
    fields: *const anyopaque,
};

/// Every function `of` made. A global, because a kosmos takes no allocator and a modifier is
/// plain data a script may hold; it lives as long as the lists `kosm.keep` keeps.
var entries: std.ArrayList(Entry) = .empty;

/// A function running `fields.apply(color)`, with a copy of `fields` kept for the whole run, so
/// later changes to `fields` do not reach it. `T` gives `pub fn apply(self: T, color: kosm.Color)
/// kosm.Color`; its fields are the values the function takes, as a sepia's `amount`.
pub fn of(comptime T: type, fields: T) Function {
    if (!@hasDecl(T, "apply") or @TypeOf(T.apply) != fn (T, Color) Color)
        @compileError("kosm.Modifier.Function.of: " ++ @typeName(T) ++ " needs pub fn apply(self: " ++ @typeName(T) ++ ", color: kosm.Color) kosm.Color");
    const kept = keep.keep(T, &.{fields});
    const Runner = struct {
        fn run(pointer: *const anyopaque, color: Color) Color {
            const self: *const T = @ptrCast(@alignCast(pointer));
            return self.apply(color);
        }
    };
    // A kosmos cannot handle running out of memory; kosm stops with this message instead.
    entries.append(keep.allocator(), .{ .run = Runner.run, .fields = &kept[0] }) catch @panic("kosm.Modifier.Function.of: out of memory");
    return .{ .name = @typeName(T), .id = entries.items.len - 1 };
}

/// Runs the function on `color`. A function no `of` made (its fields set by hand) gives
/// `color` unchanged and records why, which kosm fails with like `kosm.fail`'s message.
pub fn apply(function: Function, color: Color) Color {
    if (function.id >= entries.items.len) {
        failure.record("modifier function '{s}' (id {d}) was not made by kosm.Modifier.Function.of; set a modifier's function only through Function.of or its module's modifier function", .{ function.name, function.id });
        return color;
    }
    const entry = entries.items[function.id];
    return entry.run(entry.fields, color);
}

const testing = std.testing;

const Darken = struct {
    amount: f64 = 0.1,

    pub fn apply(self: Darken, color: Color) Color {
        var darker = color;
        darker.lightness -= self.amount;
        return darker;
    }
};

const Gray = struct {
    pub fn apply(_: Gray, color: Color) Color {
        return .{ .lightness = color.lightness, .chroma = 0, .hue = 0, .alpha = color.alpha };
    }
};

const test_color: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 250 };

test "a function runs its type's apply with the fields it was given, copied" {
    var fields: Darken = .{ .amount = 0.2 };
    const function = of(Darken, fields);
    fields.amount = 0.4;
    try testing.expectApproxEqAbs(0.3, function.apply(test_color).lightness, 1e-12);
    try testing.expectEqualStrings("Modifier.Function.Darken", function.name);
}

test "a type without fields makes a function too" {
    const function = of(Gray, .{});
    try testing.expectEqual(0.0, function.apply(test_color).chroma);
}

test "a function no of made keeps the color and records why" {
    failure.clear();
    defer failure.clear();
    const forged: Function = .{ .name = "sepia.Modifier", .id = std.math.maxInt(usize) };
    try testing.expectEqual(test_color, forged.apply(test_color));
    try testing.expect(std.mem.startsWith(u8, failure.message().?, "modifier function 'sepia.Modifier'"));
}
