//! A color in OKLCH with alpha, stored in f64 so nothing is lost between edits (D48).

const Color = @This();

const std = @import("std");
const parsing = @import("Color/parse.zig");

/// Perceptual lightness: 0 is black, 1 is white. Values outside 0..1 are kept (D48).
lightness: f64,
/// Colorfulness, 0 for grays. Never negative; about 0.37 is the most sRGB can show.
chroma: f64,
/// Hue angle in degrees, 0..360. Meaningless when chroma is 0.
hue: f64,
/// Opacity: 0 is transparent, 1 is opaque.
alpha: f64 = 1,

/// A color in gamma-encoded sRGB.
pub const Rgb = @import("Color/Rgb.zig");
/// A color in HSV (= HSB) over sRGB.
pub const Hsv = @import("Color/Hsv.zig");
/// A color in HSL over sRGB.
pub const Hsl = @import("Color/Hsl.zig");
/// A color in naive CMYK over sRGB.
pub const Cmyk = @import("Color/Cmyk.zig");
/// Formatted color text.
pub const Text = @import("Color/Text.zig");

/// Below this chroma a color counts as gray, and mixing takes the other color's hue.
const gray_chroma = 1e-6;
/// Floats print with at most this many decimals unless a file's format says otherwise.
pub const default_decimals = 6;
/// The most decimals a float component can print with.
pub const max_decimals = 12;
/// Formatted float components are clamped to this magnitude so they always fit in `Text`.
const max_float_magnitude = 1e12;

/// Builds a color from gamma-encoded sRGB channels, nominally 0..1.
pub fn fromRgb(rgb: Rgb) Color {
    const linear: Vector = .{ linearFromGamma(rgb.red), linearFromGamma(rgb.green), linearFromGamma(rgb.blue) };
    const cone = multiply(linear_srgb_to_cone, linear);
    const lab = multiply(cone_to_lab, .{ std.math.cbrt(cone[0]), std.math.cbrt(cone[1]), std.math.cbrt(cone[2]) });
    const lightness = lab[0];
    const green_red = lab[1];
    const blue_yellow = lab[2];

    const chroma = std.math.hypot(green_red, blue_yellow);
    const hue = if (chroma < gray_chroma) 0 else wrapHue(std.math.radiansToDegrees(std.math.atan2(blue_yellow, green_red)));
    return .{ .lightness = lightness, .chroma = chroma, .hue = hue, .alpha = rgb.alpha };
}

/// Converts to gamma-encoded sRGB without clipping, so out-of-gamut channels leave 0..1.
pub fn toRgb(color: Color) Rgb {
    const hue_radians = std.math.degreesToRadians(color.hue);
    const green_red = color.chroma * @cos(hue_radians);
    const blue_yellow = color.chroma * @sin(hue_radians);

    const cone_root = multiply(lab_to_cone, .{ color.lightness, green_red, blue_yellow });
    const linear = multiply(cone_to_linear_srgb, .{ cube(cone_root[0]), cube(cone_root[1]), cube(cone_root[2]) });
    return .{
        .red = gammaFromLinear(linear[0]),
        .green = gammaFromLinear(linear[1]),
        .blue = gammaFromLinear(linear[2]),
        .alpha = color.alpha,
    };
}

/// Errors from parsing hex color text.
pub const ParseHexError = error{InvalidHexColor};

/// Parses `rgb`, `rgba`, `rrggbb` or `rrggbbaa`, with an optional leading `#`.
pub fn parseHex(text: []const u8) ParseHexError!Color {
    const digits = if (std.mem.startsWith(u8, text, "#")) text[1..] else text;
    var channels: [4]u8 = .{ 0, 0, 0, 255 };
    switch (digits.len) {
        3, 4 => for (digits, 0..) |digit, index| {
            const value = try hexDigit(digit);
            channels[index] = value * 16 + value;
        },
        6, 8 => for (0..digits.len / 2) |index| {
            channels[index] = try hexDigit(digits[index * 2]) * 16 + try hexDigit(digits[index * 2 + 1]);
        },
        else => return error.InvalidHexColor,
    }
    return fromRgb(.{
        .red = @as(f64, @floatFromInt(channels[0])) / 255,
        .green = @as(f64, @floatFromInt(channels[1])) / 255,
        .blue = @as(f64, @floatFromInt(channels[2])) / 255,
        .alpha = @as(f64, @floatFromInt(channels[3])) / 255,
    });
}

/// Errors from parsing color text.
pub const ParseError = parsing.Error;

/// Parses any common color text (D55): hex as `parseHex` takes it, `rgb()`, `rgba()`,
/// `hsl()`, `hsla()` or `oklch()`, with commas or spaces and an optional `/ alpha`.
pub fn parse(text: []const u8) ParseError!Color {
    return parsing.parse(text);
}

/// Mixes toward `target` in OKLCH: amount 0 keeps this color, 1 gives `target`.
/// Hue takes the shorter way around the wheel; a gray side takes the other side's hue.
pub fn mix(color: Color, target: Color, amount: f64) Color {
    const color_is_gray = color.chroma < gray_chroma;
    const target_is_gray = target.chroma < gray_chroma;
    const hue = if (color_is_gray and !target_is_gray)
        target.hue
    else if (target_is_gray)
        color.hue
    else
        wrapHue(color.hue + amount * hueDifference(color.hue, target.hue));
    return .{
        .lightness = lerp(color.lightness, target.lightness, amount),
        .chroma = lerp(color.chroma, target.chroma, amount),
        .hue = hue,
        .alpha = lerp(color.alpha, target.alpha, amount),
    };
}

/// WCAG 2 relative luminance, 0..1, from the color clipped to sRGB. Ignores alpha.
pub fn luminance(color: Color) f64 {
    const rgb = color.toRgb();
    return 0.2126 * linearFromGamma(clip(rgb.red)) +
        0.7152 * linearFromGamma(clip(rgb.green)) +
        0.0722 * linearFromGamma(clip(rgb.blue));
}

/// WCAG 2 contrast ratio between two colors, 1..21.
pub fn contrastRatio(color: Color, other: Color) f64 {
    const color_luminance = color.luminance();
    const other_luminance = other.luminance();
    return (@max(color_luminance, other_luminance) + 0.05) / (@min(color_luminance, other_luminance) + 0.05);
}

/// One value a `format` template can print (D47).
pub const Component = enum {
    /// sRGB channel as an integer 0..255, clipped to the gamut.
    red_255,
    green_255,
    blue_255,
    alpha_255,
    /// sRGB channel as a float, nominally 0..1. Not clipped, for apps that accept HDR values.
    red_01,
    green_01,
    blue_01,
    alpha_01,
    /// `rrggbb`, lowercase, clipped to the gamut. No `#`.
    hex,
    /// `rrggbbaa`, lowercase, clipped to the gamut. No `#`.
    hex8,
    /// `RRGGBB`, uppercase, clipped to the gamut. No `#`.
    hex_upper,
    /// `RRGGBBAA`, uppercase, clipped to the gamut. No `#`.
    hex8_upper,
    /// OKLCH lightness as a float, nominally 0..1.
    lightness,
    /// OKLCH chroma as a float.
    chroma,
    /// OKLCH hue in degrees, 0..360.
    hue,
};

/// Space reserved per component; the longest is a float clamped to `max_float_magnitude`.
const component_width = 24;

/// Fills `template`: each `{}` takes the next component, `{{` and `}}` are literal braces (D47).
/// A count mismatch or text that might not fit in `Text` is a compile error.
pub fn format(color: Color, comptime template: []const u8, comptime components: []const Component) Text {
    comptime checkTemplate(template, components.len);
    const rgb = color.toRgb();
    var text: Text = .{};
    var component_index: usize = 0;
    var index: usize = 0;
    while (index < template.len) : (index += 1) {
        const character = template[index];
        if ((character == '{' or character == '}') and index + 1 < template.len and template[index + 1] == character) {
            text.append(template[index..][0..1]);
            index += 1;
        } else if (character == '{') {
            appendComponent(color, rgb, components[component_index], default_decimals, &text);
            component_index += 1;
            index += 1;
        } else {
            text.append(template[index..][0..1]);
        }
    }
    inline for (components) |component| {
        if (clipsRgb(rgb, component)) text.clipped = color;
    }
    return text;
}

/// `#rrggbb`, clipped to the gamut.
pub fn hex(color: Color) Text {
    return color.format("#{}", &.{.hex});
}

/// `#rrggbbaa`, clipped to the gamut.
pub fn hex8(color: Color) Text {
    return color.format("#{}", &.{.hex8});
}

/// Compile error unless `template` has exactly `component_count` placeholders and fits `Text` (D47).
pub fn checkTemplate(comptime template: []const u8, comptime component_count: usize) void {
    var placeholders: usize = 0;
    var literal_bytes: usize = 0;
    var index: usize = 0;
    while (index < template.len) : (index += 1) {
        const character = template[index];
        const doubled = index + 1 < template.len and template[index + 1] == character;
        if ((character == '{' or character == '}') and doubled) {
            literal_bytes += 1;
            index += 1;
        } else if (character == '{') {
            if (!(index + 1 < template.len and template[index + 1] == '}'))
                @compileError("color template: '{' must be followed by '}' or doubled as '{{' in \"" ++ template ++ "\"");
            placeholders += 1;
            index += 1;
        } else if (character == '}') {
            @compileError("color template: a lone '}' must be doubled as '}}' in \"" ++ template ++ "\"");
        } else {
            literal_bytes += 1;
        }
    }
    if (placeholders != component_count)
        @compileError(std.fmt.comptimePrint("color template \"{s}\" has {d} placeholders but {d} components", .{ template, placeholders, component_count }));
    if (literal_bytes + placeholders * component_width > Text.capacity)
        @compileError("color template \"" ++ template ++ "\" is too long for Color.Text");
}

/// One component as text, floats with at most `decimals` decimals (clamped to `max_decimals`).
pub fn formatComponent(color: Color, component: Component, decimals: u8) Text {
    const rgb = color.toRgb();
    var text: Text = .{};
    appendComponent(color, rgb, component, @min(decimals, max_decimals), &text);
    if (clipsRgb(rgb, component)) text.clipped = color;
    return text;
}

/// Whether printing `component` clips this color to the sRGB gamut (D48): a byte component
/// whose channel rounds outside 0..255, so the printed byte differs. Floats never clip.
pub fn clips(color: Color, component: Component) bool {
    return clipsRgb(color.toRgb(), component);
}

fn clipsRgb(rgb: Rgb, component: Component) bool {
    return switch (component) {
        .red_255 => clipsByte(rgb.red),
        .green_255 => clipsByte(rgb.green),
        .blue_255 => clipsByte(rgb.blue),
        .alpha_255 => clipsByte(rgb.alpha),
        .hex, .hex_upper => clipsByte(rgb.red) or clipsByte(rgb.green) or clipsByte(rgb.blue),
        .hex8, .hex8_upper => clipsByte(rgb.red) or clipsByte(rgb.green) or clipsByte(rgb.blue) or clipsByte(rgb.alpha),
        .red_01, .green_01, .blue_01, .alpha_01, .lightness, .chroma, .hue => false,
    };
}

fn clipsByte(channel: f64) bool {
    const byte = @round(channel * 255);
    return byte < 0 or byte > 255;
}

fn appendComponent(color: Color, rgb: Rgb, component: Component, decimals: u8, text: *Text) void {
    switch (component) {
        .red_255 => formatByte(rgb.red, "{d}", text),
        .green_255 => formatByte(rgb.green, "{d}", text),
        .blue_255 => formatByte(rgb.blue, "{d}", text),
        .alpha_255 => formatByte(rgb.alpha, "{d}", text),
        .red_01 => formatFloat(rgb.red, decimals, text),
        .green_01 => formatFloat(rgb.green, decimals, text),
        .blue_01 => formatFloat(rgb.blue, decimals, text),
        .alpha_01 => formatFloat(rgb.alpha, decimals, text),
        .hex, .hex8 => {
            formatByte(rgb.red, "{x:0>2}", text);
            formatByte(rgb.green, "{x:0>2}", text);
            formatByte(rgb.blue, "{x:0>2}", text);
            if (component == .hex8) formatByte(rgb.alpha, "{x:0>2}", text);
        },
        .hex_upper, .hex8_upper => {
            formatByte(rgb.red, "{X:0>2}", text);
            formatByte(rgb.green, "{X:0>2}", text);
            formatByte(rgb.blue, "{X:0>2}", text);
            if (component == .hex8_upper) formatByte(rgb.alpha, "{X:0>2}", text);
        },
        .lightness => formatFloat(color.lightness, decimals, text),
        .chroma => formatFloat(color.chroma, decimals, text),
        .hue => formatFloat(color.hue, decimals, text),
    }
}

fn formatByte(channel: f64, comptime pattern: []const u8, text: *Text) void {
    const byte: u8 = @intFromFloat(@round(clip(channel) * 255));
    // Cannot fail: format reserved component_width bytes per component at compile time.
    const written = std.fmt.bufPrint(text.buffer[text.length..], pattern, .{byte}) catch unreachable;
    text.length += written.len;
}

fn formatFloat(value: f64, decimals: u8, text: *Text) void {
    const finite = if (std.math.isNan(value)) 0 else std.math.clamp(value, -max_float_magnitude, max_float_magnitude);
    // Cannot fail: the value is clamped and decimals are at most max_decimals, so it fits in component_width.
    const written = std.fmt.bufPrint(text.buffer[text.length..], "{d}", .{roundDecimals(finite, decimals)}) catch unreachable;
    text.length += written.len;
}

/// `value` rounded to at most `decimals` decimals, so `{d}` prints no float noise
/// (0.1 + 0.2 prints `0.3`). Values too large to scale, and infinities, are kept; -0 becomes 0.
pub fn roundDecimals(value: f64, decimals: u8) f64 {
    const scale = std.math.pow(f64, 10, @floatFromInt(decimals));
    const scaled = value * scale;
    if (!std.math.isFinite(scaled)) return value;
    const rounded = @round(scaled) / scale;
    return if (rounded == 0) 0 else rounded;
}

const Vector = [3]f64;
const Matrix = [3]Vector;

// Ottosson's published Oklab matrices are rounded to 10 digits. Forcing exact row sums keeps
// white at lightness 1 and grays at chroma 0; computing the inverses keeps round trips exact.
const linear_srgb_to_cone = withRowSums(.{
    .{ 0.4122214708, 0.5363325363, 0.0514459929 },
    .{ 0.2119034982, 0.6806995451, 0.1073969566 },
    .{ 0.0883024619, 0.2817188376, 0.6299787005 },
}, .{ 1, 1, 1 });
const cone_to_lab = withRowSums(.{
    .{ 0.2104542553, 0.7936177850, -0.0040720468 },
    .{ 1.9779984951, -2.4285922050, 0.4505937099 },
    .{ 0.0259040371, 0.7827717662, -0.8086757660 },
}, .{ 1, 0, 0 });
const cone_to_linear_srgb = invert(linear_srgb_to_cone);
const lab_to_cone = invert(cone_to_lab);

fn withRowSums(matrix: Matrix, sums: Vector) Matrix {
    var result = matrix;
    for (&result, sums) |*row, sum| {
        const current = row[0] + row[1] + row[2];
        if (sum == 0) {
            for (row) |*entry| entry.* -= current / 3;
        } else {
            for (row) |*entry| entry.* *= sum / current;
        }
    }
    return result;
}

fn invert(matrix: Matrix) Matrix {
    const m = matrix;
    const cofactors: Matrix = .{
        .{ m[1][1] * m[2][2] - m[1][2] * m[2][1], m[0][2] * m[2][1] - m[0][1] * m[2][2], m[0][1] * m[1][2] - m[0][2] * m[1][1] },
        .{ m[1][2] * m[2][0] - m[1][0] * m[2][2], m[0][0] * m[2][2] - m[0][2] * m[2][0], m[0][2] * m[1][0] - m[0][0] * m[1][2] },
        .{ m[1][0] * m[2][1] - m[1][1] * m[2][0], m[0][1] * m[2][0] - m[0][0] * m[2][1], m[0][0] * m[1][1] - m[0][1] * m[1][0] },
    };
    const determinant = m[0][0] * cofactors[0][0] + m[0][1] * cofactors[1][0] + m[0][2] * cofactors[2][0];
    var result: Matrix = undefined;
    for (&result, cofactors) |*row, cofactor_row| {
        for (row, cofactor_row) |*entry, cofactor| entry.* = cofactor / determinant;
    }
    return result;
}

fn multiply(matrix: Matrix, vector: Vector) Vector {
    var result: Vector = undefined;
    for (&result, matrix) |*entry, row| entry.* = row[0] * vector[0] + row[1] * vector[1] + row[2] * vector[2];
    return result;
}

fn hexDigit(digit: u8) ParseHexError!u8 {
    return std.fmt.charToDigit(digit, 16) catch error.InvalidHexColor;
}

fn linearFromGamma(channel: f64) f64 {
    const magnitude = @abs(channel);
    const linear = if (magnitude <= 0.04045) magnitude / 12.92 else std.math.pow(f64, (magnitude + 0.055) / 1.055, 2.4);
    return std.math.copysign(linear, channel);
}

fn gammaFromLinear(channel: f64) f64 {
    const magnitude = @abs(channel);
    const gamma = if (magnitude <= 0.0031308) magnitude * 12.92 else 1.055 * std.math.pow(f64, magnitude, 1.0 / 2.4) - 0.055;
    return std.math.copysign(gamma, channel);
}

fn cube(value: f64) f64 {
    return value * value * value;
}

fn clip(channel: f64) f64 {
    return std.math.clamp(channel, 0, 1);
}

fn lerp(from: f64, to: f64, amount: f64) f64 {
    return from + (to - from) * amount;
}

/// Wraps any angle into 0..360.
pub fn wrapHue(degrees: f64) f64 {
    const wrapped = @mod(degrees, 360);
    return if (wrapped == 360) 0 else wrapped;
}

/// Signed shortest turn from `from` to `to`, in -180..180 degrees.
fn hueDifference(from: f64, to: f64) f64 {
    const difference = wrapHue(to - from);
    return if (difference > 180) difference - 360 else difference;
}

const testing = std.testing;

fn expectHex(expected: []const u8, color: Color) !void {
    const text = color.hex8();
    try testing.expectEqualStrings(expected, text.slice());
}

test "every 8-bit channel value survives a hex round trip" {
    for (0..256) |value| {
        const digits = std.fmt.hex(@as(u8, @intCast(value)));
        for (0..4) |channel| {
            var buffer: [9]u8 = "#000000ff".*;
            buffer[1 + channel * 2 ..][0..2].* = digits;
            try expectHex(&buffer, try parseHex(&buffer));
        }
    }
}

test "mixed hex colors survive a round trip" {
    const samples = [_][]const u8{ "#102840ff", "#eceff4ff", "#bf616aff", "#ebcb8bff", "#5e81ac80", "#ffffff00", "#000000ff", "#ff0000ff", "#00ff00ff", "#0000ffff" };
    for (samples) |sample| try expectHex(sample, try parseHex(sample));
}

test "known OKLCH values" {
    const red = try parseHex("ff0000");
    try testing.expectApproxEqAbs(0.627955, red.lightness, 1e-4);
    try testing.expectApproxEqAbs(0.257683, red.chroma, 1e-4);
    try testing.expectApproxEqAbs(29.2339, red.hue, 1e-2);

    const white = try parseHex("fff");
    try testing.expectApproxEqAbs(1.0, white.lightness, 1e-12);
    try testing.expectApproxEqAbs(0.0, white.chroma, 1e-12);

    const black = try parseHex("000");
    try testing.expectEqual(0.0, black.lightness);
}

test "parseHex accepts short forms and rejects bad input" {
    try expectHex("#aabbccff", try parseHex("abc"));
    try expectHex("#aabbccdd", try parseHex("#abcd"));
    try testing.expectError(error.InvalidHexColor, parseHex("#12345"));
    try testing.expectError(error.InvalidHexColor, parseHex("ggg"));
    try testing.expectError(error.InvalidHexColor, parseHex(""));
    try testing.expectError(error.InvalidHexColor, parseHex("#"));
}

test "out-of-gamut colors are kept, and clipped only when printed as bytes" {
    const vivid: Color = .{ .lightness = 0.9, .chroma = 0.4, .hue = 140 };
    const rgb = vivid.toRgb();
    try testing.expect(rgb.red < 0 or rgb.green > 1 or rgb.blue < 0);
    const text = vivid.format("{} {}", &.{ .red_255, .green_255 });
    try testing.expectEqualStrings("0 255", text.slice());

    const bright = fromRgb(.{ .red = 2, .green = 2, .blue = 2 });
    const floats = bright.format("{}", &.{.red_01});
    try testing.expectEqualStrings("2", floats.slice());
}

test "a color clips only when a printed byte changes" {
    const just_inside = fromRgb(.{ .red = 255.4 / 255.0, .green = 0.5, .blue = 0.5 });
    const just_outside = fromRgb(.{ .red = 255.6 / 255.0, .green = 0.5, .blue = 0.5 });
    const below = fromRgb(.{ .red = 0.5, .green = 0.5, .blue = -0.6 / 255.0 });
    try testing.expect(!just_inside.clips(.hex));
    try testing.expect(just_outside.clips(.hex));
    try testing.expect(just_outside.clips(.red_255));
    try testing.expect(!just_outside.clips(.green_255));
    try testing.expect(!just_outside.clips(.red_01));
    try testing.expect(below.clips(.blue_255));

    const sheer: Color = .{ .lightness = 0.5, .chroma = 0, .hue = 0, .alpha = 1.5 };
    try testing.expect(!sheer.clips(.hex));
    try testing.expect(sheer.clips(.hex8));
}

test "a round-tripped hex color never clips" {
    for ([_][]const u8{ "#ffffff", "#000000", "#ff0000", "#00ff00", "#0000ff", "#ffff00", "#00ffff" }) |sample| {
        const color = try parseHex(sample);
        try testing.expect(!color.clips(.hex8));
        try testing.expectEqual(null, color.hex().clipped);
    }
}

test "formatted text remembers a clipped color" {
    const vivid: Color = .{ .lightness = 0.9, .chroma = 0.4, .hue = 140 };
    try testing.expectEqual(vivid, vivid.format("rgba({})", &.{.hex8}).clipped.?);
    try testing.expectEqual(null, vivid.format("{}", &.{.lightness}).clipped);
    try testing.expectEqual(vivid, vivid.formatComponent(.green_255, 6).clipped.?);
}

test "format fills components and keeps doubled braces" {
    const color = try parseHex("#5e81ac80");
    const rgba = color.format("rgba({}, {}, {}, {})", &.{ .red_255, .green_255, .blue_255, .alpha_01 });
    try testing.expectEqualStrings("rgba(94, 129, 172, 0.501961)", rgba.slice());
    const braces = color.format("{{{}}}", &.{.hex});
    try testing.expectEqualStrings("{5e81ac}", braces.slice());
    try testing.expectEqualStrings("#5e81ac", color.hex().slice());
}

test "uppercase hex and float components with a chosen precision" {
    const color = try parseHex("#5e81ac80");
    try testing.expectEqualStrings("#5E81AC 5E81AC80", color.format("#{} {}", &.{ .hex_upper, .hex8_upper }).slice());
    try testing.expectEqualStrings("0.5", color.formatComponent(.alpha_01, 2).slice());
    try testing.expectEqualStrings("0.501961", color.formatComponent(.alpha_01, 6).slice());
    try testing.expectEqualStrings("1", color.formatComponent(.alpha_01, 0).slice());
    try testing.expectEqualStrings("0.50196078431", color.formatComponent(.alpha_01, 11).slice());
    try testing.expectEqualStrings("5E81AC", color.formatComponent(.hex_upper, 0).slice());
}

test "roundDecimals trims float noise and keeps what it cannot scale" {
    try testing.expectEqual(0.3, roundDecimals(0.1 + 0.2, 6));
    try testing.expectEqual(6.4, roundDecimals(@as(f32, 6.4), 6));
    try testing.expectEqual(0.0, roundDecimals(-0.0000001, 6));
    try testing.expectEqual(1e300, roundDecimals(1e300, 12));
    try testing.expect(std.math.isInf(roundDecimals(std.math.inf(f64), 2)));
}

test "mix takes the shorter way around the hue wheel" {
    const near_360: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 350 };
    const near_0: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 10 };
    try testing.expectApproxEqAbs(0.0, near_360.mix(near_0, 0.5).hue, 1e-9);
    try testing.expectApproxEqAbs(355.0, near_360.mix(near_0, 0.25).hue, 1e-9);
}

test "mix with a gray keeps the colored side's hue" {
    const gray: Color = .{ .lightness = 0.5, .chroma = 0, .hue = 0 };
    const blue: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 250 };
    try testing.expectEqual(250.0, gray.mix(blue, 0.5).hue);
    try testing.expectEqual(250.0, blue.mix(gray, 0.5).hue);
    try testing.expectApproxEqAbs(0.05, blue.mix(gray, 0.5).chroma, 1e-12);
}

test "contrast ratio of black on white is 21" {
    try testing.expectApproxEqAbs(21.0, (try parseHex("000")).contrastRatio(try parseHex("fff")), 1e-9);
}

test "OKLCH survives a float round trip through sRGB, in and out of gamut" {
    const samples = [_]Color{
        .{ .lightness = 0.5, .chroma = 0.1, .hue = 250 },
        .{ .lightness = 0.9, .chroma = 0.4, .hue = 140 },
        .{ .lightness = 0.2, .chroma = 0.05, .hue = 359.5 },
        .{ .lightness = 1.3, .chroma = 0.02, .hue = 30, .alpha = 0.25 },
    };
    for (samples) |sample| {
        const back = fromRgb(sample.toRgb());
        try testing.expectApproxEqAbs(sample.lightness, back.lightness, 1e-12);
        try testing.expectApproxEqAbs(sample.chroma, back.chroma, 1e-12);
        try testing.expectApproxEqAbs(sample.hue, back.hue, 1e-9);
        try testing.expectEqual(sample.alpha, back.alpha);
    }
}
