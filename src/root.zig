//! Kosm core: colors, palettes, modifiers and themes.

const std = @import("std");

pub const Color = @import("Color.zig");
pub const Palette = @import("Palette.zig");
pub const Modifier = @import("Modifier.zig");
pub const Variations = @import("Variations.zig");
pub const Theme = @import("Theme.zig");
pub const Mode = Theme.Mode;

/// A color from hex text known at compile time: `rgb`, `rgba`, `rrggbb` or `rrggbbaa`,
/// with an optional `#`. Bad text is a compile error; use `Color.parseHex` at runtime.
pub fn hex(comptime text: []const u8) Color {
    return comptime Color.parseHex(text) catch @compileError("kosm.hex: \"" ++ text ++ "\" is not a hex color");
}

test {
    std.testing.refAllDecls(@This());
}

test "hex works at compile time" {
    const color = comptime hex("#bf616a");
    try std.testing.expectEqualStrings("#bf616a", color.hex().slice());
}
