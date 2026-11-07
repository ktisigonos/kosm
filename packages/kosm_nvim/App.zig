//! Neovim's colors (D22, D27): a base16 palette plus the terminal colors, written from
//! `templates/theme.lua` to `file`, which returns them as a Lua table for the user's own
//! nvim config to load (D57).

const App = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The file kosm owns. Default: `~/.config/nvim/lua/theme.lua`.
file: []const u8 = "~/.config/nvim/lua/theme.lua",
/// How values are spelled (D70), e.g. `.color = .hex_upper`. Default: colors as `#rrggbb`;
/// null fields take kosm's `true`/`false` and 6 float decimals.
format: kosm.Format,
/// Whether the colorscheme leaves the background transparent. Default: false.
transparent: bool = false,
/// The base16 slots.
base16: Base16,
/// The 8 terminal colors and their bright variants.
terminal: Terminal,

pub const Base16 = @import("Base16.zig");
pub const Terminal = @import("Terminal.zig");

/// Colors from the theme (D27): base16 backgrounds and foregrounds from black and white
/// (swapped in light mode), its accents and the terminal colors from the wheel.
pub fn from(theme: kosm.Theme) App {
    const palette = theme.palette;
    const variations = theme.variations;
    const background = if (theme.mode == .dark) palette.black else palette.white;
    const foreground = if (theme.mode == .dark) palette.white else palette.black;
    const bright = variations.lightness.bright;
    return .{
        .format = .{ .color = .hex },
        .base16 = .{
            .base00 = background,
            .base01 = variations.surface.raised.apply(background),
            .base02 = variations.state.selected.apply(background),
            .base03 = variations.emphasis.muted.apply(foreground),
            .base04 = variations.emphasis.muted.apply(foreground),
            .base05 = foreground,
            .base06 = variations.emphasis.strong.apply(foreground),
            .base07 = bright.apply(foreground),
            .base08 = palette.red,
            .base09 = palette.orange,
            .base0A = palette.yellow,
            .base0B = palette.green,
            .base0C = palette.cyan,
            .base0D = palette.blue,
            .base0E = palette.purple,
            .base0F = palette.pink,
        },
        .terminal = .{
            .black = palette.black,
            .red = palette.red,
            .green = palette.green,
            .yellow = palette.yellow,
            .blue = palette.blue,
            .magenta = palette.magenta,
            .cyan = palette.cyan,
            .white = palette.white,
            .br_black = bright.apply(palette.black),
            .br_red = bright.apply(palette.red),
            .br_green = bright.apply(palette.green),
            .br_yellow = bright.apply(palette.yellow),
            .br_blue = bright.apply(palette.blue),
            .br_magenta = bright.apply(palette.magenta),
            .br_cyan = bright.apply(palette.cyan),
            .br_white = bright.apply(palette.white),
        },
    };
}

/// Writes the palette to `file`.
pub fn apply(self: App, output: *kosm.Output) !void {
    try output.template(self, .{
        .file = self.file,
        .text = @embedFile("templates/theme.lua"),
        .format = self.format,
    });
}

const testing = std.testing;

test "apply fills the template with the palette" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = home_buffer[0..try tmp.dir.realPath(testing.io, &home_buffer)];
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var plan: kosm.Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    var diagnostics: kosm.Diagnostics = .{};
    var warnings: kosm.Warnings = .init(arena.allocator());
    var output: kosm.Output = .{
        .allocator = arena.allocator(),
        .home = home,
        .adapters = &.{},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .warnings = &warnings,
        .app = "nvim",
    };

    const theme = kosm.Theme.from(.{ .black = kosm.hex("041c26"), .white = kosm.hex("a3c5cc"), .red = kosm.hex("80333c") }, .dark);
    var app = from(theme);
    app.transparent = true;
    app.terminal.br_white = kosm.hex("b7dce5");
    try app.apply(&output);
    try testing.expectEqual(0, warnings.items.items.len);

    const written = plan.files.items[0].new;
    try testing.expect(std.mem.startsWith(u8, written, "return {\n  transparent = true,\n\n  base00 = '#041c26',\n"));
    try testing.expect(std.mem.indexOf(u8, written, "\n  base08 = '#80333c',\n") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\n  white = '#a3c5cc',\n") != null);
    try testing.expect(std.mem.endsWith(u8, written, "\n  br_white = '#b7dce5',\n}\n"));
}
