//! Turns the app's sections into the `kosm.Value` tree the kitty adapter writes (D64): one
//! table per section, keyed by kitty's option names. Null options are left out, so the
//! file only holds what the kosmos set (D27).

const std = @import("std");
const kosm = @import("kosm");
const values = @import("values.zig");

const Allocator = std.mem.Allocator;
const Entry = kosm.Value.Entry;

/// Builds one table per field of `sections`, a struct of section structs.
pub fn tree(allocator: Allocator, sections: anytype) Allocator.Error!kosm.Value {
    const names = @typeInfo(@TypeOf(sections)).@"struct".field_names;
    const tables = try allocator.alloc(Entry, names.len);
    inline for (names, tables) |name, *table| {
        table.* = .{ .key = name, .value = try section(allocator, @field(sections, name)) };
    }
    return .{ .table = tables };
}

/// The options of one section that are set, in declaration order.
fn section(allocator: Allocator, options: anytype) Allocator.Error!kosm.Value {
    const Section = @TypeOf(options);
    comptime checkNames(Section, "repeated");
    comptime checkNames(Section, "comma_separated");
    var entries: std.ArrayList(Entry) = .empty;
    inline for (@typeInfo(Section).@"struct".field_names) |name| {
        const option = @field(options, name);
        if (comptime isListed(Section, "repeated", name)) {
            for (option) |item| try entries.append(allocator, .{ .key = name, .value = try value(allocator, item) });
        } else if (option) |present| {
            const written = if (comptime isListed(Section, "comma_separated", name))
                try commaSeparated(allocator, present)
            else
                try value(allocator, present);
            try entries.append(allocator, .{ .key = name, .value = written });
        }
    }
    return .{ .table = entries.items };
}

/// One option's value: scalars stay scalars, so colors keep the file's color format (D61).
fn value(allocator: Allocator, option: anytype) Allocator.Error!kosm.Value {
    const T = @TypeOf(option);
    if (T == kosm.Color) return .{ .color = option };
    if (T == []const u8) return .{ .string = option };
    if (comptime std.meta.hasMethod(T, "format")) return .{ .raw = try allocator.print("{f}", .{option}) };
    switch (@typeInfo(T)) {
        .bool => return .{ .boolean = option },
        .int => return .{ .integer = option },
        .float => return .{ .float = option },
        .@"enum" => return .{ .raw = try tagText(allocator, T, @tagName(option)) },
        .@"union" => switch (option) {
            inline else => |payload, tag| {
                if (@TypeOf(payload) == void) return .{ .raw = try tagText(allocator, T, @tagName(tag)) };
                return value(allocator, payload);
            },
        },
        .pointer => {
            const items = try allocator.alloc(kosm.Value, option.len);
            for (option, items) |item, *slot| slot.* = try value(allocator, item);
            return .{ .list = items };
        },
        else => @compileError("kosm_kitty: an option of type " ++ @typeName(T) ++ " needs a format method"),
    }
}

/// A list of enums joined by commas, as `enabled_layouts` takes it.
fn commaSeparated(allocator: Allocator, items: anytype) Allocator.Error!kosm.Value {
    var text: std.Io.Writer.Allocating = .init(allocator);
    for (items, 0..) |item, index| {
        if (index != 0) text.writer.writeByte(',') catch return error.OutOfMemory;
        values.writeTag(&text.writer, @tagName(item), @hasDecl(@TypeOf(item), "underscored")) catch return error.OutOfMemory;
    }
    return .{ .raw = text.written() };
}

fn tagText(allocator: Allocator, comptime T: type, name: []const u8) Allocator.Error![]const u8 {
    if (@hasDecl(T, "underscored")) return name;
    const text = try allocator.dupe(u8, name);
    std.mem.replaceScalar(u8, text, '_', '-');
    return text;
}

fn isListed(comptime Section: type, comptime list: []const u8, comptime name: []const u8) bool {
    if (!@hasDecl(Section, list)) return false;
    for (@field(Section, list)) |listed| {
        if (std.mem.eql(u8, listed, name)) return true;
    }
    return false;
}

fn checkNames(comptime Section: type, comptime list: []const u8) void {
    if (!@hasDecl(Section, list)) return;
    for (@field(Section, list)) |listed| {
        if (!@hasField(Section, listed)) @compileError(@typeName(Section) ++ "." ++ list ++ " names no option '" ++ listed ++ "'");
    }
}

const testing = std.testing;

test "only set options are written, under kitty's names and spellings" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const Cursor = struct {
        cursor_shape: ?enum { block, beam } = null,
        cursor_trail: ?u32 = null,
        undercurl_style: ?enum { thin_sparse, thick_dense } = null,
        padding_fill_strategy: ?enum {
            background,
            neighboring_cell,
            pub const underscored = true;
        } = null,
        cursor: ?values.ColorOrNone = null,
        scrollbar_handle_color: ?values.ScrollbarColor = null,
        window_border_width: ?values.Length = null,
    };
    const result = try tree(arena.allocator(), .{ .cursor = Cursor{
        .cursor_trail = 1,
        .undercurl_style = .thin_sparse,
        .padding_fill_strategy = .neighboring_cell,
        .cursor = .none,
        .scrollbar_handle_color = .selection_background,
        .window_border_width = .{ .pixels = 2 },
    } });
    const entries = result.table[0].value.table;
    try testing.expectEqualStrings("cursor", result.table[0].key);
    try testing.expectEqual(6, entries.len);
    try testing.expectEqualStrings("cursor_trail", entries[0].key);
    try testing.expectEqual(1, entries[0].value.integer);
    try testing.expectEqualStrings("thin-sparse", entries[1].value.raw);
    try testing.expectEqualStrings("neighboring_cell", entries[2].value.raw);
    try testing.expectEqualStrings("none", entries[3].value.raw);
    try testing.expectEqualStrings("selection_background", entries[4].value.raw);
    try testing.expectEqualStrings("2px", entries[5].value.raw);
}

test "repeated options become one entry each, comma lists one joined entry" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const Section = struct {
        env: []const values.Env = &.{},
        enabled_layouts: ?[]const values.Layout = null,
        url_prefixes: ?[]const []const u8 = null,
        pub const repeated = [_][]const u8{"env"};
        pub const comma_separated = [_][]const u8{"enabled_layouts"};
    };
    const result = try tree(arena.allocator(), .{ .advanced = Section{
        .env = &.{ .{ .name = "EDITOR", .value = "nvim" }, .{ .name = "PAGER" } },
        .enabled_layouts = &.{ .tall, .stack },
        .url_prefixes = &.{ "http", "https" },
    } });
    const entries = result.table[0].value.table;
    try testing.expectEqual(4, entries.len);
    try testing.expectEqualStrings("EDITOR=nvim", entries[0].value.raw);
    try testing.expectEqualStrings("PAGER", entries[1].value.raw);
    try testing.expectEqualStrings("tall,stack", entries[2].value.raw);
    try testing.expectEqualStrings("https", entries[3].value.list[1].string);
}

test "structured values are written in kitty's syntax" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const font: values.Font = .{ .family = "Maple Mono \"NF\"", .features = &.{ "+zero", "cv01=2" }, .axes = &.{.{ .name = "wght", .value = 380 }} };
    try testing.expectEqualStrings("family=\"Maple Mono \\\"NF\\\"\" features=\"+zero cv01=2\" wght=380", (try value(allocator, font)).raw);
    try testing.expectEqualStrings("10", (try value(allocator, values.Edges.all(10))).raw);
    try testing.expectEqualStrings("1 2 3 4", (try value(allocator, values.Edges{ .top = 1, .right = 2, .bottom = 3, .left = 4 })).raw);
    const symbols: values.SymbolMap = .{ .codepoints = &.{ .{ .first = 0xe0a0, .last = 0xe0a3 }, .{ .first = 0x2665 } }, .font = "Symbols Nerd Font" };
    try testing.expectEqualStrings("U+E0A0-U+E0A3,U+2665 Symbols Nerd Font", (try value(allocator, symbols)).raw);
    const blink: values.Timing = .{ .seconds = -1, .easing = .linear, .second_easing = .{ .cubic_bezier = .{ .x1 = 0.4, .y1 = 0, .x2 = 0.2, .y2 = 1 } } };
    try testing.expectEqualStrings("-1 linear cubic-bezier(0.4, 0, 0.2, 1)", (try value(allocator, blink)).raw);
    try testing.expectEqualStrings("no-cursor no-sudo", (try value(allocator, values.ShellIntegration{ .no_cursor = true, .no_sudo = true })).raw);
    try testing.expectEqualStrings("enabled", (try value(allocator, values.ShellIntegration{})).raw);
    try testing.expectEqualStrings("disabled", (try value(allocator, values.ShellIntegration{ .disabled = true, .no_rc = true })).raw);
    try testing.expectEqualStrings("no-op", (try value(allocator, values.PasteActions{})).raw);
    try testing.expectEqualStrings("ctrl+shift", (try value(allocator, values.Modifiers{ .ctrl = true, .shift = true })).raw);
    try testing.expectEqualStrings("env_var,path", (try value(allocator, values.CloneSourceStrategies{ .env_var = true, .path = true })).raw);
    try testing.expectEqualStrings("0 count-background", (try value(allocator, values.ConfirmClose{ .windows = 0, .count_background = true })).raw);
    try testing.expectEqualStrings("80c", (try value(allocator, values.WindowSize{ .cells = 80 })).raw);
    try testing.expectEqualStrings("auto", (try value(allocator, values.FontOrAuto.auto)).raw);
    const notify: values.NotifyOnCmdFinish = .{ .when = .invisible, .min_seconds = 15, .action = .{ .notify_bell = .{ .focus = true } } };
    try testing.expectEqualStrings("invisible 15 notify-bell focus", (try value(allocator, notify)).raw);
    try testing.expectEqualStrings("global \"Actions::Launch\" launch sh", (try value(allocator, values.MenuMap{ .path = &.{ "Actions", "Launch" }, .action = "launch sh" })).raw);
}
