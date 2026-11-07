//! ghostty config files: one `key = value` line per option, a repeated key adding one more
//! (`font-family`, `palette`, `keybind`), `#` comments on lines of their own (D40). A table is a
//! section, written as a `# name` comment above its options, since ghostty has no nesting.

const std = @import("std");
const kosm = @import("kosm");
const parser = @import("parser.zig");

/// The adapter for ghostty config files; enables `generate`, `block` (D71) and `edit`. It claims
/// `.ghostty`, ghostty's own extension; the plain `config` file needs `.lang = "ghostty"`.
pub const adapter: kosm.Adapter = .{
    .name = "ghostty",
    .extensions = &.{".ghostty"},
    .default_format = .{ .color = .hex, .boolean = .true_false },
    .format = format,
    .parser = parser.parse,
    .serialize = serialize,
    .comment = .{ .line = "#" },
};

/// Longest value kosm renders before deciding whether it needs quotes.
const max_value_length = 64 * 1024;

fn serialize(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (root != .table) return context.unsupported("a ghostty config file is a table of options, not a {s}", .{@tagName(root)});
    var first_section = true;
    try writeTable(writer, root.table, context, &first_section);
}

fn writeTable(writer: *std.Io.Writer, entries: []const kosm.Value.Entry, context: *kosm.Adapter.Context, first_section: *bool) kosm.Adapter.Error!void {
    for (entries) |entry| {
        switch (entry.value) {
            .table => |table| {
                if (table.len == 0) continue;
                if (!first_section.*) try writer.writeByte('\n');
                first_section.* = false;
                try writer.print("# {s}\n", .{entry.key});
                try writeTable(writer, table, context, first_section);
            },
            .list => |items| for (items) |item| try writeLine(writer, entry.key, item, context),
            else => try writeLine(writer, entry.key, entry.value, context),
        }
    }
}

fn writeLine(writer: *std.Io.Writer, key: []const u8, value: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (value == .list or value == .table) return context.unsupported("'{s}': a ghostty option holds one plain value per line", .{key});
    try writer.print("{s} = ", .{key});
    try writeValue(writer, key, value, context);
    try writer.writeByte('\n');
}

/// Writes one value; with `parser`, enables `edit` (D42).
fn format(writer: *std.Io.Writer, value: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (value == .list or value == .table) return context.unsupported("a ghostty option holds one plain value, not a {s}", .{@tagName(value)});
    try writeValue(writer, "value", value, context);
}

/// Strings and joined values get quotes when ghostty would otherwise change them: it trims a
/// value's outer whitespace and strips one pair of outer quotes, and never reads escapes.
fn writeValue(writer: *std.Io.Writer, key: []const u8, value: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    switch (value) {
        .raw => |text| {
            try checkSingleLine(key, text, context);
            try writer.writeAll(text);
        },
        .string => |text| try writeQuotedIfNeeded(writer, key, text, context),
        .joined => {
            var buffer: [max_value_length]u8 = undefined;
            var rendered: std.Io.Writer = .fixed(&buffer);
            writePlain(&rendered, key, value, context) catch |err| switch (err) {
                error.WriteFailed => return context.unsupported("'{s}': the value is longer than {d} bytes", .{ key, max_value_length }),
                error.UnsupportedValue => return error.UnsupportedValue,
            };
            try writeQuotedIfNeeded(writer, key, rendered.buffered(), context);
        },
        else => try writePlain(writer, key, value, context),
    }
}

fn writePlain(writer: *std.Io.Writer, key: []const u8, value: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    switch (value) {
        .string, .raw => |text| {
            try checkSingleLine(key, text, context);
            try writer.writeAll(text);
        },
        .integer => |integer| try writer.print("{d}", .{integer}),
        .float => |float| try context.writeFloat(writer, float),
        .boolean => |boolean| try context.writeBoolean(writer, boolean),
        .color => |color| try context.writeColor(writer, color),
        .joined => |parts| for (parts) |part| try writePlain(writer, key, part, context),
        .list, .table => return context.unsupported("'{s}': a ghostty value holds no lists or tables", .{key}),
    }
}

fn writeQuotedIfNeeded(writer: *std.Io.Writer, key: []const u8, text: []const u8, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    try checkSingleLine(key, text, context);
    if (!needsQuotes(text)) return writer.writeAll(text);
    try writer.print("\"{s}\"", .{text});
}

fn needsQuotes(text: []const u8) bool {
    if (text.len == 0) return true;
    if (isSpace(text[0]) or isSpace(text[text.len - 1])) return true;
    return text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"';
}

fn isSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t';
}

fn checkSingleLine(key: []const u8, text: []const u8, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (std.mem.indexOfAny(u8, text, "\r\n") != null) return context.unsupported("'{s}': ghostty values cannot span lines", .{key});
}

const testing = std.testing;

fn serializeForTest(root: kosm.Value, output: *std.Io.Writer.Allocating) !void {
    var context: kosm.Adapter.Context = .{ .format = adapter.default_format.resolve() };
    try serialize(&output.writer, root, &context);
}

test "options are key = value lines, lists repeat the key" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    const root: kosm.Value = .{ .table = &.{
        .{ .key = "font-family", .value = .{ .list = &.{ .{ .string = "Maple Mono Normal NFP" }, .{ .string = "Cascadia Code NF" } } } },
        .{ .key = "font-size", .value = .{ .float = 13 } },
        .{ .key = "palette", .value = .{ .joined = &.{ .{ .raw = "0=" }, .{ .color = try kosm.Color.parseHex("#041C26") } } } },
        .{ .key = "background-opacity", .value = .{ .float = 0.5 } },
        .{ .key = "focus-follows-mouse", .value = .{ .boolean = true } },
        .{ .key = "image-storage-limit", .value = .{ .integer = 4294967295 } },
        .{ .key = "empty", .value = .{ .table = &.{} } },
    } };
    try serializeForTest(root, &output);
    try testing.expectEqualStrings(
        \\font-family = Maple Mono Normal NFP
        \\font-family = Cascadia Code NF
        \\font-size = 13
        \\palette = 0=#041c26
        \\background-opacity = 0.5
        \\focus-follows-mouse = true
        \\image-storage-limit = 4294967295
        \\
    , output.written());
}

test "tables become section comments" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    const root: kosm.Value = .{ .table = &.{
        .{ .key = "fonts", .value = .{ .table = &.{.{ .key = "font-size", .value = .{ .integer = 13 } }} } },
        .{ .key = "colors", .value = .{ .table = &.{.{ .key = "background", .value = .{ .color = try kosm.Color.parseHex("#282c34") } }} } },
    } };
    try serializeForTest(root, &output);
    try testing.expectEqualStrings("# fonts\nfont-size = 13\n\n# colors\nbackground = #282c34\n", output.written());
}

test "values ghostty would trim or unquote are quoted" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    const root: kosm.Value = .{ .table = &.{
        .{ .key = "title", .value = .{ .string = " " } },
        .{ .key = "title", .value = .{ .string = "" } },
        .{ .key = "title", .value = .{ .string = "\"quoted\"" } },
        .{ .key = "title", .value = .{ .string = "say \"hi\" #1" } },
        .{ .key = "keybind", .value = .{ .joined = &.{.{ .raw = "ctrl+a=text:a " }} } },
    } };
    try serializeForTest(root, &output);
    try testing.expectEqualStrings(
        \\title = " "
        \\title = ""
        \\title = ""quoted""
        \\title = say "hi" #1
        \\keybind = "ctrl+a=text:a "
        \\
    , output.written());
}

test "values that would break a line are refused" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    var context: kosm.Adapter.Context = .{ .format = adapter.default_format.resolve() };
    const root: kosm.Value = .{ .table = &.{.{ .key = "command", .value = .{ .string = "fish\nrm -rf" } }} };
    try testing.expectError(error.UnsupportedValue, serialize(&output.writer, root, &context));
    try testing.expectEqualStrings("'command': ghostty values cannot span lines", context.message());
}

test "format writes one value the way serialize does" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    var context: kosm.Adapter.Context = .{ .format = adapter.default_format.resolve() };
    try format(&output.writer, .{ .string = "  padded" }, &context);
    try output.writer.writeByte(' ');
    try format(&output.writer, .{ .color = try kosm.Color.parseHex("#a3c5cc") }, &context);
    try testing.expectEqualStrings("\"  padded\" #a3c5cc", output.written());
    try testing.expectError(error.UnsupportedValue, format(&output.writer, .{ .list = &.{} }, &context));
}

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings = undefined,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output = undefined,

    fn init(fixture: *Fixture, path: []const u8, contents: []const u8) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        if (std.Io.Dir.path.dirname(path)) |parent| try fixture.tmp.dir.createDirPath(testing.io, parent);
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = contents });
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "terminal",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }
};

const real_config =
    \\config-file = Ricer
    \\gtk-single-instance = true
    \\quit-after-last-window-closed = false
    \\
    \\font-synthetic-style = true
    \\font-size = 13
    \\
    \\cursor-style = block
    \\focus-follows-mouse = true
    \\
    \\window-decoration = server
    \\window-padding-x = 10
    \\window-padding-y = 10
    \\
    \\palette =  0 = 041C26
    \\palette = 1=80333C
    \\custom-shader-animation = true
    \\custom-shader = ./shaders/ghostty-cursor-shaders/cursor_warp.glsl
    \\
    \\# Conflicts with many common binds, such as ones in lazy git
    \\keybind = ctrl+enter=unbind
    \\
;

test "edit changes only the values' bytes of a real config, repeated keys by index" {
    var fixture: Fixture = undefined;
    try fixture.init(".config/ghostty/config", real_config);
    defer fixture.deinit();
    var config = try fixture.output.edit(.{ .files = "~/.config/ghostty/config", .lang = "ghostty" });
    try config.set("font-size", 14.5);
    try config.set("focus-follows-mouse", false);
    try config.set("window-padding-x", kosm.raw("10,20"));
    try config.setNth("palette", 1, kosm.raw("1=#993d49"));
    try config.set("custom-shader", " ./shaders/padded.glsl");
    try testing.expectError(error.TooManyMatches, config.set("palette", kosm.raw("0=#000000")));

    try testing.expectEqualStrings(
        \\config-file = Ricer
        \\gtk-single-instance = true
        \\quit-after-last-window-closed = false
        \\
        \\font-synthetic-style = true
        \\font-size = 14.5
        \\
        \\cursor-style = block
        \\focus-follows-mouse = false
        \\
        \\window-decoration = server
        \\window-padding-x = 10,20
        \\window-padding-y = 10
        \\
        \\palette =  0 = 041C26
        \\palette = 1=#993d49
        \\custom-shader-animation = true
        \\custom-shader = " ./shaders/padded.glsl"
        \\
        \\# Conflicts with many common binds, such as ones in lazy git
        \\keybind = ctrl+enter=unbind
        \\
    , fixture.plan.files.items[0].new);
}

test "the .ghostty extension picks the adapter without .lang" {
    var fixture: Fixture = undefined;
    try fixture.init(".config/ghostty/config.ghostty", "background = 282c34\n");
    defer fixture.deinit();
    var config = try fixture.output.edit(.{ .files = "~/.config/ghostty/config.ghostty" });
    try config.set("background", kosm.hex("041c26"));
    try testing.expectEqualStrings("background = #041c26\n", fixture.plan.files.items[0].new);
}
