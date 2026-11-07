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
/// The file that gets a block reading the generated module, `hl.config(require("kosm"))`,
/// appended at its end so kosm's values win (D97). Only with the `.generate` target, which
/// must then write `~/.config/hypr/kosm.lua`. A missing file is left for Hyprland to create,
/// with a warning. Null: no block. Default: `~/.config/hypr/hyprland.lua`.
include: ?[]const u8 = "~/.config/hypr/hyprland.lua",
/// How values are spelled (D70), e.g. `.color = .hex_upper`. Default: `#rrggbbaa` colors, so
/// alpha is kept; null fields take the Lua adapter's, then kosm's.
format: kosm.Format = .{ .color = .hex8 },
/// Derives each inactive color from its active one when it is null and the active one is set
/// (D23), e.g. `general.col.inactive_border` from `general.col.active_border`.
/// Default: the theme's `state.inactive`.
inactive: kosm.Modifier,
/// Settings the app doesn't cover, such as a plugin's (D99), written after its own:
/// `.{ .path = "plugin.dynamic_cursors.length", .value = .{ .integer = 24 } }`. One that
/// overlaps a set option or another extra fails the apply. Default: none.
extra: []const kosm.Setting = &.{},

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
pub const default_target: Target = .{ .generate = default_module };

/// Where `require("kosm")` in the include block finds the generated module.
const default_module = "~/.config/hypr/kosm.lua";

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
const own_fields = [_][]const u8{ "target", "include", "format", "inactive", "extra" };

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

/// Writes every set option to the target. An option Hyprland can't read (an empty gradient)
/// fails the apply, naming it (D93).
pub fn apply(self: App, output: *kosm.Output) !void {
    const file = switch (self.target) {
        .generate => |path| path,
        .edit => |files| files.files,
    };
    // Checked before deriving, so a bad active color is named instead of the inactive copy.
    for (try settings.list(output.allocator, self, &own_fields)) |setting| {
        if (setting.problem) |message| return output.fail(file, "option '{s}': {s}", .{ setting.path, message });
    }
    const set = try self.withExtras(output, file, try settings.list(output.allocator, self.withDerived(), &own_fields));
    switch (self.target) {
        .generate => {
            if (self.include != null and !std.mem.eql(u8, file, default_module))
                return output.fail(self.include.?, "the include block reads require(\"kosm\"), which finds only {s}, not {s}; set include = null and read it yourself", .{ default_module, file });
            try output.generate(.{ .file = file, .lang = "lua", .format = self.format }, try settings.tree(output.allocator, set));
            if (self.include) |include|
                try output.templateBlock(self, .{ .file = include, .id = "hyprland", .text = "hl.config(require(\"kosm\"))\n", .lang = "lua", .missing = .skip });
        },
        .edit => |files| {
            var selection = try output.edit(.{ .files = files.files, .exclude = files.exclude, .lang = "lua", .format = self.format });
            for (set) |setting| try selection.set(setting.path, setting.value);
        },
    }
}

/// `set` followed by the extras (D99), each checked against everything before it.
fn withExtras(self: App, output: *kosm.Output, file: []const u8, set: []const settings.Setting) ![]const settings.Setting {
    var all: std.ArrayList(settings.Setting) = .empty;
    try all.appendSlice(output.allocator, set);
    for (self.extra) |extra| {
        var failure: kosm.Path.Failure = .{};
        const path = kosm.Path.parse(output.allocator, extra.path, &failure) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidKeyPath => return output.fail(file, "extra '{s}', column {d}: {s}", .{ extra.path, failure.column, failure.problem.describe() }),
        };
        const keys = try output.allocator.alloc(?[]const u8, path.segments.len);
        for (path.segments, keys) |segment, *key| key.* = switch (segment) {
            .key => |name| name,
            .any => if (self.target == .generate)
                return output.fail(file, "extra '{s}': '*' matches keys in files kosm edits, and a generated module has none to match", .{extra.path})
            else
                null,
        };
        try all.append(output.allocator, .{ .path = extra.path, .keys = keys, .value = extra.value, .extra = true });
    }
    if (settings.overlap(all.items)) |found| {
        const kind = if (found.other.extra) "extra" else "option";
        return output.fail(file, "extra '{s}' and {s} '{s}' write the same key, or one inside the other; keep one (D99)", .{ found.extra.path, kind, found.other.path });
    }
    return all.items;
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
    return .{ .inactive = .{ .lightness = -0.1 }, .format = .{ .color = .hex }, .include = null };
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

test "hyprland.lua gets a block reading the generated module at its end, once (D97)" {
    const user_config = "hl.config({ general = { gaps_in = 5 } })\n";
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ ".config/hypr/hyprland.lua", user_config },
        .{ ".config/hypr/done.lua", user_config ++ "-- kosm:begin hyprland\nhl.config(require(\"kosm\"))\n-- kosm:end\n" },
    });
    defer fixture.deinit();
    var app = from(kosm.Theme.from(test_palette, .dark));
    try app.apply(&fixture.output);
    try testing.expectEqualStrings(user_config ++ "-- kosm:begin hyprland\nhl.config(require(\"kosm\"))\n-- kosm:end\n", fixture.planned("~/.config/hypr/hyprland.lua"));
    try testing.expectEqual(0, fixture.warnings.items.items.len);

    var second: Fixture = undefined;
    try second.init(&.{.{ ".config/hypr/done.lua", user_config ++ "-- kosm:begin hyprland\nhl.config(require(\"kosm\"))\n-- kosm:end\n" }});
    defer second.deinit();
    app.include = "~/.config/hypr/done.lua";
    try app.apply(&second.output);
    try testing.expectEqualStrings("~/.config/hypr/done.lua", second.plan.files.items[1].display_path);
    try testing.expect(!second.plan.files.items[1].changed());
}

test "a missing hyprland.lua is left for Hyprland to create, with a warning (D97)" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    const app = from(kosm.Theme.from(test_palette, .dark));
    try app.apply(&fixture.output);
    try testing.expectEqual(1, fixture.plan.files.items.len);
    try testing.expectEqualStrings("~/.config/hypr/kosm.lua", fixture.plan.files.items[0].display_path);
    const warnings = fixture.warnings.items.items;
    try testing.expectEqual(1, warnings.len);
    try testing.expectEqualStrings("~/.config/hypr/hyprland.lua", warnings[0].file);
    try testing.expectEqualStrings("does not exist, so block 'hyprland' is not written; apply again once it exists, or add the block's lines yourself:\nhl.config(require(\"kosm\"))", warnings[0].message);
}

test "the include block refuses a module require(\"kosm\") would not find" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    var app = from(kosm.Theme.from(test_palette, .dark));
    app.target = .{ .generate = "~/.config/hypr/theme.lua" };
    try testing.expectError(error.AppFailed, app.apply(&fixture.output));
    try testing.expectEqualStrings("the include block reads require(\"kosm\"), which finds only ~/.config/hypr/kosm.lua, not ~/.config/hypr/theme.lua; set include = null and read it yourself", fixture.diagnostics.message());
    try testing.expectEqual(0, fixture.plan.files.items.len);

    app.include = null;
    try app.apply(&fixture.output);
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

test "choices Hyprland reads as numbers are enums, written as their number" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    var app = bareApp();
    app.target = .{ .generate = "~/kosm.lua" };
    app.general.layout = .{ .lua = "my_layout" };
    app.input.accel_profile = .{ .custom = .{ .step = 0.5, .points = &.{ 0, 0.25, 1.5 } } };
    app.input.scroll_points = .{ .step = 1, .points = &.{ 0, 2 } };
    app.input.float_switch_override_focus = .floating_too;
    app.input.tablet.transform = .flipped_90;
    app.misc.force_default_wallpaper = .random;
    app.scrolling.follow_focus = .soft;
    try app.apply(&fixture.output);
    const written = fixture.planned("~/kosm.lua");
    for ([_][]const u8{
        "        layout = \"lua:my_layout\",\n",
        "        accel_profile = \"custom 0.5 0 0.25 1.5\",\n",
        "        scroll_points = \"1 0 2\",\n",
        "        float_switch_override_focus = 2,\n",
        "        tablet = {\n            transform = 5,\n        },\n",
        "        force_default_wallpaper = -1,\n",
        "    scrolling = {\n        follow_focus = 2,\n    },\n",
    }) |expected| {
        if (std.mem.indexOf(u8, written, expected) == null) {
            std.debug.print("missing:\n{s}\nin:\n{s}\n", .{ expected, written });
            return error.TestExpectedEqual;
        }
    }

    var built_in = bareApp();
    built_in.target = app.target;
    built_in.general.layout = .scrolling;
    built_in.input.accel_profile = .flat;
    var second: Fixture = undefined;
    try second.init(&.{});
    defer second.deinit();
    try built_in.apply(&second.output);
    try testing.expectEqualStrings("return {\n    general = {\n        layout = \"scrolling\",\n    },\n    input = {\n        accel_profile = \"flat\",\n    },\n}\n", second.planned("~/kosm.lua"));
}

test "a gradient Hyprland can't draw fails the apply, naming the option (D93)" {
    const colors: [12]kosm.Color = @splat(kosm.hex("#2e8799"));
    var too_many = bareApp();
    too_many.general.col.active_border = .from(&colors);
    try testing.expectEqual(10, too_many.general.col.active_border.?.colors.len);
    var empty = bareApp();
    empty.target = .{ .edit = .{} };
    empty.decoration.glow.color = .{};

    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    try testing.expectError(error.AppFailed, too_many.apply(&fixture.output));
    try testing.expectEqualStrings("option 'general.col.active_border': the gradient holds 12 colors; Hyprland draws at most 10", fixture.diagnostics.message());
    try testing.expectEqualStrings("~/.config/hypr/kosm.lua", fixture.diagnostics.file);
    try testing.expectError(error.AppFailed, empty.apply(&fixture.output));
    try testing.expectEqualStrings("option 'decoration.glow.color': the gradient has no colors; set at least one", fixture.diagnostics.message());
    try testing.expectEqualStrings("~/.config/hypr/**/*.lua", fixture.diagnostics.file);
    try testing.expectEqual(0, fixture.plan.files.items.len);
}

test "extras land in the generated module's tables beside the options, quoted keys too (D99)" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{});
    defer fixture.deinit();
    var app = bareApp();
    app.target = .{ .generate = "~/kosm.lua" };
    app.general.border_size = 2;
    app.decoration.rounding = 10;
    app.extra = &.{
        .{ .path = "plugin.dynamic_cursors.length", .value = .{ .integer = 24 } },
        .{ .path = "general.future_option", .value = .{ .color = kosm.hex("#2e8799") } },
        .{ .path = "plugin.\"hy.prop\".enabled", .value = .{ .boolean = false } },
    };
    try app.apply(&fixture.output);
    try testing.expectEqualStrings(
        \\return {
        \\    general = {
        \\        border_size = 2,
        \\        future_option = "#2e8799",
        \\    },
        \\    decoration = {
        \\        rounding = 10,
        \\    },
        \\    plugin = {
        \\        dynamic_cursors = {
        \\            length = 24,
        \\        },
        \\        ["hy.prop"] = {
        \\            enabled = false,
        \\        },
        \\    },
        \\}
        \\
    , fixture.planned("~/kosm.lua"));
}

test "the edit target sets extras by path in the user's files (D99)" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{.{ ".config/hypr/plugins.lua", "hl.config({ plugin = { dynamic_cursors = { length = 10 } } })\n" }});
    defer fixture.deinit();
    var app = bareApp();
    app.target = .{ .edit = .{} };
    app.extra = &.{.{ .path = "plugin.*.length", .value = .{ .integer = 24 } }};
    try app.apply(&fixture.output);
    try testing.expectEqualStrings("hl.config({ plugin = { dynamic_cursors = { length = 24 } } })\n", fixture.planned("~/.config/hypr/plugins.lua"));
}

test "an extra overlapping an option or another extra fails naming both (D99)" {
    const cases = [_]struct { extra: []const kosm.Setting, message: []const u8 }{
        .{ .extra = &.{.{ .path = "general.border_size", .value = .{ .integer = 3 } }}, .message = "extra 'general.border_size' and option 'general.border_size' write the same key, or one inside the other; keep one (D99)" },
        .{ .extra = &.{.{ .path = "general.border_size.width", .value = .{ .integer = 3 } }}, .message = "extra 'general.border_size.width' and option 'general.border_size' write the same key, or one inside the other; keep one (D99)" },
        .{ .extra = &.{.{ .path = "general", .value = .{ .table = &.{} } }}, .message = "extra 'general' and option 'general.border_size' write the same key, or one inside the other; keep one (D99)" },
        .{ .extra = &.{ .{ .path = "plugin.a", .value = .{ .integer = 1 } }, .{ .path = "plugin.\"a\".b", .value = .{ .integer = 2 } } }, .message = "extra 'plugin.\"a\".b' and extra 'plugin.a' write the same key, or one inside the other; keep one (D99)" },
        .{ .extra = &.{.{ .path = "plugin.*.length", .value = .{ .integer = 1 } }}, .message = "extra 'plugin.*.length': '*' matches keys in files kosm edits, and a generated module has none to match" },
        .{ .extra = &.{.{ .path = "plugin..length", .value = .{ .integer = 1 } }}, .message = "extra 'plugin..length', column 8: a segment is empty (two dots, or a dot at an end)" },
    };
    for (cases) |case| {
        var fixture: Fixture = undefined;
        try fixture.init(&.{});
        defer fixture.deinit();
        var app = bareApp();
        app.general.border_size = 2;
        app.extra = case.extra;
        try testing.expectError(error.AppFailed, app.apply(&fixture.output));
        try testing.expectEqualStrings(case.message, fixture.diagnostics.message());
        try testing.expectEqual(0, fixture.plan.files.items.len);
    }
}
