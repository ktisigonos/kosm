//! A palette style's own code: a function giving each hue taken from an image its final color,
//! written in Zig or through a frontend, with the fields it was given. Made by `of`, or by the
//! `style` function of a module kosm generates for a style written through a frontend; never
//! set by hand.

const StyleFunction = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const failure = @import("../failure.zig");

/// The type whose `apply` runs, for messages: "pastel.Style".
name: []const u8,
/// Which function of the run it is, in the order `of` made them.
id: usize,

/// Every function `of` made.
const functions = @import("../registry.zig").Registry(fn (fields: *const anyopaque, hue: Color, background: Color) Color);

/// A function running `fields.apply(hue, background)`, with a copy of `fields` kept for the whole
/// run. `T` gives `pub fn apply(self: T, hue: kosm.Color, background: kosm.Color) kosm.Color`,
/// returning the hue's final color; `kosm.Image.readable` keeps it readable on the background.
pub fn of(comptime T: type, fields: T) StyleFunction {
    if (!@hasDecl(T, "apply") or @TypeOf(T.apply) != fn (T, Color, Color) Color)
        @compileError("kosm.Image.Style.Function.of: " ++ @typeName(T) ++ " needs pub fn apply(self: " ++ @typeName(T) ++ ", hue: kosm.Color, background: kosm.Color) kosm.Color");
    const Runner = struct {
        fn run(pointer: *const anyopaque, hue: Color, background: Color) Color {
            const self: *const T = @ptrCast(@alignCast(pointer));
            return self.apply(hue, background);
        }
    };
    return .{ .name = @typeName(T), .id = functions.add(T, Runner.run, fields) };
}

/// Runs the function on `hue`, taken from an image whose theme has `background`. A function no
/// `of` made (its fields set by hand) gives `hue` unchanged and records why, which kosm fails
/// with like `kosm.fail`'s message.
pub fn apply(function: StyleFunction, hue: Color, background: Color) Color {
    const entry = functions.get(function.id) orelse {
        failure.record("palette style '{s}' (id {d}) was not made by kosm.Image.Style.Function.of; set a style's function only through Function.of or its module's style function", .{ function.name, function.id });
        return hue;
    };
    return entry.run(entry.fields, hue, background);
}

const testing = std.testing;

const Toward = struct {
    amount: f64 = 0.5,

    pub fn apply(self: Toward, hue: Color, background: Color) Color {
        return hue.mix(background, self.amount);
    }
};

test "a style function gets the hue and the background, with the fields it was given" {
    const black: Color = .{ .lightness = 0, .chroma = 0, .hue = 0 };
    const hue: Color = .{ .lightness = 0.8, .chroma = 0.1, .hue = 30 };
    try testing.expectApproxEqAbs(0.4, StyleFunction.of(Toward, .{}).apply(hue, black).lightness, 1e-12);
    try testing.expectApproxEqAbs(0.2, StyleFunction.of(Toward, .{ .amount = 0.75 }).apply(hue, black).lightness, 1e-12);
}

test "a style function no of made keeps the hue and records why" {
    failure.clear();
    defer failure.clear();
    const hue: Color = .{ .lightness = 0.8, .chroma = 0.1, .hue = 30 };
    const forged: StyleFunction = .{ .name = "pastel.Style", .id = std.math.maxInt(usize) };
    try testing.expectEqual(hue, forged.apply(hue, hue));
    try testing.expect(std.mem.startsWith(u8, failure.message().?, "palette style 'pastel.Style'"));
}
