//! One link of a composed modifier: the same fields as `Modifier`, minus the chain.

const Step = @This();

const Color = @import("../Color.zig");
const Mix = @import("Mix.zig");
const Contrast = @import("Contrast.zig");
const Hsv = @import("Hsv.zig");
const Hsl = @import("Hsl.zig");
const Rgb = @import("Rgb.zig");
const Cmyk = @import("Cmyk.zig");

lightness: f64 = 0,
chroma: f64 = 0,
hue: f64 = 0,
hsv: ?Hsv = null,
hsl: ?Hsl = null,
rgb: ?Rgb = null,
cmyk: ?Cmyk = null,
alpha: ?f64 = null,
mix: ?Mix = null,
contrast: ?Contrast = null,

/// Applies the OKLCH deltas, then HSV, HSL, RGB and CMYK, then the mix, then the
/// contrast pick, then the alpha.
pub fn apply(step: Step, color: Color) Color {
    var result: Color = .{
        .lightness = color.lightness + step.lightness,
        .chroma = @max(0, color.chroma + step.chroma),
        .hue = Color.wrapHue(color.hue + step.hue),
        .alpha = color.alpha,
    };
    if (step.hsv) |hsv| result = hsv.apply(result);
    if (step.hsl) |hsl| result = hsl.apply(result);
    if (step.rgb) |rgb| result = rgb.apply(result);
    if (step.cmyk) |cmyk| result = cmyk.apply(result);
    if (step.mix) |mixing| result = result.mix(mixing.toward, mixing.amount);
    if (step.contrast) |contrast| {
        const readable = if (result.contrastRatio(contrast.dark) >= result.contrastRatio(contrast.light)) contrast.dark else contrast.light;
        result = readable.mix(result, contrast.toward_original);
    }
    if (step.alpha) |alpha| result.alpha = alpha;
    return result;
}
