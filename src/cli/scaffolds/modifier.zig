//! The scaffold_name modifier, made by `kosm new modifier scaffold_name`. A kosmos uses it with
//! `const scaffold_name = @import("scaffold_name");` and sets `scaffold_name.modifier(.{})`
//! wherever a modifier goes (a variation, a `then` step), or calls
//! `scaffold_name.modifier(.{ .amount = 0.2 }).apply(color)` on a color.

const kosm = @import("kosm");

/// Warms a color: shifts its hue toward orange and adds a little chroma.
pub const Modifier = struct {
    /// How far toward orange, 0..1. Default: 0.5.
    amount: f64 = 0.5,

    /// The color changed. Runs wherever the modifier is applied, so it never fails.
    pub fn apply(self: Modifier, color: kosm.Color) kosm.Color {
        // The shorter way round the wheel, -180..180 degrees.
        const toward_warm = kosm.Color.wrapHue(warm_hue - color.hue + 180) - 180;
        var result = color;
        result.hue = kosm.Color.wrapHue(color.hue + toward_warm * self.amount * hue_share);
        result.chroma += 0.02 * self.amount;
        return result;
    }
};

/// The hue warmed toward, in degrees (orange).
const warm_hue: f64 = 60;
/// The share of the way to `warm_hue` an amount of 1 goes.
const hue_share: f64 = 0.25;

/// The modifier with `fields` set, as a `kosm.Modifier` to set wherever a modifier goes or to
/// compose with `then`.
pub fn modifier(fields: Modifier) kosm.Modifier {
    return .{ .function = .of(Modifier, fields) };
}
