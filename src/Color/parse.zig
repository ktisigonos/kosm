//! Color text as people type it on the command line (D55): hex, `rgb()`, `rgba()`, `hsl()`,
//! `hsla()` and `oklch()`, with commas or spaces between values and an optional `/ alpha`.

const std = @import("std");
const Color = @import("../Color.zig");

/// The text is not a color in any accepted form.
pub const Error = error{InvalidColor};

/// CSS maps an `oklch()` chroma of 100% to this chroma.
const full_chroma = 0.4;
const max_values = 4;

/// Parses hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `#` optional) or a color function.
/// `rgb` channels are 0..255 or percentages; `hsl` hue is in degrees, saturation and
/// lightness in percent; `oklch` lightness is 0..1 or a percentage. Alpha is 0..1 or a percentage.
pub fn parse(text: []const u8) Error!Color {
    const trimmed = std.mem.trim(u8, text, " \t");
    const open = std.mem.findScalar(u8, trimmed, '(') orelse
        return Color.parseHex(trimmed) catch error.InvalidColor;
    if (!std.mem.endsWith(u8, trimmed, ")")) return error.InvalidColor;
    const name = std.mem.trim(u8, trimmed[0..open], " \t");

    var values: [max_values]Number = undefined;
    var count: usize = 0;
    var tokens = std.mem.tokenizeAny(u8, trimmed[open + 1 .. trimmed.len - 1], " \t,/");
    while (tokens.next()) |token| {
        if (count == max_values) return error.InvalidColor;
        values[count] = try parseNumber(token);
        count += 1;
    }
    if (count < 3) return error.InvalidColor;
    const alpha = if (count == 4) try fractionFrom(values[3]) else 1;

    if (std.ascii.eqlIgnoreCase(name, "rgb") or std.ascii.eqlIgnoreCase(name, "rgba")) {
        return Color.fromRgb(.{
            .red = try channelFrom(values[0]),
            .green = try channelFrom(values[1]),
            .blue = try channelFrom(values[2]),
            .alpha = alpha,
        });
    }
    if (std.ascii.eqlIgnoreCase(name, "hsl") or std.ascii.eqlIgnoreCase(name, "hsla")) {
        const hsl: Color.Hsl = .{ .hue = try hueFrom(values[0]), .saturation = try percentFrom(values[1]), .lightness = try percentFrom(values[2]), .alpha = alpha };
        return Color.fromRgb(hsl.toRgb());
    }
    if (std.ascii.eqlIgnoreCase(name, "oklch")) {
        return .{ .lightness = try fractionFrom(values[0]), .chroma = try chromaFrom(values[1]), .hue = try hueFrom(values[2]), .alpha = alpha };
    }
    return error.InvalidColor;
}

const Number = struct {
    value: f64,
    unit: enum { none, percent, degrees },
};

fn parseNumber(token: []const u8) Error!Number {
    var digits = token;
    var number: Number = .{ .value = 0, .unit = .none };
    if (std.mem.endsWith(u8, digits, "%")) {
        digits = digits[0 .. digits.len - 1];
        number.unit = .percent;
    } else if (std.mem.endsWith(u8, digits, "deg")) {
        digits = digits[0 .. digits.len - "deg".len];
        number.unit = .degrees;
    }
    number.value = std.fmt.parseFloat(f64, digits) catch return error.InvalidColor;
    if (!std.math.isFinite(number.value)) return error.InvalidColor;
    return number;
}

fn channelFrom(number: Number) Error!f64 {
    return switch (number.unit) {
        .none => number.value / 255,
        .percent => number.value / 100,
        .degrees => error.InvalidColor,
    };
}

/// Alpha and OKLCH lightness: 0..1, or a percentage.
fn fractionFrom(number: Number) Error!f64 {
    return switch (number.unit) {
        .none => number.value,
        .percent => number.value / 100,
        .degrees => error.InvalidColor,
    };
}

/// CSS also takes bare numbers for `hsl` saturation and lightness, read as percentages.
fn percentFrom(number: Number) Error!f64 {
    if (number.unit == .degrees) return error.InvalidColor;
    return number.value / 100;
}

fn hueFrom(number: Number) Error!f64 {
    if (number.unit == .percent) return error.InvalidColor;
    return Color.wrapHue(number.value);
}

fn chromaFrom(number: Number) Error!f64 {
    const chroma = switch (number.unit) {
        .none => number.value,
        .percent => number.value / 100 * full_chroma,
        .degrees => return error.InvalidColor,
    };
    if (chroma < 0) return error.InvalidColor;
    return chroma;
}

const testing = std.testing;

fn expectHex8(expected: []const u8, text: []const u8) !void {
    const color = try parse(text);
    try testing.expectEqualStrings(expected, color.hex8().slice());
}

test "rgb forms with commas, spaces, percentages and alpha" {
    try expectHex8("#5e81acff", "rgb(94, 129, 172)");
    try expectHex8("#5e81acff", "RGB(94 129 172)");
    try expectHex8("#5e81ac80", "rgba(94, 129, 172, 0.5)");
    try expectHex8("#5e81ac80", "rgb(94 129 172 / 50%)");
    try expectHex8("#ff0000ff", "rgb(100%, 0%, 0%)");
}

test "hex text passes through, with or without #" {
    try expectHex8("#5e81acff", "#5e81ac");
    try expectHex8("#5e81acff", " 5e81ac ");
    try expectHex8("#11223344", "1234");
}

test "hsl covers every sector of the hue circle" {
    try expectHex8("#ff0000ff", "hsl(0, 100%, 50%)");
    try expectHex8("#ffff00ff", "hsl(60deg, 100%, 50%)");
    try expectHex8("#008000ff", "hsl(120, 100%, 25.1%)");
    try expectHex8("#00ffffff", "hsl(180 100 50)");
    try expectHex8("#0000ffff", "hsl(240, 100%, 50%)");
    try expectHex8("#ff00ffff", "hsl(300, 100%, 50%)");
    try expectHex8("#ff000080", "hsla(360, 100%, 50%, 0.5)");
    try expectHex8("#808080ff", "hsl(200, 0%, 50.2%)");
}

test "oklch keeps its values as given" {
    const color = try parse("oklch(62.8% 0.2577 29.23deg / 0.25)");
    try testing.expectApproxEqAbs(0.628, color.lightness, 1e-12);
    try testing.expectApproxEqAbs(0.2577, color.chroma, 1e-12);
    try testing.expectApproxEqAbs(29.23, color.hue, 1e-12);
    try testing.expectApproxEqAbs(0.25, color.alpha, 1e-12);
    const percent_chroma = try parse("oklch(0.5, 50%, -30)");
    try testing.expectApproxEqAbs(0.2, percent_chroma.chroma, 1e-12);
    try testing.expectApproxEqAbs(330.0, percent_chroma.hue, 1e-12);
    try expectHex8("#ff0000ff", "oklch(0.627955 0.257683 29.2339)");
}

test "bad color text is rejected" {
    const bad = [_][]const u8{
        "",
        "rgb(1, 2)",
        "rgb(1, 2, 3, 4, 5)",
        "rgb(1, 2, 3",
        "rgb(a, b, c)",
        "rgb(1deg, 2, 3)",
        "hsl(10%, 50%, 50%)",
        "oklch(0.5 -0.1 20)",
        "lab(50 20 30)",
        "rgb(nan, 1, 1)",
        "ggg",
        "#12345",
    };
    for (bad) |text| try testing.expectError(error.InvalidColor, parse(text));
}
