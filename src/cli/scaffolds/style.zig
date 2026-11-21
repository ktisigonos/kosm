//! The scaffold_name palette style, made by `kosm new style scaffold_name`. A kosmos uses it with
//! `const scaffold_name = @import("scaffold_name");` and takes an image's colors with it:
//! `image.palette(.{ .style = scaffold_name.style(.{}) })`.

const kosm = @import("kosm");

/// Takes each hue of an image softened: less chroma, then readable on the background.
pub const Style = struct {
    /// The share of each hue's chroma kept, 0..1. Default: 0.6.
    chroma: f64 = 0.6,
    /// The WCAG 2 contrast ratio (1..21) every hue keeps against the background. Default: 4.5.
    contrast: f64 = 4.5,

    /// The final color of `hue`, taken from an image whose theme has `background`. It never fails.
    pub fn apply(self: Style, hue: kosm.Color, background: kosm.Color) kosm.Color {
        var soft = hue;
        soft.chroma *= self.chroma;
        return kosm.Image.readable(soft, background, self.contrast);
    }
};

/// The palette style with `fields` set, as a `kosm.Image.Style` to take an image's colors with.
pub fn style(fields: Style) kosm.Image.Style {
    return .{ .function = .of(Style, fields) };
}
