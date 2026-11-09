//! Turns the app's options into the `kosm.Value` tree the ghostty adapter writes: one
//! entry per line, keyed by ghostty's option name (`font_family` -> `font-family`). Null options
//! and empty lists are left out, so the file only holds what the kosmos set.

const std = @import("std");
const kosm = @import("kosm");
const values = @import("values.zig");
const Joined = @import("Joined.zig");

const Allocator = std.mem.Allocator;
const Entry = kosm.Value.Entry;

/// App fields that are kosm's, not ghostty options.
const own_fields = [_][]const u8{ "file", "format", "bright", "keybind_clear", "extra" };

/// One entry per line of the file, in the order `App` declares its options. Lists repeat their
/// key; `palette` writes `N=color` per set index; `keybind_clear` writes `keybind = clear` first.
pub fn tree(allocator: Allocator, app: anytype) Allocator.Error!kosm.Value {
    // Walking ghostty's 211 options takes more than the default quota.
    @setEvalBranchQuota(20_000);
    var entries: std.ArrayList(Entry) = .empty;
    inline for (@typeInfo(@TypeOf(app)).@"struct".field_names) |name| {
        if (comptime isOwnField(name)) continue;
        const key = comptime optionName(name);
        const option = @field(app, name);
        if (comptime std.mem.eql(u8, name, "palette")) {
            try appendPalette(allocator, &entries, option);
        } else if (comptime std.mem.eql(u8, name, "keybind")) {
            try appendKeybinds(allocator, &entries, app.keybind_clear, option);
        } else if (@typeInfo(@TypeOf(option)) == .optional) {
            if (option) |present| try entries.append(allocator, .{ .key = key, .value = try value(allocator, present) });
        } else {
            for (option) |item| try entries.append(allocator, .{ .key = key, .value = try value(allocator, item) });
        }
    }
    return .{ .table = entries.items };
}

fn appendPalette(allocator: Allocator, entries: *std.ArrayList(Entry), palette: anytype) Allocator.Error!void {
    for (palette, 0..) |maybe_color, index| {
        const color = maybe_color orelse continue;
        const parts = try allocator.alloc(kosm.Value, 2);
        parts[0] = .{ .raw = try allocator.print("{d}=", .{index}) };
        parts[1] = .{ .color = color };
        try entries.append(allocator, .{ .key = "palette", .value = .{ .joined = parts } });
    }
}

fn appendKeybinds(allocator: Allocator, entries: *std.ArrayList(Entry), clear: bool, keybinds: []const values.Keybind) Allocator.Error!void {
    if (clear) try entries.append(allocator, .{ .key = "keybind", .value = .{ .raw = "clear" } });
    for (keybinds) |keybind| {
        try entries.append(allocator, .{ .key = "keybind", .value = try joinedValue(allocator, keybind) });
        for (keybind.chain) |action| {
            var joined: Joined = .init(allocator);
            values.Keybind.writeChained(action, &joined) catch return error.OutOfMemory;
            try entries.append(allocator, .{ .key = "keybind", .value = joined.finish() catch return error.OutOfMemory });
        }
    }
}

/// One option's value: scalars stay scalars, compound values are joined so numbers,
/// booleans and colors follow the file's format, and a list is written comma-separated.
fn value(allocator: Allocator, option: anytype) Allocator.Error!kosm.Value {
    const T = @TypeOf(option);
    if (T == kosm.Color) return .{ .color = option };
    if (T == []const u8) return .{ .string = option };
    if (comptime std.meta.hasMethod(T, "write")) return joinedValue(allocator, option);
    if (comptime std.meta.hasMethod(T, "format")) return .{ .raw = try allocator.print("{f}", .{option}) };
    switch (@typeInfo(T)) {
        .bool => return .{ .boolean = option },
        // A u64 limit can be larger than `Value.integer` holds; ghostty takes the digits either way.
        .int => return if (std.math.cast(i64, option)) |integer| .{ .integer = integer } else .{ .raw = try allocator.print("{d}", .{option}) },
        .float => return .{ .float = option },
        .@"enum" => return .{ .raw = try tagText(allocator, T, @tagName(option)) },
        .@"union" => switch (option) {
            inline else => |payload, tag| {
                if (@TypeOf(payload) == void) return .{ .raw = try tagText(allocator, T, @tagName(tag)) };
                return value(allocator, payload);
            },
        },
        .pointer => return commaSeparated(allocator, option),
        else => @compileError("kosm_ghostty: an option of type " ++ @typeName(T) ++ " needs a write or format method"),
    }
}

fn joinedValue(allocator: Allocator, option: anytype) Allocator.Error!kosm.Value {
    var joined: Joined = .init(allocator);
    option.write(&joined) catch return error.OutOfMemory;
    return joined.finish() catch error.OutOfMemory;
}

fn commaSeparated(allocator: Allocator, items: anytype) Allocator.Error!kosm.Value {
    const parts = try allocator.alloc(kosm.Value, if (items.len == 0) 0 else items.len * 2 - 1);
    for (items, 0..) |item, index| {
        if (index != 0) parts[index * 2 - 1] = .{ .raw = "," };
        parts[index * 2] = try value(allocator, item);
    }
    return .{ .joined = parts };
}

fn tagText(allocator: Allocator, comptime T: type, name: []const u8) Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    values.writeTag(&text.writer, name, @hasDecl(T, "underscored")) catch return error.OutOfMemory;
    return text.written();
}

/// Whether the app field `name` is kosm's rather than a ghostty option.
pub fn isOwnField(comptime name: []const u8) bool {
    for (own_fields) |own| {
        if (std.mem.eql(u8, own, name)) return true;
    }
    return false;
}

/// The ghostty option an app field writes: `font_family` is `font-family`.
pub fn optionName(comptime name: []const u8) []const u8 {
    comptime {
        var text: [name.len]u8 = undefined;
        for (name, &text) |byte, *slot| slot.* = if (byte == '_') '-' else byte;
        const final = text;
        return &final;
    }
}

const testing = std.testing;
const adapter = @import("adapter.zig").adapter;

/// `option` as the ghostty adapter writes it in a file with `format`.
fn rendered(allocator: Allocator, option: anytype, format: kosm.Format) ![]const u8 {
    var context: kosm.Adapter.Context = .{ .format = format.orElse(adapter.default_format).resolve() };
    return renderedValue(allocator, try value(allocator, option), &context);
}

fn renderedValue(allocator: Allocator, option: kosm.Value, context: *kosm.Adapter.Context) ![]const u8 {
    const root: kosm.Value = .{ .table = &.{.{ .key = "option", .value = option }} };
    var text: std.Io.Writer.Allocating = .init(allocator);
    try adapter.serialize.?(&text.writer, root, context);
    const line = text.written();
    return line["option = ".len .. line.len - 1];
}

test "only set options are written, under ghostty's names and spellings" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const Options = struct {
        file: []const u8 = "ignored",
        keybind_clear: bool = false,
        font_family: []const []const u8 = &.{},
        font_size: ?f64 = null,
        alpha_blending: ?enum { native, linear, linear_corrected } = null,
        cursor_style: ?enum {
            block,
            block_hollow,
            pub const underscored = true;
        } = null,
        cursor_color: ?values.CellColor = null,
        confirm_close_surface: ?union(enum) { boolean: bool, always } = null,
        osc_color_report_format: ?enum { none, @"8_bit", @"16_bit" } = null,
        macos_icon_screen_color: ?[]const kosm.Color = null,
        title: ?[]const u8 = null,
        palette: [256]?kosm.Color = @splat(null),
        keybind: []const values.Keybind = &.{},
    };
    var options: Options = .{
        .font_family = &.{ "Maple Mono", "Adwaita Mono" },
        .alpha_blending = .linear_corrected,
        .cursor_style = .block_hollow,
        .cursor_color = .cell_foreground,
        .confirm_close_surface = .{ .boolean = false },
        .osc_color_report_format = .@"8_bit",
        .macos_icon_screen_color = &.{ kosm.hex("000000"), kosm.hex("ffffff") },
    };
    options.palette[3] = kosm.hex("668033");
    const result = try tree(arena.allocator(), options);
    const entries = result.table;
    try testing.expectEqual(9, entries.len);
    try testing.expectEqualStrings("font-family", entries[0].key);
    try testing.expectEqualStrings("Adwaita Mono", entries[1].value.string);
    try testing.expectEqualStrings("alpha-blending", entries[2].key);
    try testing.expectEqualStrings("linear-corrected", entries[2].value.raw);
    try testing.expectEqualStrings("block_hollow", entries[3].value.raw);
    try testing.expectEqualStrings("cell-foreground", entries[4].value.raw);
    try testing.expect(!entries[5].value.boolean);
    try testing.expectEqualStrings("8-bit", entries[6].value.raw);
    var context: kosm.Adapter.Context = .{ .format = adapter.default_format.resolve() };
    try testing.expectEqualStrings("#000000,#ffffff", try renderedValue(arena.allocator(), entries[7].value, &context));
    try testing.expectEqualStrings("palette", entries[8].key);
    try testing.expectEqualStrings("3=#668033", try renderedValue(arena.allocator(), entries[8].value, &context));
}

test "keybinds write their prefixes, table and chained actions in order, after a clear" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const Options = struct { keybind_clear: bool, keybind: []const values.Keybind };
    const result = try tree(allocator, Options{ .keybind_clear = true, .keybind = &.{
        .{ .trigger = "ctrl+enter", .action = .unbind },
        .{ .trigger = "ctrl+a>n", .action = .new_window, .chain = &.{ .{ .goto_split = .left }, .toggle_fullscreen } },
        .{ .trigger = "ctrl+shift+d", .action = .{ .new_split = .right }, .global = true, .unconsumed = true },
        .{ .table = "vim", .trigger = "j", .action = .{ .scroll_page_lines = 1 } },
        .{ .trigger = "ctrl+u", .action = .{ .text = "\x15 \"x\"" } },
        .{ .trigger = "ctrl+equal", .action = .{ .increase_font_size = 1.5 } },
        .{ .trigger = "ctrl+shift+j", .action = .{ .write_screen_file = .{ .action = .paste, .format = .plain } } },
        .{ .trigger = "super+up", .action = .{ .resize_split = .{ .direction = .up, .pixels = 10 } } },
        .{ .trigger = "ctrl+x", .action = .{ .raw = "future_action:argument" } },
    } });
    var context: kosm.Adapter.Context = .{ .format = adapter.default_format.resolve() };
    const expected = [_][]const u8{
        "clear",
        "ctrl+enter=unbind",
        "ctrl+a>n=new_window",
        "chain=goto_split:left",
        "chain=toggle_fullscreen",
        "global:unconsumed:ctrl+shift+d=new_split:right",
        "vim/j=scroll_page_lines:1",
        "ctrl+u=text:\\x15 \\\"x\\\"",
        "ctrl+equal=increase_font_size:1.5",
        "ctrl+shift+j=write_screen_file:paste,plain",
        "super+up=resize_split:up,10",
        "ctrl+x=future_action:argument",
    };
    try testing.expectEqual(expected.len, result.table.len);
    for (expected, result.table) |line, entry| {
        try testing.expectEqualStrings("keybind", entry.key);
        try testing.expectEqualStrings(line, try renderedValue(allocator, entry.value, &context));
    }
}

test "structured values are written in ghostty's syntax" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testing.expectEqualStrings("bold,no-italic", try rendered(allocator, values.SyntheticStyle{ .bold = true, .italic = false }, .{}));
    try testing.expectEqualStrings("no-system,audio,no-border", try rendered(allocator, values.BellFeatures{ .system = false, .audio = true, .border = false }, .{}));
    try testing.expectEqualStrings("ssh-env,no-ssh-terminfo", try rendered(allocator, values.ShellIntegrationFeatures{ .ssh_env = true, .ssh_terminfo = false }, .{}));
    try testing.expectEqualStrings("1h30m", try rendered(allocator, values.Duration{ .hours = 1, .minutes = 30 }, .{}));
    try testing.expectEqualStrings("750ms", try rendered(allocator, values.Duration{ .milliseconds = 750 }, .{}));
    try testing.expectEqualStrings("0ms", try rendered(allocator, values.Duration{}, .{}));
    try testing.expectEqualStrings("-1", try rendered(allocator, values.Adjustment{ .pixels = -1 }, .{}));
    try testing.expectEqualStrings("20%", try rendered(allocator, values.Adjustment{ .percent = 20 }, .{}));
    try testing.expectEqualStrings("10", try rendered(allocator, values.Padding.all(10), .{}));
    try testing.expectEqualStrings("2,4", try rendered(allocator, values.Padding{ .start = 2, .end = 4 }, .{}));
    try testing.expectEqualStrings("wght=800", try rendered(allocator, values.FontVariation{ .axis = "wght", .value = 800 }, .{}));
    const symbols: values.CodepointMap = .{ .codepoints = &.{ .{ .first = 0xe0a0, .last = 0xe0a3 }, .{ .first = 0x2665 } }, .font = "Symbols Nerd Font" };
    try testing.expectEqualStrings("U+E0A0-U+E0A3,U+2665=Symbols Nerd Font", try rendered(allocator, symbols, .{}));
    try testing.expectEqualStrings("U+03A3=SUM", try rendered(allocator, values.ClipboardCodepointMap{ .codepoints = .{ .first = 0x3a3 }, .replacement = .{ .text = "SUM" } }, .{}));
    try testing.expectEqualStrings("U+2500=U+002D", try rendered(allocator, values.ClipboardCodepointMap{ .codepoints = .{ .first = 0x2500 }, .replacement = .{ .codepoint = '-' } }, .{}));
    try testing.expectEqualStrings("light:Rose Pine Dawn,dark:Rose Pine", try rendered(allocator, values.Theme{ .light_dark = .{ .light = "Rose Pine Dawn", .dark = "Rose Pine" } }, .{}));
    try testing.expectEqualStrings("Rose Pine", try rendered(allocator, values.Theme{ .name = "Rose Pine" }, .{}));
    try testing.expectEqualStrings("precision:0.1,discrete:3", try rendered(allocator, values.MouseScrollMultiplier{ .precision = 0.1, .discrete = 3 }, .{}));
    try testing.expectEqualStrings("discrete:3", try rendered(allocator, values.MouseScrollMultiplier{ .discrete = 3 }, .{}));
    try testing.expectEqualStrings("50%,500px", try rendered(allocator, values.QuickTerminalSize{ .primary = .{ .percent = 50 }, .secondary = .{ .pixels = 500 } }, .{}));
    try testing.expectEqualStrings("EDITOR=nvim", try rendered(allocator, values.Env{ .name = "EDITOR", .value = "nvim" }, .{}));
    try testing.expectEqualStrings("left_ctrl=right_alt", try rendered(allocator, values.KeyRemap{ .from = .left_ctrl, .to = .right_alt }, .{}));
    try testing.expectEqualStrings("raw:echo \\x1b[0m\\n", try rendered(allocator, values.Input{ .raw = "echo \x1b[0m\n" }, .{}));
    try testing.expectEqualStrings("path:/tmp/greeting", try rendered(allocator, values.Input{ .path = "/tmp/greeting" }, .{}));
    try testing.expectEqualStrings("false", try rendered(allocator, @as(values.FontStyle, .disabled), .{}));
    try testing.expectEqualStrings("unlimited", try rendered(allocator, @as(values.Limit, .unlimited), .{}));
    try testing.expectEqualStrings("10000", try rendered(allocator, values.Limit{ .amount = 10000 }, .{}));
    try testing.expectEqualStrings("macos-glass-clear", try rendered(allocator, @as(values.BackgroundBlur, .macos_glass_clear), .{}));
    try testing.expectEqualStrings("20", try rendered(allocator, values.BackgroundBlur{ .intensity = 20 }, .{}));
    try testing.expectEqualStrings("~/code", try rendered(allocator, values.WorkingDirectory{ .path = "~/code" }, .{}));
    try testing.expectEqualStrings("bright", try rendered(allocator, @as(values.BoldColor, .bright), .{}));
}

test "a command palette entry quotes every field as a Zig string" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const reset: values.CommandPaletteEntry = .{ .title = "Reset \"Style\"", .description = "Send SGR 0", .action = .{ .csi = "0m" } };
    try testing.expectEqualStrings("title:\"Reset \\\"Style\\\"\",description:\"Send SGR 0\",action:\"csi:0m\"", try rendered(allocator, reset, .{}));
    const greet: values.CommandPaletteEntry = .{ .title = "Greet", .action = .{ .text = "hi\n" } };
    try testing.expectEqualStrings("title:\"Greet\",action:\"text:hi\\\\n\"", try rendered(allocator, greet, .{}));
}

test "compound values follow the file's float precision" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const format: kosm.Format = .{ .float_precision = 1 };
    try testing.expectEqualStrings("12.5%", try rendered(allocator, values.Adjustment{ .percent = 12.46 }, format));
    try testing.expectEqualStrings("wght=380.3", try rendered(allocator, values.FontVariation{ .axis = "wght", .value = 380.25 }, format));
    try testing.expectEqualStrings("precision:0.3", try rendered(allocator, values.MouseScrollMultiplier{ .precision = 0.25 }, format));
    const keybind: values.Keybind = .{ .trigger = "ctrl+equal", .action = .{ .increase_font_size = 1.25 } };
    try testing.expectEqualStrings("ctrl+equal=increase_font_size:1.3", try rendered(allocator, keybind, format));
}
