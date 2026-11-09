//! kitty's "Fonts" options. Field names are kitty's option names.

const values = @import("../values.zig");

/// The main font face: a family name or a precise font specification. null: kitty's default, `monospace`.
font_family: ?values.Font = null,
/// The bold face, picked automatically from `font_family` by default. null: kitty's default, `auto`.
bold_font: ?values.FontOrAuto = null,
/// The italic face, picked automatically from `font_family` by default. null: kitty's default, `auto`.
italic_font: ?values.FontOrAuto = null,
/// The bold italic face, picked automatically from `font_family` by default. null: kitty's default, `auto`.
bold_italic_font: ?values.FontOrAuto = null,
/// Font size (in pts). null: kitty's default, `11.0`.
font_size: ?f64 = null,
/// Render right-to-left scripts left to right, without kitty reordering words. null: kitty's default, `no`.
force_ltr: ?bool = null,
/// Map the specified Unicode codepoints to a particular font. Each item is written as its own line.
symbol_map: []const values.SymbolMap = &.{},
/// Restrict codepoints to a number of cells instead of letting them grow into following spaces. Each item is written as its own line.
narrow_symbols: []const values.NarrowSymbols = &.{},
/// Choose how you want to handle multi-character ligatures. null: kitty's default, `never`.
disable_ligatures: ?enum { never, cursor, always } = null,
/// Choose exactly which OpenType features to enable or disable. Each item is written as its own line.
font_features: []const values.FontFeatures = &.{},
/// Modify font characteristics such as the position or thickness of the underline and strikethrough. Each item is written as its own line.
modify_font: []const values.ModifyFont = &.{},
/// The sizes of the lines used for the box drawing Unicode characters. null: kitty's default, `0.001, 1, 1.5, 2`.
box_drawing_scale: ?values.BoxDrawingScale = null,
/// The style with which undercurls are rendered. null: kitty's default, `thin-sparse`.
undercurl_style: ?enum { thin_sparse, thin_dense, thick_sparse, thick_dense } = null,
/// The size of the gaps kitty leaves in underlines where they cross descenders; 0 disables them. null: kitty's default, `1`.
underline_exclusion: ?values.UnderlineExclusion = null,
/// Control how kitty composites text glyphs onto the background color. null: kitty's default, `platform`.
text_composition_strategy: ?values.TextComposition = null,
/// A setting to prevent low contrast between foreground and background colors. null: kitty's default, `0`.
text_fg_override_threshold: ?values.ContrastThreshold = null,

/// Options kitty allows more than once: each item is its own line.
pub const repeated = [_][]const u8{ "symbol_map", "narrow_symbols", "font_features", "modify_font" };
