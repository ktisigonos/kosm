//! Codepoints replaced when text is copied to the clipboard (`clipboard-codepoint-map`).

const ClipboardCodepointMap = @This();

const std = @import("std");
const CodepointRange = @import("CodepointRange.zig");

/// The codepoints to replace.
codepoints: CodepointRange,
/// What each one becomes.
replacement: Replacement,

/// One codepoint, or text.
pub const Replacement = union(enum) { codepoint: u21, text: []const u8 };

/// Writes the value the way ghostty spells it (`U+2500=U+002D`, `U+03A3=SUM`).
pub fn format(map: ClipboardCodepointMap, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try map.codepoints.format(writer);
    switch (map.replacement) {
        .codepoint => |codepoint| try writer.print("=U+{X:0>4}", .{codepoint}),
        .text => |text| try writer.print("={s}", .{text}),
    }
}
