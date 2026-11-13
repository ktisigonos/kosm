//! Kosm core: colors, palettes, modifiers and themes, and the writers apps plan files through.

const std = @import("std");

pub const Color = @import("Color.zig");
pub const Palette = @import("Palette.zig");
pub const Modifier = @import("Modifier.zig");
pub const Variations = @import("Variations.zig");
pub const Theme = @import("Theme.zig");
pub const Mode = Theme.Mode;
pub const Keyboard = @import("Keyboard.zig");
pub const Curve = @import("curve.zig").Curve;
pub const ColorFormat = @import("ColorFormat.zig");
pub const Format = @import("Format.zig");
pub const ColorChoice = @import("color_choice.zig").ColorChoice;
pub const Raw = @import("Raw.zig");
pub const Value = @import("value.zig").Value;
pub const Setting = @import("Setting.zig");
pub const Path = @import("Path.zig");
pub const Adapter = @import("Adapter.zig");
pub const treesitter = @import("treesitter.zig");
pub const Output = @import("Output.zig");
pub const Diagnostics = @import("Diagnostics.zig");
pub const Warnings = @import("Warnings.zig");
pub const Reloader = @import("Reloader.zig");
pub const Plan = @import("Plan.zig");
pub const commit = @import("commit.zig");
pub const diff = @import("diff.zig");

/// Text written into a file verbatim, with no quoting or escaping.
pub fn raw(text: []const u8) Raw {
    return .{ .text = text };
}

/// A color from hex text known at compile time: `rgb`, `rgba`, `rrggbb` or `rrggbbaa`,
/// with an optional `#`. Bad text is a compile error; use `Color.parseHex` at runtime. The
/// color is known at compile time too, so a list of them (`&.{ hex("000000") }`) is a constant
/// that outlives the function writing it.
pub inline fn hex(comptime text: []const u8) Color {
    return comptime blk: {
        // The sRGB to OKLCH math (pow, cbrt) needs far more than the default 1000 branches.
        @setEvalBranchQuota(20_000);
        break :blk Color.parseHex(text) catch @compileError("kosm.hex: \"" ++ text ++ "\" is not a hex color");
    };
}

fn blackList() []const Color {
    return &.{hex("000000")};
}

fn overwriteStack(seed: u8) u8 {
    var buffer: [256]u8 = @splat(seed);
    std.mem.doNotOptimizeAway(&buffer);
    return buffer[0];
}

test "a list of hex colors written in a function outlives it" {
    const colors = blackList();
    _ = overwriteStack(0xff);
    comptime std.debug.assert(hex("ff0000").alpha == 1);
    try std.testing.expectEqual(0, colors[0].lightness);
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Color);
    std.testing.refAllDecls(Color.Hsv);
    std.testing.refAllDecls(Color.Hsl);
    std.testing.refAllDecls(Color.Cmyk);
    std.testing.refAllDecls(@import("Color/parse.zig"));
    std.testing.refAllDecls(@import("color_choice.zig"));
    std.testing.refAllDecls(Palette);
    std.testing.refAllDecls(Theme);
    std.testing.refAllDecls(Theme.Roles);
    std.testing.refAllDecls(Theme.Code);
    std.testing.refAllDecls(Modifier);
    std.testing.refAllDecls(Modifier.Step);
    std.testing.refAllDecls(Variations);
    std.testing.refAllDecls(Keyboard);
    std.testing.refAllDecls(@import("curve.zig"));
    std.testing.refAllDecls(ColorFormat);
    std.testing.refAllDecls(Format);
    std.testing.refAllDecls(Format.Resolved);
    std.testing.refAllDecls(@import("value.zig"));
    std.testing.refAllDecls(Adapter);
    std.testing.refAllDecls(Adapter.Context);
    std.testing.refAllDecls(Output);
    std.testing.refAllDecls(Output.Selection);
    std.testing.refAllDecls(@import("Path.zig"));
    std.testing.refAllDecls(Setting);
    std.testing.refAllDecls(@import("glob.zig"));
    std.testing.refAllDecls(treesitter);
    std.testing.refAllDecls(Diagnostics);
    std.testing.refAllDecls(Warnings);
    std.testing.refAllDecls(Reloader);
    std.testing.refAllDecls(Plan);
    std.testing.refAllDecls(Plan.Edit);
    std.testing.refAllDecls(@import("block.zig"));
    std.testing.refAllDecls(commit);
    std.testing.refAllDecls(diff);
    std.testing.refAllDecls(@import("template.zig"));
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
