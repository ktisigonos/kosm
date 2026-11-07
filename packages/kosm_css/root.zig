//! CSS: custom properties on `:root` (the `css` adapter).

const std = @import("std");
const kosm = @import("kosm");

/// Writes CSS custom properties; enables `generate` and `block` (D71). Colors default to `#rrggbbaa`.
pub const adapter: kosm.Adapter = .{
    .name = "css",
    .extensions = &.{".css"},
    .default_format = .{ .color = .hex8 },
    .serialize = serialize,
    .comment = .{ .block = .{ .open = "/*", .close = "*/" } },
};

/// One `--name: value;` line per value, inside `:root { }`. Nested tables join their keys with
/// `-`, and `_` becomes `-`: `.kosm = .{ .tab_bar = c }` is `--kosm-tab-bar`.
fn serialize(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (root != .table) return context.unsupported("a CSS file is a table of properties, not a {s}", .{@tagName(root)});
    try writer.writeAll(":root {\n");
    var path: [max_depth][]const u8 = undefined;
    try writeTable(writer, root.table, &path, 0, context);
    try writer.writeAll("}\n");
}

/// Deeper nesting than this is surely a mistake in the app.
const max_depth = 16;

fn writeTable(writer: *std.Io.Writer, entries: []const kosm.Value.Entry, path: *[max_depth][]const u8, depth: usize, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (depth == max_depth) return context.unsupported("properties nest deeper than {d} levels", .{max_depth});
    for (entries) |entry| {
        path[depth] = entry.key;
        if (entry.value == .table) {
            try writeTable(writer, entry.value.table, path, depth + 1, context);
            continue;
        }
        try writer.writeAll("  --");
        for (path[0 .. depth + 1], 0..) |segment, index| {
            if (index != 0) try writer.writeByte('-');
            for (segment) |character| try writer.writeByte(if (character == '_') '-' else character);
        }
        try writer.writeAll(": ");
        try writeValue(writer, path[0 .. depth + 1], entry.value, context);
        try writer.writeAll(";\n");
    }
}

fn writeValue(writer: *std.Io.Writer, path: []const []const u8, value: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    switch (value) {
        .string => |text| {
            try writer.writeByte('"');
            for (text) |character| switch (character) {
                '"', '\\' => try writer.print("\\{c}", .{character}),
                '\n' => try writer.writeAll("\\a "),
                else => try writer.writeByte(character),
            };
            try writer.writeByte('"');
        },
        .raw => |text| try writer.writeAll(text),
        .integer => |integer| try writer.print("{d}", .{integer}),
        .float => |float| try context.writeFloat(writer, float),
        .color => |color| try context.writeColor(writer, color),
        .boolean => return context.unsupported("'{s}': CSS has no booleans; pass a number or kosm.raw text", .{path[path.len - 1]}),
        .list => return context.unsupported("'{s}': CSS lists differ per property; pass kosm.raw text", .{path[path.len - 1]}),
        .joined => |parts| for (parts) |part| try writeValue(writer, path, part, context),
        .table => unreachable,
    }
}

const testing = std.testing;

test "nested tables become dashed custom properties on :root" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    var context: kosm.Adapter.Context = .{ .format = adapter.default_format.resolve() };
    const root: kosm.Value = .{ .table = &.{.{ .key = "kosm", .value = .{ .table = &.{
        .{ .key = "foreground", .value = .{ .color = try kosm.Color.parseHex("#a3c5cc") } },
        .{ .key = "containers", .value = .{ .table = &.{.{ .key = "blue", .value = .{ .color = try kosm.Color.parseHex("#26718080") } }} } },
        .{ .key = "font_family", .value = .{ .string = "Maple \"Mono\"" } },
        .{ .key = "border_radius", .value = .{ .raw = "10px" } },
        .{ .key = "opacity", .value = .{ .float = 0.5 } },
    } } }} };
    try serialize(&output.writer, root, &context);
    try testing.expectEqualStrings(
        \\:root {
        \\  --kosm-foreground: #a3c5ccff;
        \\  --kosm-containers-blue: #26718080;
        \\  --kosm-font-family: "Maple \"Mono\"";
        \\  --kosm-border-radius: 10px;
        \\  --kosm-opacity: 0.5;
        \\}
        \\
    , output.written());
}

test "booleans and lists are refused with the property named" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    var context: kosm.Adapter.Context = .{ .format = adapter.default_format.resolve() };
    const root: kosm.Value = .{ .table = &.{.{ .key = "blur", .value = .{ .boolean = true } }} };
    try testing.expectError(error.UnsupportedValue, serialize(&output.writer, root, &context));
    try testing.expectEqualStrings("'blur': CSS has no booleans; pass a number or kosm.raw text", context.message());
}
