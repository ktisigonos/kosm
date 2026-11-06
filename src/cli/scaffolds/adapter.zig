//! The scaffold_name adapter, made by `kosm new adapter scaffold_name`. Apps write
//! `.scaffold_name` files through it, or any file with `.lang = "scaffold_name"`.

const std = @import("std");
const kosm = @import("kosm");

/// Every capability is optional: `serialize` lets apps `generate` whole files, `comment` lets
/// them write blocks, and `format` with `parser` lets them edit values by path.
pub const adapter: kosm.Adapter = .{
    .name = "scaffold_name",
    .extensions = &.{".scaffold_name"},
    .serialize = serialize,
    .comment = .{ .line = "#" },
};

/// One `key = value` line per value. Nested tables and lists are refused.
fn serialize(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (root != .table) return context.unsupported("a scaffold_name file is a table of keys, not a {s}", .{@tagName(root)});
    for (root.table) |entry| {
        try writer.print("{s} = ", .{entry.key});
        switch (entry.value) {
            .string => |text| try writer.print("\"{s}\"", .{text}),
            .raw => |text| try writer.writeAll(text),
            .integer => |integer| try writer.print("{d}", .{integer}),
            .float => |float| try context.writeFloat(writer, float),
            .boolean => |boolean| try context.writeBoolean(writer, boolean),
            .color => |color| try context.writeColor(writer, color),
            .table, .list => return context.unsupported("'{s}' is a {s}; scaffold_name files hold only plain values", .{ entry.key, @tagName(entry.value) }),
        }
        try writer.writeByte('\n');
    }
}
