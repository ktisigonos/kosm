//! A transform applied to any color: OKLCH deltas, alpha, a mix, a contrast pick, or a chain of these (D15).

const Modifier = @This();

const std = @import("std");
const Color = @import("Color.zig");

/// Added to OKLCH lightness. Positive lightens. The result is not clamped (D48).
lightness: f64 = 0,
/// Added to OKLCH chroma. Positive saturates. The result never drops below 0.
chroma: f64 = 0,
/// Added to the hue, in degrees. The result wraps into 0..360.
hue: f64 = 0,
/// Replaces the alpha (0..1) last, after any mix or contrast pick. Null keeps the alpha.
alpha: ?f64 = null,
/// Mixes toward a color after the deltas. Null: no mix.
mix: ?Mix = null,
/// Replaces the color with a readable one on top of it, after the mix. Null: no contrast pick.
contrast: ?Contrast = null,
/// Steps run after this one, filled by `then`. Not meant to be set by hand.
chain: Chain = .{},

/// Mixing toward a color in OKLCH (D15).
pub const Mix = struct {
    /// The color to mix toward.
    toward: Color,
    /// 0 keeps the color, 1 gives `toward`.
    amount: f64,
};

/// Picks whichever of two colors reads better on top of the color, by WCAG 2 contrast ratio (D15).
pub const Contrast = struct {
    /// The dark candidate. `Theme.from` sets it to the palette's black.
    dark: Color = .{ .lightness = 0, .chroma = 0, .hue = 0 },
    /// The light candidate. `Theme.from` sets it to the palette's white.
    light: Color = .{ .lightness = 1, .chroma = 0, .hue = 0 },
    /// How far the pick mixes back toward the original color: 0 is full contrast.
    toward_original: f64 = 0,
};

/// One link of a composed modifier: the same fields as `Modifier`, minus the chain.
pub const Step = struct {
    lightness: f64 = 0,
    chroma: f64 = 0,
    hue: f64 = 0,
    alpha: ?f64 = null,
    mix: ?Mix = null,
    contrast: ?Contrast = null,

    /// Applies the deltas, then the mix, then the contrast pick, then the alpha (D15).
    pub fn apply(step: Step, color: Color) Color {
        var result: Color = .{
            .lightness = color.lightness + step.lightness,
            .chroma = @max(0, color.chroma + step.chroma),
            .hue = Color.wrapHue(color.hue + step.hue),
            .alpha = color.alpha,
        };
        if (step.mix) |mixing| result = result.mix(mixing.toward, mixing.amount);
        if (step.contrast) |contrast| {
            const readable = if (result.contrastRatio(contrast.dark) >= result.contrastRatio(contrast.light)) contrast.dark else contrast.light;
            result = readable.mix(result, contrast.toward_original);
        }
        if (step.alpha) |alpha| result.alpha = alpha;
        return result;
    }
};

/// Extra steps of a composed modifier, stored inline so composing needs no memory (D16).
pub const Chain = struct {
    steps: [max_steps - 1]Step = undefined,
    length: usize = 0,
};

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

test "then copies, so later changes to an input do not leak in" {
    var first: Modifier = .{ .lightness = 0.1 };
    const composed = first.then(.{ .lightness = 0.1 });
    first.lightness = 0.5;
    try testing.expectApproxEqAbs(0.7, composed.apply(test_blue).lightness, 1e-12);
}
