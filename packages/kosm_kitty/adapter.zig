//! kitty.conf: one `key value` line per option (D39). A table is a section, written as a
//! `# name` comment above its options, since kitty.conf has no nesting.

const std = @import("std");
const kosm = @import("kosm");

/// The adapter for kitty.conf files; enables `generate`. It claims no extension, since many
/// formats use `.conf`: pass `.lang = "kitty"`.
pub const adapter: kosm.Adapter = .{
    .name = "kitty",
    .color_format = .hex,
    .serialize = serialize,
};

fn serialize(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (root != .table) return context.unsupported("a kitty.conf file is a table of options, not a {s}", .{@tagName(root)});
    var first_section = true;
    try writeTable(writer, root.table, context, &first_section);
}

fn writeTable(writer: *std.Io.Writer, entries: []const kosm.Value.Entry, context: *kosm.Adapter.Context, first_section: *bool) kosm.Adapter.Error!void {
    for (entries) |entry| {
        if (entry.value == .table) {
            if (entry.value.table.len == 0) continue;
            if (!first_section.*) try writer.writeByte('\n');
            first_section.* = false;
            try writer.print("# {s}\n", .{entry.key});
            try writeTable(writer, entry.value.table, context, first_section);
            continue;
        }
        try writer.writeAll(entry.key);
        try writer.writeByte(' ');
        try writeValue(writer, entry.key, entry.value, context);
        try writer.writeByte('\n');
        first_section.* = false;
    }
}

fn writeValue(writer: *std.Io.Writer, key: []const u8, value: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    switch (value) {
        .string, .raw => |text| {
            if (std.mem.indexOfAny(u8, text, "\r\n") != null) return context.unsupported("'{s}': kitty.conf values cannot span lines", .{key});
            try writer.writeAll(text);
        },
        .integer => |integer| try writer.print("{d}", .{integer}),
        .float => |float| try writer.print("{d}", .{float}),
        .boolean => |boolean| try writer.writeAll(if (boolean) "yes" else "no"),
        .color => |color| try context.writeColor(writer, color),
        .list => |items| for (items, 0..) |item, index| {
            if (item == .list or item == .table) return context.unsupported("'{s}': a kitty.conf list holds only plain values", .{key});
            if (index != 0) try writer.writeByte(' ');
            try writeValue(writer, key, item, context);
        },
        .table => unreachable,
    }
}

const testing = std.testing;

fn serializeForTest(root: kosm.Value, output: *std.Io.Writer.Allocating) !void {
    var context: kosm.Adapter.Context = .{ .color_format = .hex };
    try serialize(&output.writer, root, &context);
}

test "sections become comments over plain option lines" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    const root: kosm.Value = .{ .table = &.{
        .{ .key = "fonts", .value = .{ .table = &.{
            .{ .key = "font_family", .value = .{ .raw = "family=\"Maple Mono\"" } },
            .{ .key = "font_size", .value = .{ .float = 13 } },
        } } },
        .{ .key = "mouse", .value = .{ .table = &.{} } },
        .{ .key = "colors", .value = .{ .table = &.{
            .{ .key = "background", .value = .{ .color = try kosm.Color.parseHex("#041c26") } },
            .{ .key = "background_opacity", .value = .{ .float = 0.5 } },
            .{ .key = "dynamic_background_opacity", .value = .{ .boolean = true } },
            .{ .key = "url_prefixes", .value = .{ .list = &.{ .{ .string = "http" }, .{ .string = "https" } } } },
        } } },
    } };
    try serializeForTest(root, &output);
    try testing.expectEqualStrings(
        \\# fonts
        \\font_family family="Maple Mono"
        \\font_size 13
        \\
        \\# colors
        \\background #041c26
        \\background_opacity 0.5
        \\dynamic_background_opacity yes
        \\url_prefixes http https
        \\
    , output.written());
}

test "values that would break a line are refused" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    var context: kosm.Adapter.Context = .{ .color_format = .hex };
    const root: kosm.Value = .{ .table = &.{.{ .key = "shell", .value = .{ .string = "fish\nrm -rf" } }} };
    try testing.expectError(error.UnsupportedValue, serialize(&output.writer, root, &context));
    try testing.expectEqualStrings("'shell': kitty.conf values cannot span lines", context.message());
}
