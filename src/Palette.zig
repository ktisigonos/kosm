//! The palette a kosmos defines: black, white and any of the 12 wheel hues.

const Palette = @This();

const std = @import("std");
const Color = @import("Color.zig");

/// Background in dark mode, foreground in light mode (by convention).
black: Color,
/// Foreground in dark mode, background in light mode (by convention).
white: Color,
/// Wheel position 0 deg. Null: mixed from the nearest set hues.
red: ?Color = null,
/// Wheel position 30 deg. Null: mixed from the nearest set hues.
orange: ?Color = null,
/// Wheel position 60 deg. Null: mixed from the nearest set hues.
yellow: ?Color = null,
/// Wheel position 90 deg. Null: mixed from the nearest set hues.
lime: ?Color = null,
/// Wheel position 120 deg. Null: mixed from the nearest set hues.
green: ?Color = null,
/// Wheel position 150 deg. Null: mixed from the nearest set hues.
teal: ?Color = null,
/// Wheel position 180 deg. Null: mixed from the nearest set hues.
cyan: ?Color = null,
/// Wheel position 210 deg. Null: mixed from the nearest set hues.
sky: ?Color = null,
/// Wheel position 240 deg. Null: mixed from the nearest set hues.
blue: ?Color = null,
/// Wheel position 270 deg. Null: mixed from the nearest set hues.
purple: ?Color = null,
/// Wheel position 300 deg. Null: mixed from the nearest set hues.
magenta: ?Color = null,
/// Wheel position 330 deg. Null: mixed from the nearest set hues.
pink: ?Color = null,

/// The palette modules see, every hue filled in.
pub const Resolved = @import("Palette/Resolved.zig");

/// The 12 wheel positions in order, 30 deg apart starting at red.
pub const Hue = enum { red, orange, yellow, lime, green, teal, cyan, sky, blue, purple, magenta, pink };

const hue_count = @typeInfo(Hue).@"enum".field_names.len;

/// Fills every missing hue by mixing the nearest set hues on either side, by wheel
/// position. No set hues gives gray everywhere; gray is mix(black, white).
pub fn resolve(palette: Palette) Resolved {
    const gray = palette.black.mix(palette.white, 0.5);
    var wheel: [hue_count]?Color = undefined;
    inline for (&wheel, @typeInfo(Hue).@"enum".field_names) |*slot, name| slot.* = @field(palette, name);

    var resolved: Resolved = .{
        .black = palette.black,
        .white = palette.white,
        .gray = gray,
        .red = undefined,
        .orange = undefined,
        .yellow = undefined,
        .lime = undefined,
        .green = undefined,
        .teal = undefined,
        .cyan = undefined,
        .sky = undefined,
        .blue = undefined,
        .purple = undefined,
        .magenta = undefined,
        .pink = undefined,
    };
    inline for (@typeInfo(Hue).@"enum".field_names, 0..) |name, position| {
        @field(resolved, name) = wheelColor(&wheel, position) orelse gray;
    }
    return resolved;
}

/// The set color at `position`, or a mix of its nearest set neighbours; null if none is set.
fn wheelColor(wheel: *const [hue_count]?Color, position: usize) ?Color {
    if (wheel[position]) |color| return color;
    for (1..hue_count) |previous_distance| {
        const previous = wheel[(position + hue_count - previous_distance) % hue_count] orelse continue;
        for (1..hue_count) |next_distance| {
            const next = wheel[(position + next_distance) % hue_count] orelse continue;
            const amount = @as(f64, @floatFromInt(previous_distance)) / @as(f64, @floatFromInt(previous_distance + next_distance));
            return previous.mix(next, amount);
        }
    }
    return null;
}

const testing = std.testing;
const parseHex = Color.parseHex;

fn expectColor(expected: Color, actual: Color) !void {
    try testing.expectApproxEqAbs(expected.lightness, actual.lightness, 1e-12);
    try testing.expectApproxEqAbs(expected.chroma, actual.chroma, 1e-12);
    try testing.expectApproxEqAbs(expected.hue, actual.hue, 1e-9);
    try testing.expectApproxEqAbs(expected.alpha, actual.alpha, 1e-12);
}

const test_black: Color = .{ .lightness = 0.2, .chroma = 0.02, .hue = 250 };
const test_white: Color = .{ .lightness = 0.95, .chroma = 0.01, .hue = 250 };

test "no set hues makes every hue gray" {
    const resolved = resolve(.{ .black = test_black, .white = test_white });
    try expectColor(test_black.mix(test_white, 0.5), resolved.gray);
    for (std.enums.values(Hue)) |hue| try expectColor(resolved.gray, resolved.get(hue));
}

test "one set hue makes every hue that hue" {
    const teal: Color = .{ .lightness = 0.7, .chroma = 0.1, .hue = 180 };
    const resolved = resolve(.{ .black = test_black, .white = test_white, .teal = teal });
    for (std.enums.values(Hue)) |hue| try expectColor(teal, resolved.get(hue));
}

test "set hues are kept and gaps mix by wheel distance" {
    const red: Color = .{ .lightness = 0.6, .chroma = 0.2, .hue = 25 };
    const green: Color = .{ .lightness = 0.7, .chroma = 0.15, .hue = 145 };
    const resolved = resolve(.{ .black = test_black, .white = test_white, .red = red, .green = green });
    try expectColor(red, resolved.red);
    try expectColor(green, resolved.green);
    try expectColor(red.mix(green, 0.25), resolved.orange);
    try expectColor(red.mix(green, 0.5), resolved.yellow);
    // Going the other way round, red sits 8 steps from green: pink is 7/8 of the way back to red.
    try expectColor(green.mix(red, 7.0 / 8.0), resolved.pink);
}

test "neighbours are found across the wrap at red" {
    const pink: Color = .{ .lightness = 0.7, .chroma = 0.15, .hue = 350 };
    const orange: Color = .{ .lightness = 0.7, .chroma = 0.15, .hue = 50 };
    const resolved = resolve(.{ .black = test_black, .white = test_white, .pink = pink, .orange = orange });
    try expectColor(pink.mix(orange, 0.5), resolved.red);
    try testing.expectApproxEqAbs(20.0, resolved.red.hue, 1e-9);
}

test "mixing follows wheel position, not actual hue" {
    const blue = try parseHex("5e81ac");
    const resolved = resolve(.{ .black = test_black, .white = test_white, .red = blue, .yellow = blue });
    try expectColor(blue, resolved.orange);
}
