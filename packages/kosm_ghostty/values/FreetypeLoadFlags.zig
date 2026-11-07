//! FreeType load flags (`freetype-load-flags`); Linux builds only. Null flags keep ghostty's defaults.

const FreetypeLoadFlags = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Hint glyphs. ghostty's default: on.
hinting: ?bool = null,
/// Always use FreeType's auto-hinter over the font's own. ghostty's default: off.
force_autohint: ?bool = null,
/// Render 1-bit glyphs, with no anti-aliasing. ghostty's default: off.
monochrome: ?bool = null,
/// Enable FreeType's auto-hinter. ghostty's default: on.
autohint: ?bool = null,
/// Use light hinting, which keeps glyph shapes. ghostty's default: on.
light: ?bool = null,

/// Writes the set flags the way ghostty spells them (`hinting,no-light`).
pub fn format(flags: FreetypeLoadFlags, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
