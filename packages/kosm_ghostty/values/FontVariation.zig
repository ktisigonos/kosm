//! One variable font axis and its value (`wght=800`).

const FontVariation = @This();

const Joined = @import("../Joined.zig");

/// The four-character axis tag, such as `wght`, `slnt` or `wdth`.
axis: []const u8,
/// The axis value; values the font doesn't support are ignored, not clamped.
value: f64,

/// Writes the value the way ghostty spells it, the number in the file's format.
pub fn write(variation: FontVariation, joined: *Joined) Joined.Error!void {
    try joined.writer().print("{s}=", .{variation.axis});
    try joined.float(variation.value);
}
