//! Hyprland's settings (D22, D27): every `hl.config` option of upstream Hyprland, grouped
//! and named like Hyprland's own options (`general.col.active_border`). Null options are not
//! written, so Hyprland's defaults apply. `target` picks who owns the values (D91).

const App = @This();

const std = @import("std");
const kosm = @import("kosm");
const values = @import("values.zig");
const settings = @import("settings.zig");

/// Where the options go: a Lua module kosm writes whole, or the user's own Lua files (D91).
/// Default: `default_target`.
target: Target = default_target,
/// How values are spelled (D70), e.g. `.color = .hex_upper`. Default: `#rrggbbaa` colors, so
/// alpha is kept; null fields take the Lua adapter's, then kosm's.
format: kosm.Format = .{ .color = .hex8 },
/// Derives each inactive color from its active one when it is null and the active one is set
/// (D23), e.g. `general.col.inactive_border` from `general.col.active_border`.
/// Default: the theme's `state.inactive`.
inactive: kosm.Modifier,

general: General = .{},
decoration: Decoration = .{},
animations: Animations = .{},
input: Input = .{},
gestures: Gestures = .{},
group: Group = .{},
misc: Misc = .{},
layers: Layers = .{},
binds: Binds = .{},
xwayland: Xwayland = .{},
opengl: Opengl = .{},
render: Render = .{},
cursor: Cursor = .{},
ecosystem: Ecosystem = .{},
debug: Debug = .{},
layout: Layout = .{},
dwindle: Dwindle = .{},
master: Master = .{},
scrolling: Scrolling = .{},
experimental: Experimental = .{},
input_capture: InputCapture = .{},
quirks: Quirks = .{},

/// Who owns Hyprland's values (D91).
pub const Target = union(enum) {
    /// Writes every set option to this Lua module, `return { general = { ... } }`, so kosm is
    /// the source of truth. `hyprland.lua` reads it with `hl.config(require("kosm"))` (D57).
    generate: []const u8,
    /// Sets each set option where the user's Lua files already hold it (D25, D30), so they stay
    /// the source of truth. An option they lack must be left null: kosm never inserts keys (D28).
    edit: Files,
};

/// The user's Lua files an `edit` target changes (D79).
pub const Files = @import("Files.zig");

/// The target every app starts with: kosm owns `~/.config/hypr/kosm.lua` (D91). Change it here
/// to make editing the user's files the default.
pub const default_target: Target = .{ .generate = "~/.config/hypr/kosm.lua" };

/// Hyprland's `general` options.
pub const General = @import("sections/General.zig");
/// Hyprland's `decoration` options.
pub const Decoration = @import("sections/Decoration.zig");
/// Hyprland's `animations` options.
pub const Animations = @import("sections/Animations.zig");
/// Hyprland's `input` options.
pub const Input = @import("sections/Input.zig");
/// Hyprland's `gestures` options.
pub const Gestures = @import("sections/Gestures.zig");
/// Hyprland's `group` options.
pub const Group = @import("sections/Group.zig");
/// Hyprland's `misc` options.
pub const Misc = @import("sections/Misc.zig");
/// Hyprland's `layers` options.
pub const Layers = @import("sections/Layers.zig");
/// Hyprland's `binds` options.
pub const Binds = @import("sections/Binds.zig");
/// Hyprland's `xwayland` options.
pub const Xwayland = @import("sections/Xwayland.zig");
/// Hyprland's `opengl` options.
pub const Opengl = @import("sections/Opengl.zig");
/// Hyprland's `render` options.
pub const Render = @import("sections/Render.zig");
/// Hyprland's `cursor` options.
pub const Cursor = @import("sections/Cursor.zig");
/// Hyprland's `ecosystem` options.
pub const Ecosystem = @import("sections/Ecosystem.zig");
/// Hyprland's `debug` options.
pub const Debug = @import("sections/Debug.zig");
/// Hyprland's `layout` options.
pub const Layout = @import("sections/Layout.zig");
/// Hyprland's `dwindle` options.
pub const Dwindle = @import("sections/Dwindle.zig");
/// Hyprland's `master` options.
pub const Master = @import("sections/Master.zig");
/// Hyprland's `scrolling` options.
pub const Scrolling = @import("sections/Scrolling.zig");
/// Hyprland's `experimental` options.
pub const Experimental = @import("sections/Experimental.zig");
/// Hyprland's `input_capture` options.
pub const InputCapture = @import("sections/InputCapture.zig");
/// Hyprland's `quirks` options.
pub const Quirks = @import("sections/Quirks.zig");

/// App fields that are kosm's, not Hyprland options.
const own_fields = [_][]const u8{ "target", "format", "inactive" };

/// Colors from the theme (D27): the active border, glow and groupbar text from the accent
/// (cyan) and the foreground, groups in yellow (locked: orange), windows that can't be grouped in
/// magenta, the shadow from `surface.shadow`, the background behind windows. Inactive colors
/// derive through `inactive`; every other option is left to Hyprland.
pub fn from(theme: kosm.Theme) App {
    const palette = theme.palette;
    const variations = theme.variations;
    const foreground = if (theme.mode == .dark) palette.white else palette.black;
    const background = if (theme.mode == .dark) palette.black else palette.white;
    var app: App = .{ .inactive = variations.state.inactive };

    app.general.col.active_border = .solid(palette.cyan);
    app.general.col.nogroup_border_active = .solid(palette.magenta);
    app.decoration.shadow.color = .solid(variations.surface.shadow.apply(background));
    app.decoration.glow.color = .solid(palette.cyan);
    app.group.col.border_active = .solid(palette.yellow);
    app.group.col.border_locked_active = .solid(palette.orange);
    app.group.groupbar.col.active = .solid(palette.yellow);
    app.group.groupbar.col.locked_active = .solid(palette.orange);
    app.group.groupbar.text_color = foreground;
    app.group.groupbar.text_color_locked_active = foreground;
    app.misc.background_color = background;
    app.misc.col.splash = foreground;
    return app;
}

/// Makes Hyprland re-read its config (D74). Without a running Hyprland, kosm only warns.
pub fn reload(self: App, reloader: *kosm.Reloader) !void {
    _ = self;
    try reloader.run(&.{ "hyprctl", "reload" });
}

/// Writes every set option to the target.
pub fn apply(self: App, output: *kosm.Output) !void {
    const app = self.withDerived();
    switch (self.target) {
        .generate => |file| {
            const tree = try settings.tree(output.allocator, app, &own_fields);
            try output.generate(.{ .file = file, .lang = "lua", .format = self.format }, tree);
        },
        .edit => |files| {
            var selection = try output.edit(.{ .files = files.files, .exclude = files.exclude, .lang = "lua", .format = self.format });
            for (try settings.list(output.allocator, app, &own_fields)) |setting| try selection.set(setting.path, setting.value);
        },
    }
}

/// The app with every null inactive color derived from its set active one (D23).
fn withDerived(self: App) App {
    var app = self;
    const inactive = self.inactive;
    derive(values.Gradient, &app.general.col.inactive_border, app.general.col.active_border, inactive);
    derive(values.Gradient, &app.general.col.nogroup_border, app.general.col.nogroup_border_active, inactive);
    derive(values.Gradient, &app.decoration.shadow.color_inactive, app.decoration.shadow.color, inactive);
    derive(values.Gradient, &app.decoration.glow.color_inactive, app.decoration.glow.color, inactive);
    derive(values.Gradient, &app.group.col.border_inactive, app.group.col.border_active, inactive);
    derive(values.Gradient, &app.group.col.border_locked_inactive, app.group.col.border_locked_active, inactive);
    derive(values.Gradient, &app.group.groupbar.col.inactive, app.group.groupbar.col.active, inactive);
    derive(values.Gradient, &app.group.groupbar.col.locked_inactive, app.group.groupbar.col.locked_active, inactive);
    derive(kosm.Color, &app.group.groupbar.text_color_inactive, app.group.groupbar.text_color, inactive);
    derive(kosm.Color, &app.group.groupbar.text_color_locked_inactive, app.group.groupbar.text_color_locked_active, inactive);
    return app;
}

fn derive(comptime T: type, inactive_slot: *?T, active: ?T, inactive: kosm.Modifier) void {
    if (inactive_slot.* != null) return;
    const color = active orelse return;
    inactive_slot.* = if (T == kosm.Color) inactive.apply(color) else color.modified(inactive);
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

    fn init(fixture: *Fixture, files: []const [2][]const u8) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        for (files) |file| {
            if (std.Io.Dir.path.dirname(file[0])) |parent| try fixture.tmp.dir.createDirPath(testing.io, parent);
            try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
        }
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{lua.adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "hyprland",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn planned(fixture: *Fixture, display_path: []const u8) []const u8 {
        for (fixture.plan.files.items) |file| {
            if (std.mem.eql(u8, file.display_path, display_path)) return file.new;
        }
        return "(not planned)";
    }
};

const test_palette: kosm.Palette = .{
    .black = kosm.hex("#041c26"),
    .white = kosm.hex("#dce9ee"),
    .cyan = kosm.hex("#2e8799"),
    .yellow = kosm.hex("#ebcb8b"),
    .orange = kosm.hex("#d08770"),
    .magenta = kosm.hex("#b48ead"),
};

/// An app with only the options a test sets, written as plain hex colors.
fn bareApp() App {
    return .{ .inactive = .{ .lightness = -0.1 }, .format = .{ .color = .hex } };
}

test "from writes Hyprland's own shape to the generated module, inactive colors derived" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    var app = from(kosm.Theme.from(test_palette, .dark));
    app.decoration.blur.size = 20;
    app.decoration.blur.variant = .frost;
    try app.apply(&fixture.output);
    const written = fixture.planned("~/.config/hypr/kosm.lua");
    try testing.expectStringStartsWith(written,
        \\return {
        \\    general = {
        \\        col = {
        \\            inactive_border = "#
    );
    for ([_][]const u8{
        "            active_border = \"#2e8799ff\",\n",
        "            nogroup_border_active = \"#b48eadff\",\n",
        "    decoration = {\n        shadow = {\n            color = \"#",
        "        glow = {\n            color = \"#2e8799ff\",\n            color_inactive = \"#",
        "        blur = {\n            variant = \"frost\",\n            size = 20,\n        },\n",
        "            border_locked_active = \"#d08770ff\",\n",
        "            text_color = \"#dce9eeff\",\n",
        "        background_color = \"#041c26ff\",\n",
        "        col = {\n            splash = \"#dce9eeff\",\n        },\n",
    }) |expected| {
        if (std.mem.indexOf(u8, written, expected) == null) {
            std.debug.print("missing:\n{s}\nin:\n{s}\n", .{ expected, written });
            return error.TestExpectedEqual;
        }
    }
    try testing.expect(std.mem.indexOf(u8, written, "input") == null);
}

test "an inactive color follows its active one unless set, and a changed active one flows (D23)" {
    var app = bareApp();
    app.general.col.active_border = .solid(kosm.hex("#808080"));
    app.group.groupbar.text_color = kosm.hex("#808080");
    app.decoration.glow.color = .solid(kosm.hex("#808080"));
    app.decoration.glow.color_inactive = .solid(kosm.hex("#ff0000"));
    const derived = app.withDerived();
    const darker = app.inactive.apply(kosm.hex("#808080"));
    try testing.expectEqual(darker, derived.general.col.inactive_border.?.colors[0].?);
    try testing.expectEqual(darker, derived.group.groupbar.text_color_inactive.?);
    try testing.expectEqual(kosm.hex("#ff0000"), derived.decoration.glow.color_inactive.?.colors[0].?);
    try testing.expectEqual(null, derived.group.col.border_inactive);

    app.general.col.active_border = .solid(kosm.hex("#ffffff"));
    try testing.expectEqual(app.inactive.apply(kosm.hex("#ffffff")), app.withDerived().general.col.inactive_border.?.colors[0].?);
}

test "values are written the way Hyprland's Lua config reads them" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    var app = bareApp();
    app.target = .{ .generate = "~/kosm.lua" };
    app.general.col.active_border = .from(&.{ kosm.hex("#2e8799"), kosm.hex("#ffffff") });
    app.general.col.active_border.?.angle = 45;
    app.general.col.inactive_border = .solid(kosm.hex("#000000"));
    app.general.gaps_in = .all(5);
    app.general.gaps_out = .{ .top = 10, .right = 20, .bottom = 10, .left = 20 };
    app.general.resize_corner = .top_left;
    app.decoration.shadow.offset = .{ .x = 0, .y = 2.5 };
    app.group.groupbar.font_weight_active = .{ .name = .semibold };
    app.group.groupbar.font_weight_inactive = .{ .weight = 450 };
    app.cursor.no_hardware_cursors = .enabled;
    app.input.touchpad.drag_3fg = .@"3_finger";
    app.input.touchpad.tap_to_click = false;
    app.input_capture.capture_modifiers = true;
    app.master.orientation = .center;
    try app.apply(&fixture.output);
    try testing.expectEqualStrings(
        \\return {
        \\    general = {
        \\        gaps_in = 5,
        \\        gaps_out = {
        \\            top = 10,
        \\            right = 20,
        \\            bottom = 10,
        \\            left = 20,
        \\        },
        \\        col = {
        \\            inactive_border = "#000000",
        \\            active_border = {
        \\                colors = { "#2e8799", "#ffffff" },
        \\                angle = 45,
        \\            },
        \\        },
        \\        resize_corner = "top_left",
        \\    },
        \\    decoration = {
        \\        shadow = {
        \\            offset = { 0, 2.5 },
        \\        },
        \\    },
        \\    input = {
        \\        touchpad = {
        \\            tap_to_click = false,
        \\            drag_3fg = "3_finger",
        \\        },
        \\    },
        \\    group = {
        \\        groupbar = {
        \\            font_weight_active = "semibold",
        \\            font_weight_inactive = 450,
        \\        },
        \\    },
        \\    cursor = {
        \\        no_hardware_cursors = 1,
        \\    },
        \\    master = {
        \\        orientation = "center",
        \\    },
        \\    input_capture = {
        \\        capture_modifiers = true,
        \\    },
        \\}
        \\
    , fixture.planned("~/kosm.lua"));
}

const general_lua =
    \\local defs = require("defs")
    \\
    \\hl.config({
    \\    general = {
    \\        layout        = "scrolling",
    \\        allow_tearing = true,
    \\
    \\        -- Border
    \\        border_size             = defs.border.size,
    \\        resize_on_border        = true,
    \\
    \\        -- Border colors
    \\        col = {
    \\            inactive_border       = defs.border.inactive_col,
    \\            active_border         = { colors = { "#2E8799", "#2E8799" } },
    \\        },
    \\
    \\        snap = {
    \\            enabled      = true,
    \\            window_gap   = 10,
    \\        }
    \\    }
    \\})
    \\
;

const blur_lua =
    \\local defs = require("defs")
    \\
    \\hl.config({
    \\    decoration = {
    \\        blur = {
    \\            enabled = defs.blur.enabled,
    \\            size    = defs.blur.size,
    \\            variant = "frost",
    \\
    \\            aurora = {
    \\                color1 = "#2E8799AA",
    \\            },
    \\        },
    \\    }
    \\})
    \\
    \\hl.animation(defs.animations.windows)
    \\hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close" })
    \\
;

test "the edit target sets options in the user's files, however they are split" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ ".config/hypr/hyprland/general.lua", general_lua },
        .{ ".config/hypr/hyprland/decoration/blur.lua", blur_lua },
        .{ ".config/hypr/hyprland.lua", "require(\"hyprland.general\")\nrequire(\"hyprland.decoration.blur\")\n" },
    });
    defer fixture.deinit();
    var app = bareApp();
    app.target = .{ .edit = .{} };
    app.general.col.active_border = .from(&.{ kosm.hex("#5e81ac"), kosm.hex("#88c0d0") });
    app.general.border_size = 2;
    app.general.snap.window_gap = 5;
    app.decoration.blur.size = 8;
    app.decoration.blur.variant = .aurora;
    app.decoration.blur.aurora.color1 = kosm.hex("#bf616a");
    try app.apply(&fixture.output);

    try testing.expectEqualStrings(
        \\local defs = require("defs")
        \\
        \\hl.config({
        \\    general = {
        \\        layout        = "scrolling",
        \\        allow_tearing = true,
        \\
        \\        -- Border
        \\        border_size             = 2,
        \\        resize_on_border        = true,
        \\
        \\        -- Border colors
        \\        col = {
        \\            inactive_border       = { colors = { "#42648d", "#69a0b0" } },
        \\            active_border         = { colors = { "#5e81ac", "#88c0d0" } },
        \\        },
        \\
        \\        snap = {
        \\            enabled      = true,
        \\            window_gap   = 5,
        \\        }
        \\    }
        \\})
        \\
    , fixture.planned("~/.config/hypr/hyprland/general.lua"));
    try testing.expectEqualStrings(
        \\local defs = require("defs")
        \\
        \\hl.config({
        \\    decoration = {
        \\        blur = {
        \\            enabled = defs.blur.enabled,
        \\            size    = 8,
        \\            variant = "aurora",
        \\
        \\            aurora = {
        \\                color1 = "#bf616a",
        \\            },
        \\        },
        \\    }
        \\})
        \\
        \\hl.animation(defs.animations.windows)
        \\hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close" })
        \\
    , fixture.planned("~/.config/hypr/hyprland/decoration/blur.lua"));
}

test "the edit target refuses an option the user's files lack, or hold twice" {
    const files = [_][2][]const u8{
        .{ ".config/hypr/general.lua", general_lua },
        .{ ".config/hypr/override.lua", "hl.config({ general = { border_size = 3 } })\n" },
    };
    var app = bareApp();
    app.target = .{ .edit = .{} };
    app.general.allow_tearing = false;
    app.decoration.rounding = 10;
    {
        var fixture: Fixture = undefined;
        try fixture.init(&files);
        defer fixture.deinit();
        try testing.expectError(error.NoMatch, app.apply(&fixture.output));
        try testing.expectEqualStrings("path 'decoration.rounding' matches nothing; kosm never inserts keys (D28)", fixture.diagnostics.message());
    }
    app.decoration.rounding = null;
    app.general.border_size = 2;
    {
        var fixture: Fixture = undefined;
        try fixture.init(&files);
        defer fixture.deinit();
        try testing.expectError(error.TooManyMatches, app.apply(&fixture.output));
    }
    app.target = .{ .edit = .{ .exclude = &.{"~/.config/hypr/override.lua"} } };
    {
        var fixture: Fixture = undefined;
        try fixture.init(&files);
        defer fixture.deinit();
        try app.apply(&fixture.output);
        try testing.expect(std.mem.indexOf(u8, fixture.planned("~/.config/hypr/general.lua"), "border_size             = 2,") != null);
    }
}
