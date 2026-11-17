//! An image a kosmos takes its colors from, like a wallpaper: name it in the kosmos' `Params`
//! and kosm loads its pixels before calling the kosmos, which then takes a palette or a whole
//! theme input from it.

const Image = @This();

const std = @import("std");
const Color = @import("Color.zig");
const Palette = @import("Palette.zig");
const Theme = @import("Theme.zig");
const Analysis = @import("Image/Analysis.zig");

/// Where the image is: an absolute path, or one starting with `~/` for the home directory. A
/// folder stands for a random picture in it or its subfolders, picked anew on every apply; kosm
/// then sets this to that picture's path, so the wallpaper can follow it.
path: []const u8,
/// The image's pixels, shrunk. Kosm fills them in for every image in a kosmos' `Params`
/// before calling it; an image built anywhere else has none, and taking colors from it fails.
pixels: []const Color = &.{},

/// How colors are taken from the image: the style, the mode, how the accent is picked, and the
/// thresholds, each with a default.
pub const Options = @import("Image/Options.zig");
/// How colors are taken from the image: readable (the default), literal, vivid or muted.
pub const Style = Options.Style;
/// How the image's hues score for the accent and secondary roles.
pub const AccentBy = Options.AccentBy;
/// What the hues the image lacks become: left to mixing, made up for the roles, or all made up.
pub const Fill = Options.Fill;
/// The lightness and chroma made-up hues get: their neighbours' or the image's average.
pub const Tone = Options.Tone;

pub const Error = error{
    /// The image has no pixels: kosm loads only the images a kosmos names in its `Params`.
    ImageNotLoaded,
};

const hue_count = @typeInfo(Palette.Hue).@"enum".field_names.len;

/// Steps of the searches for a lightness or chroma; each halves the error, so 32 is far
/// below what a printed color shows.
const search_steps = 32;

/// The image's palette: black and white from its darkest and lightest colors, and each wheel
/// hue from the image's most common color near it. The hues the image barely has follow
/// `Options.fill`.
pub fn palette(image: Image, options: Options) Error!Palette {
    const analysis = try image.analyse(options);
    return paletteFrom(analysis, options, modeOf(analysis, options));
}

/// What `Theme.from` takes: the image's palette, its mode, and the accent and secondary roles
/// from its best-scoring hues (by `Options.accent_by`). Roles with no hue to take stay null,
/// so they default from the palette.
pub fn themeInput(image: Image, options: Options) Error!Theme.Input {
    const analysis = try image.analyse(options);
    const mode = modeOf(analysis, options);
    const result = paletteFrom(analysis, options, mode);
    const accent = bestHue(analysis, options, null);
    const secondary = if (accent) |position| bestHue(analysis, options, position) else null;
    return .{
        .palette = result,
        .mode = mode,
        .roles = .{
            .accent = if (accent) |position| hueOf(result, position) else null,
            .secondary = if (secondary) |position| hueOf(result, position) else null,
        },
    };
}

fn analyse(image: Image, options: Options) Error!Analysis {
    if (image.pixels.len == 0) return error.ImageNotLoaded;
    return .from(image.pixels, options);
}

fn modeOf(analysis: Analysis, options: Options) Theme.Mode {
    return options.mode orelse if (analysis.average_lightness > options.light_above) .light else .dark;
}

fn paletteFrom(analysis: Analysis, options: Options, mode: Theme.Mode) Palette {
    var black = analysis.black;
    var white = analysis.white;
    if (options.style != .literal) moveApart(&black, &white, options.foreground_contrast);
    const hues = filled(analysis, options);
    var result: Palette = .{ .black = black, .white = white };
    const background = if (mode == .dark) black else white;
    inline for (@typeInfo(Palette.Hue).@"enum".field_names, 0..) |name, position| {
        if (hues[position]) |color| @field(result, name) = styled(color, background, options);
    }
    return result;
}

/// The hues the role defaults read, which `.semantic` makes up when the image lacks them.
const semantic_hues = [_]Palette.Hue{ .red, .yellow, .green };

/// The image's hues, plus those `Options.fill` makes up.
fn filled(analysis: Analysis, options: Options) [hue_count]?Color {
    var hues = analysis.hues;
    switch (options.fill) {
        .extracted => {},
        .semantic => for (semantic_hues) |hue| {
            const position = @backingInt(hue);
            if (hues[position] == null) hues[position] = madeUp(analysis, position, options);
        },
        .complete => for (&hues, 0..) |*hue, position| {
            if (hue.* == null) hue.* = madeUp(analysis, position, options);
        },
    }
    return hues;
}

/// A made-up hue for `position`: its reference hue, turned toward the accent by `Options.tint`,
/// at the lightness and chroma `Options.tone` picks.
fn madeUp(analysis: Analysis, position: usize, options: Options) Color {
    const tone = switch (options.tone) {
        .neighbours => neighbourTone(analysis, position),
        .uniform => uniformTone(analysis),
    } orelse fallbackTone(analysis, options);
    return withinGamut(.{ .lightness = tone.lightness, .chroma = tone.chroma, .hue = tintedHue(analysis, position, options) });
}

/// The lightness and chroma of a made-up hue.
const MadeUpTone = struct { lightness: f64, chroma: f64 };

/// The tone of the nearest image hues on either side of `position`, mixed by wheel position;
/// null when the image has no hues.
fn neighbourTone(analysis: Analysis, position: usize) ?MadeUpTone {
    for (1..hue_count) |previous_distance| {
        const previous = analysis.hues[(position + hue_count - previous_distance) % hue_count] orelse continue;
        for (1..hue_count) |next_distance| {
            const next = analysis.hues[(position + next_distance) % hue_count] orelse continue;
            const amount = @as(f64, @floatFromInt(previous_distance)) / @as(f64, @floatFromInt(previous_distance + next_distance));
            return .{
                .lightness = std.math.lerp(previous.lightness, next.lightness, amount),
                .chroma = std.math.lerp(previous.chroma, next.chroma, amount),
            };
        }
    }
    return null;
}

/// The average tone of the image's hues, weighted by their share of the pixels; null when the
/// image has no hues.
fn uniformTone(analysis: Analysis) ?MadeUpTone {
    var weight: f64 = 0;
    var lightness: f64 = 0;
    var chroma: f64 = 0;
    for (analysis.hues, analysis.shares) |hue, share| {
        const color = hue orelse continue;
        weight += share;
        lightness += color.lightness * share;
        chroma += color.chroma * share;
    }
    if (weight == 0) return null;
    return .{ .lightness = lightness / weight, .chroma = chroma / weight };
}

fn fallbackTone(analysis: Analysis, options: Options) MadeUpTone {
    return .{
        .lightness = std.math.lerp(analysis.black.lightness, analysis.white.lightness, 0.5),
        .chroma = options.fallback_chroma,
    };
}

/// The reference hue at `position`, turned by `Options.tint` of the shortest way toward the
/// accent's hue; unturned when the image has no hues.
fn tintedHue(analysis: Analysis, position: usize, options: Options) f64 {
    const reference = Analysis.referenceHues()[position];
    if (options.tint == 0) return reference;
    const accent = analysis.hues[bestHue(analysis, options, null) orelse return reference].?;
    var turn = Color.wrapHue(accent.hue - reference);
    if (turn > 180) turn -= 360;
    return Color.wrapHue(reference + turn * std.math.clamp(options.tint, 0, 1));
}

fn hueOf(result: Palette, position: usize) ?Color {
    return switch (@as(Palette.Hue, @fromBackingInt(@intCast(position)))) {
        inline else => |hue| @field(result, @tagName(hue)),
    };
}

/// The set hue scoring best, at least `Options.secondary_distance` away from `away_from` on
/// the wheel; null when none is.
fn bestHue(analysis: Analysis, options: Options, away_from: ?usize) ?usize {
    var best: ?usize = null;
    var best_score: f64 = 0;
    for (analysis.hues, analysis.shares, 0..) |hue, share, position| {
        const color = hue orelse continue;
        if (away_from) |other| {
            if (Analysis.hueDistance(wheelDegrees(position), wheelDegrees(other)) < options.secondary_distance) continue;
        }
        const score = switch (options.accent_by) {
            .vivid => share * color.chroma,
            .dominant => share,
        };
        if (best == null or score > best_score) {
            best = position;
            best_score = score;
        }
    }
    return best;
}

fn wheelDegrees(position: usize) f64 {
    return @as(f64, @floatFromInt(position)) * 30;
}

fn styled(color: Color, background: Color, options: Options) Color {
    return switch (options.style) {
        .literal => color,
        .readable => readable(color, background, options.minimum_contrast),
        .vivid => readable(scaledChroma(color, options.vivid_chroma), background, options.minimum_contrast),
        .muted => readable(scaledChroma(color, options.muted_chroma), background, options.minimum_contrast),
    };
}

fn scaledChroma(color: Color, factor: f64) Color {
    var scaled = color;
    scaled.chroma *= factor;
    return scaled;
}

/// `color` within sRGB, moved in lightness away from `background` until their contrast is at
/// least `minimum`, or as far as it goes.
fn readable(color: Color, background: Color, minimum: f64) Color {
    const start = withinGamut(color);
    if (start.contrastRatio(background) >= minimum) return start;
    const target: f64 = if (background.luminance() < 0.18) 1 else 0;
    var low: f64 = 0;
    var high: f64 = 1;
    for (0..search_steps) |_| {
        const amount = (low + high) / 2;
        if (withLightness(color, std.math.lerp(color.lightness, target, amount)).contrastRatio(background) >= minimum) high = amount else low = amount;
    }
    return withLightness(color, std.math.lerp(color.lightness, target, high));
}

/// Moves the darker of the two toward black and the lighter toward white, together, until
/// their contrast is at least `minimum`, or as far as they go.
fn moveApart(black: *Color, white: *Color, minimum: f64) void {
    if (black.contrastRatio(white.*) >= minimum) return;
    const darker = if (black.luminance() <= white.luminance()) black else white;
    const lighter = if (darker == black) white else black;
    const darker_start = darker.*;
    const lighter_start = lighter.*;
    var low: f64 = 0;
    var high: f64 = 1;
    for (0..search_steps) |_| {
        const amount = (low + high) / 2;
        const moved_darker = withLightness(darker_start, std.math.lerp(darker_start.lightness, 0, amount));
        const moved_lighter = withLightness(lighter_start, std.math.lerp(lighter_start.lightness, 1, amount));
        if (moved_darker.contrastRatio(moved_lighter) >= minimum) high = amount else low = amount;
    }
    darker.* = withLightness(darker_start, std.math.lerp(darker_start.lightness, 0, high));
    lighter.* = withLightness(lighter_start, std.math.lerp(lighter_start.lightness, 1, high));
}

fn withLightness(color: Color, lightness: f64) Color {
    var moved = color;
    moved.lightness = lightness;
    return withinGamut(moved);
}

/// `color` with its chroma lowered until it is inside sRGB, keeping lightness and hue.
fn withinGamut(color: Color) Color {
    if (!color.clips(.hex)) return color;
    var low: f64 = 0;
    var high: f64 = color.chroma;
    for (0..search_steps) |_| {
        var candidate = color;
        candidate.chroma = (low + high) / 2;
        if (candidate.clips(.hex)) high = candidate.chroma else low = candidate.chroma;
    }
    var fitted = color;
    fitted.chroma = low;
    return fitted;
}

const testing = std.testing;

fn gray(lightness: f64) Color {
    return .{ .lightness = lightness, .chroma = 0, .hue = 0 };
}

/// A pixel at wheel position `position` (its reference hue).
fn wheelPixel(position: usize, lightness: f64, chroma: f64) Color {
    return .{ .lightness = lightness, .chroma = chroma, .hue = Analysis.referenceHues()[position] };
}

test "an image kosm did not load has no colors" {
    const image: Image = .{ .path = "~/wallpaper.jxl" };
    try testing.expectError(error.ImageNotLoaded, image.palette(.{}));
    try testing.expectError(error.ImageNotLoaded, image.themeInput(.{}));
}

test "literal takes the image's colors exactly" {
    var pixels: [100]Color = @splat(gray(0.1));
    for (pixels[50..]) |*pixel| pixel.* = gray(0.25);
    for (pixels[0..10]) |*pixel| pixel.* = wheelPixel(8, 0.2, 0.08);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const result = try image.palette(.{ .style = .literal, .fill = .extracted, .mode = .dark });
    try testing.expectApproxEqAbs(0.1, result.black.lightness, 1e-9);
    try testing.expectApproxEqAbs(0.25, result.white.lightness, 1e-9);
    try testing.expectApproxEqAbs(0.2, result.blue.?.lightness, 1e-9);
    try testing.expectApproxEqAbs(0.08, result.blue.?.chroma, 1e-9);
    try testing.expectEqual(null, result.red);
}

test "readable lifts a dark hue to the minimum contrast, keeping its hue" {
    var pixels: [100]Color = @splat(gray(0.1));
    for (pixels[50..]) |*pixel| pixel.* = gray(0.9);
    for (pixels[0..10]) |*pixel| pixel.* = wheelPixel(8, 0.2, 0.08);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const result = try image.palette(.{ .mode = .dark });
    const blue = result.blue.?;
    try testing.expectApproxEqAbs(4.5, blue.contrastRatio(result.black), 0.01);
    try testing.expectApproxEqAbs(Analysis.referenceHues()[8], blue.hue, 1e-9);
    try testing.expect(!blue.clips(.hex));

    const light = try image.palette(.{ .mode = .light });
    try testing.expect(light.blue.?.contrastRatio(light.white) >= 4.5);
}

test "readable leaves a hue that is readable already" {
    var pixels: [100]Color = @splat(gray(0.1));
    for (pixels[50..]) |*pixel| pixel.* = gray(0.9);
    for (pixels[0..10]) |*pixel| pixel.* = wheelPixel(4, 0.8, 0.1);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    try testing.expectApproxEqAbs(0.8, (try image.palette(.{ .mode = .dark })).green.?.lightness, 1e-9);
}

test "readable moves black and white apart until they contrast enough" {
    var pixels: [100]Color = @splat(gray(0.4));
    for (pixels[50..]) |*pixel| pixel.* = gray(0.6);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const result = try image.palette(.{});
    try testing.expectApproxEqAbs(7, result.black.contrastRatio(result.white), 0.01);
    try testing.expect(result.black.lightness < 0.4);
    try testing.expect(result.white.lightness > 0.6);
}

test "vivid raises chroma within sRGB and muted lowers it" {
    var pixels: [100]Color = @splat(gray(0.1));
    for (pixels[50..]) |*pixel| pixel.* = gray(0.9);
    for (pixels[0..10]) |*pixel| pixel.* = wheelPixel(4, 0.8, 0.1);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const vivid = (try image.palette(.{ .style = .vivid, .mode = .dark })).green.?;
    try testing.expectApproxEqAbs(0.13, vivid.chroma, 1e-9);
    try testing.expectApproxEqAbs(0.06, (try image.palette(.{ .style = .muted, .mode = .dark })).green.?.chroma, 1e-9);

    for (pixels[0..10]) |*pixel| pixel.* = wheelPixel(4, 0.8, 0.2);
    const clipped = (try image.palette(.{ .style = .vivid, .mode = .dark })).green.?;
    try testing.expect(!clipped.clips(.hex));
    try testing.expect(clipped.chroma > 0.2);
}

test "a bright image gets a light theme unless the mode is set" {
    const pixels: [10]Color = @splat(gray(0.85));
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    try testing.expectEqual(.light, (try image.themeInput(.{})).mode);
    try testing.expectEqual(.dark, (try image.themeInput(.{ .mode = .dark })).mode);
    const dim: [10]Color = @splat(gray(0.3));
    try testing.expectEqual(.dark, (try (Image{ .path = "/b.png", .pixels = &dim }).themeInput(.{})).mode);
}

/// 40% dull green and 10% vivid orange over gray.
fn campfirePixels() [100]Color {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..40]) |*pixel| pixel.* = wheelPixel(4, 0.5, 0.035);
    for (pixels[40..50]) |*pixel| pixel.* = wheelPixel(1, 0.7, 0.18);
    return pixels;
}

test "the vivid accent is a small bright hue, the dominant one the most common" {
    const pixels = campfirePixels();
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const vivid = try image.themeInput(.{ .style = .literal });
    try testing.expectApproxEqAbs(0.18, vivid.roles.accent.?.chroma, 1e-9);
    try testing.expectApproxEqAbs(0.035, vivid.roles.secondary.?.chroma, 1e-9);
    const dominant = try image.themeInput(.{ .style = .literal, .accent_by = .dominant });
    try testing.expectApproxEqAbs(0.035, dominant.roles.accent.?.chroma, 1e-9);
    try testing.expectApproxEqAbs(0.18, dominant.roles.secondary.?.chroma, 1e-9);
}

test "the secondary role keeps its distance from the accent" {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..30]) |*pixel| pixel.* = wheelPixel(8, 0.5, 0.15);
    for (pixels[30..50]) |*pixel| pixel.* = wheelPixel(9, 0.5, 0.15);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const input = try image.themeInput(.{ .style = .literal });
    try testing.expectApproxEqAbs(Analysis.referenceHues()[8], input.roles.accent.?.hue, 1e-9);
    try testing.expectEqual(null, input.roles.secondary);
    const near = try image.themeInput(.{ .style = .literal, .secondary_distance = 30 });
    try testing.expectApproxEqAbs(Analysis.referenceHues()[9], near.roles.secondary.?.hue, 1e-9);
}

test "an image with no hues leaves the accent to the palette" {
    const pixels: [10]Color = @splat(gray(0.2));
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const input = try image.themeInput(.{});
    try testing.expectEqual(null, input.roles.accent);
    _ = Theme.from(input);
}

test "extracted leaves the hues the image lacks to mixing" {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..20]) |*pixel| pixel.* = wheelPixel(8, 0.6, 0.1);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const result = try image.palette(.{ .style = .literal, .fill = .extracted });
    try testing.expectEqual(null, result.red);
    try testing.expectEqual(null, result.green);
}

test "semantic makes up only red, yellow and green, at the image's lightness and chroma" {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..20]) |*pixel| pixel.* = wheelPixel(8, 0.6, 0.1);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const result = try image.palette(.{ .style = .literal });
    const references = Analysis.referenceHues();
    for ([_]?Color{ result.red, result.yellow, result.green }, [_]usize{ 0, 2, 4 }) |hue, position| {
        try testing.expectApproxEqAbs(0.6, hue.?.lightness, 1e-9);
        try testing.expectApproxEqAbs(0.1, hue.?.chroma, 1e-9);
        try testing.expectApproxEqAbs(references[position], hue.?.hue, 1e-9);
    }
    try testing.expectEqual(null, result.orange);
    try testing.expectEqual(null, result.purple);
}

test "complete makes up every hue from its neighbours by wheel position" {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..20]) |*pixel| pixel.* = wheelPixel(4, 0.5, 0.1);
    for (pixels[20..40]) |*pixel| pixel.* = wheelPixel(8, 0.7, 0.06);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const result = try image.palette(.{ .style = .literal, .fill = .complete });
    const cyan = result.cyan.?;
    try testing.expectApproxEqAbs(0.6, cyan.lightness, 1e-9);
    try testing.expectApproxEqAbs(0.08, cyan.chroma, 1e-9);
    try testing.expectApproxEqAbs(Analysis.referenceHues()[6], cyan.hue, 1e-9);
    inline for (@typeInfo(Palette.Hue).@"enum".field_names) |name| {
        try testing.expect(!@field(result, name).?.clips(.hex));
    }
}

test "made-up hues of a gray image take the fallback chroma, and are made readable" {
    var pixels: [100]Color = @splat(gray(0.1));
    for (pixels[50..]) |*pixel| pixel.* = gray(0.9);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const literal = try image.palette(.{ .style = .literal, .fill = .complete });
    try testing.expectApproxEqAbs(0.5, literal.blue.?.lightness, 1e-9);
    try testing.expectApproxEqAbs(0.12, literal.blue.?.chroma, 1e-9);
    const readable_palette = try image.palette(.{ .fill = .complete, .mode = .dark });
    try testing.expect(readable_palette.blue.?.contrastRatio(readable_palette.black) >= 4.5);
}

test "made-up hues are never picked as the accent" {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..20]) |*pixel| pixel.* = wheelPixel(8, 0.6, 0.05);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const input = try image.themeInput(.{ .style = .literal, .fill = .complete });
    try testing.expectApproxEqAbs(Analysis.referenceHues()[8], input.roles.accent.?.hue, 1e-9);
    try testing.expectEqual(null, input.roles.secondary);
}

test "a uniform tone gives made-up hues the image hues' average, weighted by share" {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..30]) |*pixel| pixel.* = wheelPixel(4, 0.4, 0.1);
    for (pixels[30..40]) |*pixel| pixel.* = wheelPixel(8, 0.8, 0.06);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const result = try image.palette(.{ .style = .literal, .fill = .complete, .tone = .uniform });
    for ([_]?Color{ result.red, result.magenta, result.pink }) |hue| {
        try testing.expectApproxEqAbs(0.5, hue.?.lightness, 1e-9);
        try testing.expectApproxEqAbs(0.09, hue.?.chroma, 1e-9);
    }
}

test "tint turns made-up hues toward the accent, the shortest way round" {
    var pixels: [100]Color = @splat(gray(0.5));
    for (pixels[0..20]) |*pixel| pixel.* = wheelPixel(8, 0.6, 0.1);
    const image: Image = .{ .path = "/a.png", .pixels = &pixels };
    const references = Analysis.referenceHues();
    const untinted = try image.palette(.{ .style = .literal });
    try testing.expectApproxEqAbs(references[0], untinted.red.?.hue, 1e-9);

    const half = try image.palette(.{ .style = .literal, .tint = 0.5 });
    var turn = Color.wrapHue(references[8] - references[0]);
    if (turn > 180) turn -= 360;
    try testing.expectApproxEqAbs(Color.wrapHue(references[0] + turn / 2), half.red.?.hue, 1e-9);
    try testing.expect(turn < 0);

    const full = try image.palette(.{ .style = .literal, .tint = 1 });
    try testing.expectApproxEqAbs(references[8], full.green.?.hue, 1e-9);
    try testing.expectApproxEqAbs(references[8], full.blue.?.hue, 1e-9);
}

test {
    testing.refAllDecls(Analysis);
}
