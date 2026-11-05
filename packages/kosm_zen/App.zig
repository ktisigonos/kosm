//! Zen Browser's theme colors (D22, D27), generated as `--kosm-*` custom properties into
//! `file`. userChrome.css and userContent.css `@import` it and use them through `var()` (D57).

const App = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The file kosm owns. Default: `~/.config/ZenBrowser/kosm.css`.
file: []const u8 = "~/.config/ZenBrowser/kosm.css",
/// How colors are printed. null: `#rrggbbaa`, the CSS adapter's format (D61).
color_format: ?kosm.ColorFormat = null,
/// Text and icons (`--kosm-foreground`). Default: white, black in light mode.
foreground: kosm.Color,
/// Links, focused fields and the selected tab's text (`--kosm-accent`). Default: cyan.
accent: kosm.Color,
/// Toolbars, sidebar, panels and new tab page (`--kosm-background`). Default: black, white
/// in light mode.
background: kosm.Color,
/// Buttons and the toolbar (`--kosm-button`). Default: `surface.raised` of `background`.
button: kosm.Color,
/// Buttons under the pointer (`--kosm-button-hovered`). null: `hovered` of `button` (D23).
button_hovered: ?kosm.Color = null,
/// Borders and outlines (`--kosm-border`). Default: cyan.
border: kosm.Color,
/// Container tab colors (`--kosm-containers-blue`, ...). Default: the wheel's hues.
containers: Containers,
/// Makes `button_hovered` from `button` when it is null (D23, D24). Default: the theme's
/// `state.hovered`.
hovered: kosm.Modifier,

pub const Containers = @import("Containers.zig");

/// Colors from the theme (D27).
pub fn from(theme: kosm.Theme) App {
    const palette = theme.palette;
    const background = if (theme.mode == .dark) palette.black else palette.white;
    return .{
        .foreground = if (theme.mode == .dark) palette.white else palette.black,
        .accent = palette.cyan,
        .background = background,
        .button = theme.variations.surface.raised.apply(background),
        .border = palette.cyan,
        .containers = .{
            .blue = palette.blue,
            .turquoise = palette.cyan,
            .green = palette.green,
            .yellow = palette.yellow,
            .orange = palette.orange,
            .red = palette.red,
            .pink = palette.pink,
            .purple = palette.purple,
        },
        .hovered = theme.variations.state.hovered,
    };
}

/// Writes every color as a `--kosm-*` custom property.
pub fn apply(self: App, output: *kosm.Output) !void {
    try output.generate(.{ .file = self.file, .lang = "css", .color_format = self.color_format }, .{ .kosm = .{
        .foreground = self.foreground,
        .accent = self.accent,
        .background = self.background,
        .button = self.button,
        .button_hovered = self.button_hovered orelse self.hovered.apply(self.button),
        .border = self.border,
        .containers = self.containers,
    } });
}

const testing = std.testing;
const css = @import("kosm_css");

test "apply writes every color as a --kosm custom property" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = home_buffer[0..try tmp.dir.realPath(testing.io, &home_buffer)];
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var plan: kosm.Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    var diagnostics: kosm.Diagnostics = .{};
    var output: kosm.Output = .{
        .allocator = arena.allocator(),
        .home = home,
        .adapters = &.{css.adapter},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .app = "zen",
    };

    const theme = kosm.Theme.from(.{ .black = kosm.hex("041c26"), .white = kosm.hex("a3c5cc"), .cyan = kosm.hex("268078") }, .dark);
    var app = from(theme);
    app.button = kosm.hex("082e3f");
    app.containers.pink = kosm.hex("4d74af");
    try app.apply(&output);

    const written = plan.files.items[0].new;
    try testing.expect(std.mem.startsWith(u8, written, ":root {\n  --kosm-foreground: #a3c5ccff;\n  --kosm-accent: #268078ff;\n"));
    try testing.expect(std.mem.indexOf(u8, written, "\n  --kosm-button: #082e3fff;\n  --kosm-button-hovered: #") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\n  --kosm-containers-pink: #4d74afff;\n") != null);
    try testing.expect(std.mem.endsWith(u8, written, "\n}\n"));
}
