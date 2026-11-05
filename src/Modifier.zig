//! A transform applied to any color: OKLCH deltas, deltas in another color space (D68), a mix,
//! a contrast pick, alpha, or a chain of these (D15).

const Modifier = @This();

const std = @import("std");
const Color = @import("Color.zig");

/// Added to OKLCH lightness. Positive lightens. The result is not clamped (D48).
lightness: f64 = 0,
/// Added to OKLCH chroma. Positive saturates. The result never drops below 0.
chroma: f64 = 0,
/// Added to the hue, in degrees. The result wraps into 0..360.
hue: f64 = 0,
/// Deltas in HSV (= HSB), after the OKLCH ones: `.{ .value = 0.1 }` is Ricer's `v+10`. Null: none.
hsv: ?Hsv = null,
/// Deltas in HSL, after HSV. Null: none.
hsl: ?Hsl = null,
/// Deltas to the sRGB channels, after HSL. Null: none.
rgb: ?Rgb = null,
/// Deltas in naive CMYK, after RGB. Null: none.
cmyk: ?Cmyk = null,
/// Replaces the alpha (0..1) last, after any mix or contrast pick. Null keeps the alpha.
alpha: ?f64 = null,
/// Mixes toward a color after every delta. Null: no mix.
mix: ?Mix = null,
/// Replaces the color with a readable one on top of it, after the mix. Null: no contrast pick.
contrast: ?Contrast = null,
/// Steps run after this one, filled by `then`. Not meant to be set by hand.
chain: Chain = .{},

/// Deltas in HSV (= HSB) (D68).
pub const Hsv = @import("Modifier/Hsv.zig");
/// Deltas in HSL (D68).
pub const Hsl = @import("Modifier/Hsl.zig");
/// Deltas to sRGB channels (D68).
pub const Rgb = @import("Modifier/Rgb.zig");
/// Deltas in naive CMYK (D68).
pub const Cmyk = @import("Modifier/Cmyk.zig");
/// Mixing toward a color in OKLCH (D15).
pub const Mix = @import("Modifier/Mix.zig");
/// Picks whichever of two colors reads better on top of the color, by WCAG 2 contrast ratio (D15).
pub const Contrast = @import("Modifier/Contrast.zig");
/// One link of a composed modifier: the same fields as `Modifier`, minus the chain.
pub const Step = @import("Modifier/Step.zig");
/// Extra steps of a composed modifier, stored inline so composing needs no memory (D16).
pub const Chain = @import("Modifier/Chain.zig");

/// The most steps one modifier can hold, counting its own.
pub const max_steps = 8;

/// The modifier that changes nothing.
pub const identity: Modifier = .{};

/// Applies this modifier's own step, then every chained step in order.
pub fn apply(modifier: Modifier, color: Color) Color {
    var result = modifier.ownStep().apply(color);
    for (modifier.chain.steps[0..modifier.chain.length]) |step| result = step.apply(result);
    return result;
}

/// A modifier applying this one, then `next` (D16). The result is a copy: changing
/// either input later does not change it. At most `max_steps` steps in total.
pub fn then(modifier: Modifier, next: Modifier) Modifier {
    const total = 1 + modifier.chain.length + 1 + next.chain.length;
    // A user-visible limit, not an invariant; no real variation chain comes close.
    if (total > max_steps) @panic("kosm.Modifier.then: a composition can hold at most 8 steps");
    var result = modifier;
    result.chain.steps[result.chain.length] = next.ownStep();
    result.chain.length += 1;
    for (next.chain.steps[0..next.chain.length]) |step| {
        result.chain.steps[result.chain.length] = step;
        result.chain.length += 1;
    }
    return result;
}

fn ownStep(modifier: Modifier) Step {
    return .{
        .lightness = modifier.lightness,
        .chroma = modifier.chroma,
        .hue = modifier.hue,
        .hsv = modifier.hsv,
        .hsl = modifier.hsl,
        .rgb = modifier.rgb,
        .cmyk = modifier.cmyk,
        .alpha = modifier.alpha,
        .mix = modifier.mix,
        .contrast = modifier.contrast,
    };
}

const testing = std.testing;

const test_blue: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 250 };

test "deltas add to lightness, chroma and hue" {
    const result = (Modifier{ .lightness = 0.1, .chroma = 0.02, .hue = 20 }).apply(test_blue);
    try testing.expectApproxEqAbs(0.6, result.lightness, 1e-12);
    try testing.expectApproxEqAbs(0.12, result.chroma, 1e-12);
    try testing.expectApproxEqAbs(270.0, result.hue, 1e-12);
}

test "hue wraps around 360 in both directions" {
    try testing.expectApproxEqAbs(10.0, (Modifier{ .hue = 120 }).apply(test_blue).hue, 1e-12);
    try testing.expectApproxEqAbs(350.0, (Modifier{ .hue = -260 }).apply(test_blue).hue, 1e-12);
}

test "chroma never goes negative, lightness is kept out of range" {
    const result = (Modifier{ .lightness = 0.8, .chroma = -1 }).apply(test_blue);
    try testing.expectEqual(0.0, result.chroma);
    try testing.expectApproxEqAbs(1.3, result.lightness, 1e-12);
}

test "alpha replaces after a mix, null keeps" {
    const translucent: Color = .{ .lightness = 0.5, .chroma = 0.1, .hue = 250, .alpha = 0.4 };
    try testing.expectEqual(0.4, identity.apply(translucent).alpha);
    try testing.expectEqual(0.9, (Modifier{ .alpha = 0.9 }).apply(translucent).alpha);
    const mixed: Modifier = .{ .alpha = 0.9, .mix = .{ .toward = test_blue, .amount = 0.5 } };
    try testing.expectEqual(0.9, mixed.apply(translucent).alpha);
}

test "mix runs after the deltas" {
    const white: Color = .{ .lightness = 1, .chroma = 0, .hue = 0 };
    const result = (Modifier{ .lightness = 0.2, .mix = .{ .toward = white, .amount = 0.5 } }).apply(test_blue);
    try testing.expectApproxEqAbs(0.85, result.lightness, 1e-12);
}

test "contrast picks the more readable candidate" {
    const on: Modifier = .{ .contrast = .{} };
    const dark_background: Color = .{ .lightness = 0.2, .chroma = 0.05, .hue = 250 };
    const light_background: Color = .{ .lightness = 0.9, .chroma = 0.05, .hue = 90 };
    try testing.expectEqual(1.0, on.apply(dark_background).lightness);
    try testing.expectEqual(0.0, on.apply(light_background).lightness);
}

test "contrast can mix back toward the original" {
    const on_muted: Modifier = .{ .contrast = .{ .toward_original = 0.25 } };
    const background: Color = .{ .lightness = 0.2, .chroma = 0.08, .hue = 250 };
    const result = on_muted.apply(background);
    try testing.expectApproxEqAbs(0.8, result.lightness, 1e-12);
    try testing.expectApproxEqAbs(0.02, result.chroma, 1e-12);
    try testing.expectApproxEqAbs(250.0, result.hue, 1e-12);
}

test "then applies steps in order, including nested chains" {
    const lighten: Modifier = .{ .lightness = 0.1 };
    const desaturate: Modifier = .{ .chroma = -0.05 };
    const to_gray: Modifier = .{ .mix = .{ .toward = .{ .lightness = 0.5, .chroma = 0, .hue = 0 }, .amount = 1 } };
    const composed = lighten.then(desaturate.then(to_gray)).then(lighten);
    try testing.expectEqual(3, composed.chain.length);
    const result = composed.apply(test_blue);
    try testing.expectApproxEqAbs(0.6, result.lightness, 1e-12);
    try testing.expectEqual(0.0, result.chroma);
}

fn expectHex(expected: []const u8, color: Color) !void {
    try testing.expectEqualStrings(expected, color.hex8().slice());
}

test "hsv value scales every channel, like Ricer's v+20 and v-15 but rounded" {
    const brighter: Modifier = .{ .hsv = .{ .value = 0.2 } };
    const inactive: Modifier = .{ .hsv = .{ .value = -0.15 } };
    try expectHex("#ccf6ffff", brighter.apply(try Color.parseHex("a3c5cc")));
    try expectHex("#84a0a6ff", inactive.apply(try Color.parseHex("a3c5cc")));
    try expectHex("#041c2680", (Modifier{ .hsv = .{} }).apply(try Color.parseHex("041c2680")));
}

test "hsv hue and saturation deltas, with the hue wrapping" {
    const red = try Color.parseHex("ff0000");
    try expectHex("#ff00ffff", (Modifier{ .hsv = .{ .hue = -60 } }).apply(red));
    try expectHex("#ffffffff", (Modifier{ .hsv = .{ .saturation = -1 } }).apply(red));
    try expectHex("#ffff00ff", (Modifier{ .hsv = .{ .hue = 420 } }).apply(red));
}

test "a gray has hsv hue 0 despite the noise of its trip through OKLCH" {
    const saturate: Modifier = .{ .hsv = .{ .saturation = 1 } };
    try expectHex("#ff0000ff", saturate.apply(try Color.parseHex("ffffff")));
    try expectHex("#7f0000ff", saturate.apply(try Color.parseHex("7f7f7f")));
    try expectHex("#ff0101ff", (Modifier{ .hsl = .{ .saturation = 1 } }).apply(try Color.parseHex("808080")));
}

test "hsl, rgb and cmyk deltas" {
    const teal = try Color.parseHex("008080");
    try expectHex("#00ffffff", (Modifier{ .hsl = .{ .lightness = 0.249 } }).apply(teal));
    try expectHex("#338080ff", (Modifier{ .rgb = .{ .red = 0.2 } }).apply(teal));
    try expectHex("#004040ff", (Modifier{ .cmyk = .{ .key = 0.25 } }).apply(teal));
    try expectHex("#808080ff", (Modifier{ .cmyk = .{ .cyan = -1 } }).apply(teal));
}

test "space deltas are not clamped, so values past 1 survive in float components" {
    const white = try Color.parseHex("ffffff");
    const brighter = (Modifier{ .hsv = .{ .value = 0.5 } }).apply(white);
    try testing.expectEqualStrings("1.5 255", brighter.format("{} {}", &.{ .red_01, .red_255 }).slice());
    const back = (Modifier{ .hsv = .{ .value = -0.5 } }).apply(brighter);
    try expectHex("#ffffffff", back);
}

test "space parts run in a fixed order after the OKLCH deltas" {
    const black = try Color.parseHex("000000");
    // Black -> white (OKLCH), -> 0.6 gray (HSV), -> red 0.8 (RGB). RGB first would give #ccaaaa.
    const modifier: Modifier = .{ .lightness = 1, .hsv = .{ .value = -0.4 }, .rgb = .{ .red = 0.2 } };
    try expectHex("#cc9999ff", modifier.apply(black));
    const later: Modifier = .{ .rgb = .{ .red = 1 }, .mix = .{ .toward = black, .amount = 1 } };
    try expectHex("#000000ff", later.apply(black));
}

test "space parts are kept through then" {
    const composed = (Modifier{ .hsv = .{ .value = 0.1 } }).then(.{ .cmyk = .{ .key = 0.5 } });
    try testing.expect(composed.chain.steps[0].cmyk != null);
    try expectHex("#333333ff", composed.apply(try Color.parseHex("999999")));
}

test "then copies, so later changes to an input do not leak in" {
    var first: Modifier = .{ .lightness = 0.1 };
    const composed = first.then(.{ .lightness = 0.1 });
    first.lightness = 0.5;
    try testing.expectApproxEqAbs(0.7, composed.apply(test_blue).lightness, 1e-12);
}
