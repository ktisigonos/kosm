//! Neovim's colors: a base16 palette plus the terminal colors, generated into
//! `file` as a Lua module returning them in one flat table (`base00`, ..., `br_white`), for the
//! user's own nvim config to load with `require`. Null values are not written.

const App = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The file kosm owns. Default: `~/.config/nvim/lua/theme.lua`.
file: []const u8 = "~/.config/nvim/lua/theme.lua",
/// How values are spelled, e.g. `.color = .hex_upper`. Null fields take the Lua
/// adapter's `true`/`false`, then kosm's `#rrggbb` and 6 float decimals.
format: kosm.Format = .{},
/// Whether the colorscheme leaves the background transparent. null: not written.
transparent: ?bool = null,
/// The base16 slots.
base16: Base16 = .{},
/// The 8 terminal colors and their bright variants.
terminal: Terminal = .{},
/// Values the app doesn't cover, written into the module after its own, nested by path:
/// `.{ .path = "accent.soft", .value = .{ .color = kosm.hex("2d8699") } }` is `theme.accent.soft`.
/// One whose path equals, contains or lies inside a set value's or another extra's fails the
/// apply. Default: none.
extra: []const kosm.Setting = &.{},

pub const Base16 = @import("Base16.zig");
pub const Terminal = @import("Terminal.zig");

/// Colors from the theme: base16 backgrounds and foregrounds from black and white
/// (swapped in light mode), its accents and the terminal colors from the wheel.
pub fn from(theme: kosm.Theme) App {
    const palette = theme.palette;
    const variations = theme.variations;
    const background = if (theme.mode == .dark) palette.black else palette.white;
    const foreground = if (theme.mode == .dark) palette.white else palette.black;
    const bright = variations.lightness.bright;
    return .{
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

/// Writes every set value to `file`, then the extras.
pub fn apply(self: App, output: *kosm.Output) !void {
    const values = try kosm.Setting.leaves(output.allocator, try self.tree(output.allocator));
    const all = try kosm.Setting.withExtras(output, self.file, values, self.extra, .{});
    try output.generate(.{ .file = self.file, .lang = "lua", .format = self.format }, try kosm.Setting.tree(output.allocator, all));
}

/// `transparent`, then the base16 slots, then the terminal colors, in one table as the user's
/// config reads them (`theme.base00`, `theme.br_white`).
fn tree(self: App, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
    var entries: std.ArrayList(kosm.Value.Entry) = .empty;
    if (self.transparent) |transparent| try entries.append(allocator, .{ .key = "transparent", .value = .{ .boolean = transparent } });
    try appendColors(allocator, &entries, self.base16);
    try appendColors(allocator, &entries, self.terminal);
    return .{ .table = entries.items };
}

fn appendColors(allocator: std.mem.Allocator, entries: *std.ArrayList(kosm.Value.Entry), colors: anytype) std.mem.Allocator.Error!void {
    inline for (@typeInfo(@TypeOf(colors)).@"struct".field_names) |name| {
        if (@field(colors, name)) |color| try entries.append(allocator, .{ .key = name, .value = .{ .color = color } });
    }
}

const testing = std.testing;
const lua = @import("kosm_lua");

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings = undefined,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output = undefined,

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{lua.adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "nvim",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }
};

test "apply writes the palette as one flat Lua table" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const theme = kosm.Theme.from(.{ .black = kosm.hex("041c26"), .white = kosm.hex("a3c5cc"), .red = kosm.hex("80333c") }, .dark);
    var app = from(theme);
    app.transparent = true;
    app.terminal.br_white = kosm.hex("b7dce5");
    try app.apply(&fixture.output);
    try testing.expectEqual(0, fixture.warnings.items.items.len);

    const written = fixture.plan.files.items[0].new;
    try testing.expectStringStartsWith(written, "return {\n    transparent = true,\n    base00 = \"#041c26\",\n");
    try testing.expect(std.mem.indexOf(u8, written, "\n    base08 = \"#80333c\",\n") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\n    white = \"#a3c5cc\",\n") != null);
    try testing.expectStringEndsWith(written, "\n    br_white = \"#b7dce5\",\n}\n");
}

test "App{} writes an empty module, and only set values are written" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const empty: App = .{};
    try empty.apply(&fixture.output);
    try testing.expectEqualStrings("return {}\n", fixture.plan.files.items[0].new);

    var app: App = .{};
    app.base16.base0D = kosm.hex("2d8699");
    app.terminal.cyan = kosm.hex("268078");
    const tree_value = try app.tree(fixture.arena.allocator());
    try testing.expectEqual(2, tree_value.table.len);
    try testing.expectEqualStrings("base0D", tree_value.table[0].key);
    try testing.expectEqualStrings("cyan", tree_value.table[1].key);
}

test "extras follow the app's values, nested by path, and a clash fails naming both" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var app: App = .{};
    app.base16.base00 = kosm.hex("041c26");
    app.extra = &.{
        .{ .path = "accent.soft", .value = .{ .color = kosm.hex("2d8699") } },
        .{ .path = "italic_comments", .value = .{ .boolean = true } },
        .{ .path = "accent.strong", .value = .{ .color = kosm.hex("268078") } },
    };
    try app.apply(&fixture.output);
    try testing.expectEqualStrings(
        \\return {
        \\    base00 = "#041c26",
        \\    accent = {
        \\        soft = "#2d8699",
        \\        strong = "#268078",
        \\    },
        \\    italic_comments = true,
        \\}
        \\
    , fixture.plan.files.items[0].new);

    app.extra = &.{.{ .path = "base00.dim", .value = .{ .color = kosm.hex("000000") } }};
    try testing.expectError(error.AppFailed, app.apply(&fixture.output));
    try testing.expectEqualStrings("extra 'base00.dim' and setting 'base00' write the same key, or one inside the other; keep one", fixture.diagnostics.message());
}
