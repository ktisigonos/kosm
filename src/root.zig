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
    return comptime blk: {
        // The sRGB to OKLCH math (pow, cbrt) needs far more than the default 1000 branches.
        @setEvalBranchQuota(20_000);
        break :blk Color.parseHex(text) catch @compileError("kosm.hex: \"" ++ text ++ "\" is not a hex color");
    };
}

test {
    std.testing.refAllDecls(@This());
}

const test_palette: Palette = .{
    .black = hex("102840"),
    .white = hex("eceff4"),
    .red = hex("bf616a"),
    .orange = hex("d08770"),
    .yellow = hex("ebcb8b"),
    .green = hex("a3be8c"),
    .blue = hex("5e81ac"),
    .purple = hex("b48ead"),
};

test "a file-level palette of hex literals fits the comptime branch quota" {
    try std.testing.expectEqualStrings("#d08770", test_palette.orange.?.hex().slice());
}

test "hex works at compile time" {
    const color = comptime hex("#bf616a");
    try std.testing.expectEqualStrings("#bf616a", color.hex().slice());
}
