//! Zen Browser's theme colors (D22, D27), generated as `--kosm-*` custom properties into
//! `file`. userChrome.css and userContent.css `@import` it and use them through `var()` (D57).
//! Its about:config prefs go to every profile's `user.js` through `profile` (D94).

const App = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The file kosm owns. Default: `~/.config/ZenBrowser/kosm.css`.
file: []const u8 = "~/.config/ZenBrowser/kosm.css",
/// How values are spelled (D70), e.g. `.color = .hex_upper`. Null fields take the CSS
/// adapter's: `#rrggbbaa`, then kosm's 6 float decimals.
format: kosm.Format = .{},
/// Text and icons (`--kosm-foreground`). null: not written. `from`: white, black in light mode.
foreground: ?kosm.Color = null,
/// Links, focused fields and the selected tab's text (`--kosm-accent`). null: not written.
/// `from`: cyan.
accent: ?kosm.Color = null,
/// Toolbars, sidebar, panels and new tab page (`--kosm-background`). null: not written.
/// `from`: black, white in light mode.
background: ?kosm.Color = null,
/// Buttons and the toolbar (`--kosm-button`). null: not written. `from`: `surface.raised` of
/// `background`.
button: ?kosm.Color = null,
/// Buttons under the pointer (`--kosm-button-hovered`). null: `hovered` of `button` when both
/// are set (D23), else not written.
button_hovered: ?kosm.Color = null,
/// Borders and outlines (`--kosm-border`). null: not written. `from`: cyan.
border: ?kosm.Color = null,
/// Container tab colors (`--kosm-containers-blue`, ...). null ones are not written. `from`:
/// the wheel's hues.
containers: Containers = .{},
/// Makes `button_hovered` from `button` when it is null (D23, D24). null: nothing derived.
/// `from`: the theme's `state.hovered`.
hovered: ?kosm.Modifier = null,
/// Custom properties the app doesn't cover (D99), written after its own, the path's keys joined
/// by `-`: `.{ .path = "kosm.tab.radius", .value = .{ .raw = "8px" } }` is `--kosm-tab-radius`.
/// One whose path equals, contains or lies inside a set color's or another extra's fails the
/// apply. Prefs have their own, `Profile.extra`. Default: none.
extra: []const kosm.Setting = &.{},
/// The about:config prefs every profile gets (D94). null: no prefs, only the CSS, e.g. on a
/// machine without Zen. `from`: `Profile.from(theme)` for every profile.
profile: ?Profile = null,

pub const Containers = @import("Containers.zig");
pub const Profile = @import("Profile.zig");

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
        .profile = .from(theme),
    };
}

/// Writes every set color as a `--kosm-*` custom property, then the prefs of `profile`.
pub fn apply(self: App, output: *kosm.Output) !void {
    const colors = try kosm.Setting.leaves(output.allocator, try self.properties(output.allocator));
    const all = try kosm.Setting.withExtras(output, self.file, colors, self.extra, .{});
    try output.generate(.{ .file = self.file, .lang = "css", .format = self.format }, try kosm.Setting.tree(output.allocator, all));
    if (self.profile) |profile| try profile.apply(output);
}

/// The set colors under `kosm`, which the CSS adapter writes as `--kosm-*` properties.
fn properties(self: App, allocator: std.mem.Allocator) std.mem.Allocator.Error!kosm.Value {
    var colors: std.ArrayList(kosm.Value.Entry) = .empty;
    try appendColors(allocator, &colors, .{
        .foreground = self.foreground,
        .accent = self.accent,
        .background = self.background,
        .button = self.button,
        .button_hovered = self.button_hovered orelse self.derivedButtonHovered(),
        .border = self.border,
    });
    var containers: std.ArrayList(kosm.Value.Entry) = .empty;
    try appendColors(allocator, &containers, self.containers);
    try colors.append(allocator, .{ .key = "containers", .value = .{ .table = containers.items } });
    return .{ .table = try allocator.dupe(kosm.Value.Entry, &.{.{ .key = "kosm", .value = .{ .table = colors.items } }}) };
}

fn appendColors(allocator: std.mem.Allocator, entries: *std.ArrayList(kosm.Value.Entry), colors: anytype) std.mem.Allocator.Error!void {
    inline for (@typeInfo(@TypeOf(colors)).@"struct".field_names) |name| {
        if (@field(colors, name)) |color| try entries.append(allocator, .{ .key = name, .value = .{ .color = color } });
    }
}

fn derivedButtonHovered(self: App) ?kosm.Color {
    const hovered = self.hovered orelse return null;
    const button = self.button orelse return null;
    return hovered.apply(button);
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
    var warnings: kosm.Warnings = .init(arena.allocator());
    var output: kosm.Output = .{
        .allocator = arena.allocator(),
        .home = home,
        .adapters = &.{css.adapter},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .warnings = &warnings,
        .app = "zen",
    };

    const theme = kosm.Theme.from(.{ .black = kosm.hex("041c26"), .white = kosm.hex("a3c5cc"), .cyan = kosm.hex("268078") }, .dark);
    var app = from(theme);
    app.profile = null;
    app.button = kosm.hex("082e3f");
    app.containers.pink = kosm.hex("4d74af");
    try app.apply(&output);
    try testing.expectEqual(0, warnings.items.items.len);

    const written = plan.files.items[0].new;
    try testing.expect(std.mem.startsWith(u8, written, ":root {\n  --kosm-foreground: #a3c5ccff;\n  --kosm-accent: #268078ff;\n"));
    try testing.expect(std.mem.indexOf(u8, written, "\n  --kosm-button: #082e3fff;\n  --kosm-button-hovered: #") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\n  --kosm-containers-pink: #4d74afff;\n") != null);
    try testing.expect(std.mem.endsWith(u8, written, "\n}\n"));
}

test "App{} writes an empty :root and no prefs, and without hovered no hover color is derived" {
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
        .adapters = &.{css.adapter},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .warnings = &warnings,
        .app = "zen",
    };

    const empty: App = .{};
    try empty.apply(&output);
    try testing.expectEqual(1, plan.files.items.len);
    try testing.expectEqualStrings(":root {\n}\n", plan.files.items[0].new);

    const app: App = .{ .button = kosm.hex("082e3f") };
    try testing.expectEqual(null, app.derivedButtonHovered());
}

test "extras follow the colors as custom properties, and a clash fails naming both (D99)" {
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
        .adapters = &.{css.adapter},
        .plan = &plan,
        .diagnostics = &diagnostics,
        .warnings = &warnings,
        .app = "zen",
    };

    var app: App = .{ .accent = kosm.hex("268078"), .containers = .{ .blue = kosm.hex("4d74af") } };
    app.extra = &.{
        .{ .path = "kosm.tab.radius", .value = .{ .raw = "8px" } },
        .{ .path = "zen.colors.primary", .value = .{ .color = kosm.hex("082e3f") } },
    };
    try app.apply(&output);
    try testing.expectEqualStrings(
        \\:root {
        \\  --kosm-accent: #268078ff;
        \\  --kosm-containers-blue: #4d74afff;
        \\  --kosm-tab-radius: 8px;
        \\  --zen-colors-primary: #082e3fff;
        \\}
        \\
    , plan.files.items[0].new);

    app.extra = &.{.{ .path = "kosm.containers", .value = .{ .raw = "none" } }};
    try testing.expectError(error.AppFailed, app.apply(&output));
    try testing.expectEqualStrings("extra 'kosm.containers' and setting 'kosm.containers.blue' write the same key, or one inside the other; keep one (D99)", diagnostics.message());
}
