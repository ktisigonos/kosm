//! kitty's settings (D22, D27): every option of kitty.conf, grouped like kitty's docs and
//! named like kitty's options. `generate` writes the set ones to `file`, which kitty.conf
//! includes (`include kosm.conf`, D57); null options are left to kitty's defaults.

const App = @This();

const std = @import("std");
const kosm = @import("kosm");
const settings = @import("settings.zig");

/// The file kosm owns; kitty.conf includes it. Default: `~/.config/kitty/kosm.conf`.
file: []const u8 = "~/.config/kitty/kosm.conf",
/// How values are spelled (D70), e.g. `.color = .hex_upper`. Null fields take the kitty
/// adapter's: `#rrggbb`, `yes`/`no`, then kosm's 6 float decimals.
format: kosm.Format = .{},
/// Derives `color8`..`color15` from `color0`..`color7` when they are null (D23). null: they
/// are not derived. `from`: the theme's `lightness.bright`.
bright: ?kosm.Modifier = null,
/// Options the app doesn't cover, such as `map` (D99), written after its own under `# extra`:
/// `.{ .path = "map", .value = .{ .string = "ctrl+t new_tab" } }`. A path is one kitty option
/// name. One that repeats a set option or another extra fails the apply, unless kitty reads
/// that option more than once (`repeatable`). Default: none.
extra: []const kosm.Setting = &.{},

fonts: Fonts = .{},
cursor: Cursor = .{},
scrollback: Scrollback = .{},
mouse: Mouse = .{},
performance: Performance = .{},
bell: Bell = .{},
window: Window = .{},
tab_bar: TabBar = .{},
colors: Colors = .{},
advanced: Advanced = .{},
os: Os = .{},
shortcuts: Shortcuts = .{},

pub const Fonts = @import("sections/Fonts.zig");
pub const Cursor = @import("sections/Cursor.zig");
pub const Scrollback = @import("sections/Scrollback.zig");
pub const Mouse = @import("sections/Mouse.zig");
pub const Performance = @import("sections/Performance.zig");
pub const Bell = @import("sections/Bell.zig");
pub const Window = @import("sections/Window.zig");
pub const TabBar = @import("sections/TabBar.zig");
pub const Colors = @import("sections/Colors.zig");
pub const Advanced = @import("sections/Advanced.zig");
pub const Os = @import("sections/Os.zig");
pub const Shortcuts = @import("sections/Shortcuts.zig");

/// Options kitty reads more than once, each line adding another, so extras may repeat them
/// (D99): the sections' `repeated` options, and those the app doesn't cover.
pub const repeatable = blk: {
    var keys: []const []const u8 = &.{ "map", "mouse_map", "include", "globinclude", "envinclude", "geninclude" };
    for (@typeInfo(App).@"struct".field_types) |Field| {
        if (@typeInfo(Field) == .@"struct" and @hasDecl(Field, "repeated")) keys = keys ++ Field.repeated;
    }
    const final = keys;
    break :blk final;
};

/// Colors from the theme (D27): foreground and background from white and black (swapped in
/// light mode), the 8 terminal colors from the wheel, cyan for URLs and the active border.
/// Every other option is left to kitty.
pub fn from(theme: kosm.Theme) App {
    const palette = theme.palette;
    const variations = theme.variations;
    const foreground = if (theme.mode == .dark) palette.white else palette.black;
    const background = if (theme.mode == .dark) palette.black else palette.white;
    var app: App = .{ .bright = variations.lightness.bright };

    app.colors.foreground = foreground;
    app.colors.background = background;
    app.colors.selection_foreground = .{ .color = variations.emphasis.strong.apply(foreground) };
    app.colors.selection_background = .{ .color = variations.state.selected.apply(background) };
    app.colors.color0 = palette.black;
    app.colors.color1 = palette.red;
    app.colors.color2 = palette.green;
    app.colors.color3 = palette.yellow;
    app.colors.color4 = palette.blue;
    app.colors.color5 = palette.magenta;
    app.colors.color6 = palette.cyan;
    app.colors.color7 = palette.white;

    app.mouse.url_color = palette.cyan;
    app.window.active_border_color = .{ .color = palette.cyan };
    app.window.inactive_border_color = variations.state.inactive.apply(palette.cyan);
    app.window.bell_border_color = palette.yellow;

    app.tab_bar.active_tab_foreground = foreground;
    app.tab_bar.active_tab_background = variations.state.selected.apply(background);
    app.tab_bar.inactive_tab_foreground = variations.emphasis.muted.apply(foreground);
    app.tab_bar.inactive_tab_background = background;
    return app;
}

/// Makes every running kitty re-read its config by sending it SIGUSR1 (D74). With no kitty
/// running, kosm only warns.
pub fn reload(self: App, reloader: *kosm.Reloader) !void {
    _ = self;
    try reloader.run(&.{ "pkill", "-USR1", "-x", "kitty" });
}

/// Writes every set option to `file`, then the extras.
pub fn apply(self: App, output: *kosm.Output) !void {
    const derived = self.withDerived();
    const tree = try settings.tree(output.allocator, .{
        .fonts = derived.fonts,
        .cursor = derived.cursor,
        .scrollback = derived.scrollback,
        .mouse = derived.mouse,
        .performance = derived.performance,
        .bell = derived.bell,
        .window = derived.window,
        .tab_bar = derived.tab_bar,
        .colors = derived.colors,
        .advanced = derived.advanced,
        .os = derived.os,
        .shortcuts = derived.shortcuts,
    });
    const options = try optionKeys(output.allocator, tree);
    const all = try kosm.Setting.withExtras(output, self.file, options, self.extra, .{ .paths = .one_key, .repeatable = repeatable });
    try output.generate(.{ .file = self.file, .lang = "kitty", .format = self.format }, try withExtraSection(output.allocator, tree, all[options.len..]));
}

/// Every option of `tree` under its kitty name; sections are only comments in kitty.conf.
fn optionKeys(allocator: std.mem.Allocator, tree: kosm.Value) std.mem.Allocator.Error![]const kosm.Setting.Keyed {
    var options: std.ArrayList(kosm.Setting.Keyed) = .empty;
    for (tree.table) |section| for (section.value.table) |option| {
        try options.append(allocator, .{ .path = option.key, .keys = try allocator.dupe(?[]const u8, &.{option.key}), .value = option.value });
    };
    return options.items;
}

/// `tree` with an `extra` section after the others holding `extras`.
fn withExtraSection(allocator: std.mem.Allocator, tree: kosm.Value, extras: []const kosm.Setting.Keyed) std.mem.Allocator.Error!kosm.Value {
    if (extras.len == 0) return tree;
    const options = try allocator.alloc(kosm.Value.Entry, extras.len);
    for (extras, options) |extra, *option| option.* = .{ .key = extra.keys[0].?, .value = extra.value };
    return .{ .table = try std.mem.concat(allocator, kosm.Value.Entry, &.{ tree.table, &.{.{ .key = "extra", .value = .{ .table = options } }} }) };
}

/// An 8-bit alpha can't hold 0.5 exactly (`80` is 0.502), so derived opacities are rounded
/// to what the hex digits meant.
const opacity_steps = 100;

fn roundedAlpha(alpha: f64) f64 {
    return @round(alpha * opacity_steps) / opacity_steps;
}

/// Fills the options that derive from others when left null (D23).
fn withDerived(self: App) App {
    var app = self;
    const colors = &app.colors;
    if (app.cursor.cursor == null) if (colors.foreground) |foreground| {
        app.cursor.cursor = .{ .color = foreground };
    };
    if (app.cursor.cursor_text_color == null) if (colors.background) |background| {
        app.cursor.cursor_text_color = .{ .color = background };
    };
    if (colors.background_opacity == null) if (colors.background) |background| {
        if (background.alpha < 1) colors.background_opacity = roundedAlpha(background.alpha);
    };
    const bright = self.bright orelse return app;
    inline for (0..8) |index| {
        const bright_field = std.fmt.comptimePrint("color{d}", .{index + 8});
        const base_field = std.fmt.comptimePrint("color{d}", .{index});
        if (@field(colors, bright_field) == null) {
            if (@field(colors, base_field)) |base| @field(colors, bright_field) = bright.apply(base);
        }
    }
    return app;
}

const testing = std.testing;
const adapter = @import("adapter.zig").adapter;

test "apply writes the theme's colors and only the options the kosmos set" {
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
        .adapters = &.{adapter},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .warnings = &warnings,
        .app = "kitty",
    };

    const theme = kosm.Theme.from(.{ .black = kosm.hex("041c2680"), .white = kosm.hex("a3c5cc"), .cyan = kosm.hex("268078") }, .dark);
    var app = from(theme);
    app.fonts.font_family = .{ .family = "Maple Mono" };
    app.fonts.font_size = 13;
    app.window.window_padding_width = .all(10);
    app.advanced.shell_integration = .{ .no_cursor = true };
    app.colors.color15 = kosm.hex("b7dce5");
    try app.apply(&output);
    try testing.expectEqual(0, warnings.items.items.len);

    const written = plan.files.items[0].new;
    for ([_][]const u8{
        "# fonts\nfont_family family=\"Maple Mono\"\nfont_size 13\n",
        "\ncursor #a3c5cc\ncursor_text_color #041c26\n",
        "\nwindow_padding_width 10\n",
        "\nbackground #041c26\nbackground_opacity 0.5\n",
        "\ncolor15 #b7dce5\n",
        "\nshell_integration no-cursor\n",
    }) |expected| {
        if (std.mem.indexOf(u8, written, expected) == null) {
            std.debug.print("missing:\n{s}\nin:\n{s}\n", .{ expected, written });
            return error.TestExpectedEqual;
        }
    }
    try testing.expect(std.mem.indexOf(u8, written, "\ncolor8 #") != null);
    try testing.expect(std.mem.indexOf(u8, written, "scrollbar") == null);
    try testing.expect(std.mem.indexOf(u8, written, "# performance") == null);
}

test "App{} writes an empty file, and without bright no bright color is derived" {
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
        .adapters = &.{adapter},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .warnings = &warnings,
        .app = "kitty",
    };

    const empty: App = .{};
    try empty.apply(&output);
    try testing.expectEqualStrings("", plan.files.items[0].new);

    var app: App = .{};
    app.colors.color1 = kosm.hex("80333c");
    try testing.expectEqual(null, app.withDerived().colors.color9);
}

test "extras follow the options under # extra, repeatable ones as often as given (D99)" {
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
        .adapters = &.{adapter},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .warnings = &warnings,
        .app = "kitty",
    };

    var app: App = .{};
    app.fonts.font_size = 13;
    app.advanced.env = &.{.{ .name = "EDITOR", .value = "nvim" }};
    app.extra = &.{
        .{ .path = "map", .value = .{ .raw = "ctrl+t new_tab" } },
        .{ .path = "map", .value = .{ .raw = "ctrl+w close_tab" } },
        .{ .path = "env", .value = .{ .raw = "PAGER=less" } },
        .{ .path = "future_option", .value = .{ .boolean = true } },
    };
    try app.apply(&output);
    try testing.expectEqualStrings(
        \\# fonts
        \\font_size 13
        \\
        \\# advanced
        \\env EDITOR=nvim
        \\
        \\# extra
        \\map ctrl+t new_tab
        \\map ctrl+w close_tab
        \\env PAGER=less
        \\future_option yes
        \\
    , plan.files.items[0].new);

    app.extra = &.{.{ .path = "font_size", .value = .{ .integer = 12 } }};
    try testing.expectError(error.AppFailed, app.apply(&output));
    try testing.expectEqualStrings("extra 'font_size' and setting 'font_size' write the same key, or one inside the other; keep one (D99)", diagnostics.message());
}
