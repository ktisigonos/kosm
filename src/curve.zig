//! How a value moves from its start to its end over an animation: a cubic bezier or a spring.
//! The standard easings are ready-made beziers (`.ease_out_expo`), usable wherever a curve is.

const std = @import("std");

/// An animation's curve. Apps write it the way their program spells it.
pub const Curve = union(enum) {
    /// A cubic bezier from (0, 0) to (1, 1), given by its two control points.
    bezier: Bezier,
    /// A damped spring, which may overshoot before it settles.
    spring: Spring,

    /// The two control points of a cubic bezier, as CSS's `cubic-bezier(x1, y1, x2, y2)`: time
    /// runs along x, progress along y. `y` may leave 0..1 to overshoot.
    pub const Bezier = struct {
        /// 0..1.
        x1: f64,
        y1: f64,
        /// 0..1.
        x2: f64,
        y2: f64,
    };

    /// A mass on a spring: stiffer is faster, more damping overshoots less.
    pub const Spring = struct {
        /// Default: 1.
        mass: f64 = 1,
        stiffness: f64,
        damping: f64,
    };

    /// The curve through two control points.
    pub fn cubicBezier(x1: f64, y1: f64, x2: f64, y2: f64) Curve {
        return .{ .bezier = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2 } };
    }

    /// CSS's named timing functions.
    pub const linear: Curve = cubicBezier(0, 0, 1, 1);
    pub const ease: Curve = cubicBezier(0.25, 0.1, 0.25, 1);
    pub const ease_in: Curve = cubicBezier(0.42, 0, 1, 1);
    pub const ease_out: Curve = cubicBezier(0, 0, 0.58, 1);
    pub const ease_in_out: Curve = cubicBezier(0.42, 0, 0.58, 1);

    /// The standard easing functions as beziers, gentlest (sine) to sharpest (expo); `circ`
    /// follows a quarter circle and `back` overshoots. `in` starts slow, `out` ends slow.
    pub const ease_in_sine: Curve = cubicBezier(0.12, 0, 0.39, 0);
    pub const ease_out_sine: Curve = cubicBezier(0.61, 1, 0.88, 1);
    pub const ease_in_out_sine: Curve = cubicBezier(0.37, 0, 0.63, 1);
    pub const ease_in_quad: Curve = cubicBezier(0.11, 0, 0.5, 0);
    pub const ease_out_quad: Curve = cubicBezier(0.5, 1, 0.89, 1);
    pub const ease_in_out_quad: Curve = cubicBezier(0.45, 0, 0.55, 1);
    pub const ease_in_cubic: Curve = cubicBezier(0.32, 0, 0.67, 0);
    pub const ease_out_cubic: Curve = cubicBezier(0.33, 1, 0.68, 1);
    pub const ease_in_out_cubic: Curve = cubicBezier(0.65, 0, 0.35, 1);
    pub const ease_in_quart: Curve = cubicBezier(0.5, 0, 0.75, 0);
    pub const ease_out_quart: Curve = cubicBezier(0.25, 1, 0.5, 1);
    pub const ease_in_out_quart: Curve = cubicBezier(0.76, 0, 0.24, 1);
    pub const ease_in_quint: Curve = cubicBezier(0.64, 0, 0.78, 0);
    pub const ease_out_quint: Curve = cubicBezier(0.22, 1, 0.36, 1);
    pub const ease_in_out_quint: Curve = cubicBezier(0.83, 0, 0.17, 1);
    pub const ease_in_expo: Curve = cubicBezier(0.7, 0, 0.84, 0);
    pub const ease_out_expo: Curve = cubicBezier(0.16, 1, 0.3, 1);
    pub const ease_in_out_expo: Curve = cubicBezier(0.87, 0, 0.13, 1);
    pub const ease_in_circ: Curve = cubicBezier(0.55, 0, 1, 0.45);
    pub const ease_out_circ: Curve = cubicBezier(0, 0.55, 0.45, 1);
    pub const ease_in_out_circ: Curve = cubicBezier(0.85, 0, 0.15, 1);
    pub const ease_in_back: Curve = cubicBezier(0.36, 0, 0.66, -0.56);
    pub const ease_out_back: Curve = cubicBezier(0.34, 1.56, 0.64, 1);
    pub const ease_in_out_back: Curve = cubicBezier(0.68, -0.6, 0.32, 1.6);
};

const testing = std.testing;

/// The families that come as `ease_in_*`, `ease_out_*` and `ease_in_out_*`.
const families = [_][]const u8{ "sine", "quad", "cubic", "quart", "quint", "expo", "circ", "back" };

/// The bezier run backwards: an `out` easing is its `in` easing mirrored through the middle.
fn mirrored(bezier: Curve.Bezier) Curve.Bezier {
    return .{ .x1 = 1 - bezier.x2, .y1 = 1 - bezier.y2, .x2 = 1 - bezier.x1, .y2 = 1 - bezier.y1 };
}

fn expectSameBezier(expected: Curve.Bezier, actual: Curve.Bezier) !void {
    const tolerance = 1e-9;
    try testing.expectApproxEqAbs(expected.x1, actual.x1, tolerance);
    try testing.expectApproxEqAbs(expected.y1, actual.y1, tolerance);
    try testing.expectApproxEqAbs(expected.x2, actual.x2, tolerance);
    try testing.expectApproxEqAbs(expected.y2, actual.y2, tolerance);
}

test "the CSS easings hold the points CSS defines" {
    try testing.expectEqual(Curve.Bezier{ .x1 = 0, .y1 = 0, .x2 = 1, .y2 = 1 }, Curve.linear.bezier);
    try testing.expectEqual(Curve.Bezier{ .x1 = 0.25, .y1 = 0.1, .x2 = 0.25, .y2 = 1 }, Curve.ease.bezier);
    try testing.expectEqual(Curve.Bezier{ .x1 = 0.42, .y1 = 0, .x2 = 1, .y2 = 1 }, Curve.ease_in.bezier);
    try testing.expectEqual(Curve.Bezier{ .x1 = 0, .y1 = 0, .x2 = 0.58, .y2 = 1 }, Curve.ease_out.bezier);
    try testing.expectEqual(Curve.Bezier{ .x1 = 0.42, .y1 = 0, .x2 = 0.58, .y2 = 1 }, Curve.ease_in_out.bezier);
    try expectSameBezier(Curve.ease_in.bezier, mirrored(Curve.ease_out.bezier));
}

test "every out easing mirrors its in easing, and every in-out easing mirrors itself" {
    inline for (families) |family| {
        const in = @field(Curve, "ease_in_" ++ family).bezier;
        const out = @field(Curve, "ease_out_" ++ family).bezier;
        const in_out = @field(Curve, "ease_in_out_" ++ family).bezier;
        try expectSameBezier(in, mirrored(out));
        try expectSameBezier(in_out, mirrored(in_out));
    }
}

test "every easing is a bezier whose time stays within 0..1, and sharper families bend later" {
    inline for (@typeInfo(Curve).@"union".decl_names) |name| {
        if (@TypeOf(@field(Curve, name)) != Curve) continue;
        const bezier = @field(Curve, name).bezier;
        try testing.expect(bezier.x1 >= 0 and bezier.x1 <= 1);
        try testing.expect(bezier.x2 >= 0 and bezier.x2 <= 1);
    }
    // The points Hyprland's and CSS's own docs give for these two.
    try testing.expectEqual(Curve.Bezier{ .x1 = 0.16, .y1 = 1, .x2 = 0.3, .y2 = 1 }, Curve.ease_out_expo.bezier);
    try testing.expectEqual(Curve.Bezier{ .x1 = 0.5, .y1 = 1, .x2 = 0.89, .y2 = 1 }, Curve.ease_out_quad.bezier);
    // An in easing starts slower the sharper its family: its first control point moves right.
    try testing.expect(Curve.ease_in_sine.bezier.x1 < Curve.ease_in_cubic.bezier.x1);
    try testing.expect(Curve.ease_in_cubic.bezier.x1 < Curve.ease_in_quint.bezier.x1);
    try testing.expect(Curve.ease_in_quint.bezier.x1 < Curve.ease_in_expo.bezier.x1);
}
