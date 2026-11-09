//! Why an apply failed, with everything needed to find the cause: kosmos, app, file and a
//! message. Filled by whoever fails first and printed by the runner.

const Diagnostics = @This();

const std = @import("std");

/// The kosmos being applied, e.g. "frost.iced".
kosmos: []const u8 = "",
/// The app's path in the kosmos tree, e.g. "terminal.kitty".
app: []const u8 = "",
/// The file involved, as the app wrote it ("~/.config/kitty/kosm.conf"), or empty.
file: []const u8 = "",
message_buffer: [message_capacity]u8 = undefined,
message_length: usize = 0,

const message_capacity = 1024;

/// Records the failure; `app` and `file` may be empty. Too-long messages are cut short.
pub fn set(diagnostics: *Diagnostics, app: []const u8, file: []const u8, comptime format: []const u8, arguments: anytype) void {
    diagnostics.app = app;
    diagnostics.file = file;
    const written = std.fmt.bufPrint(&diagnostics.message_buffer, format, arguments) catch blk: {
        break :blk diagnostics.message_buffer[0..];
    };
    diagnostics.message_length = written.len;
}

/// The recorded message, or empty.
pub fn message(diagnostics: *const Diagnostics) []const u8 {
    return diagnostics.message_buffer[0..diagnostics.message_length];
}

/// Prints `error: kosmos 'frost', app 'terminal.kitty', file ~/.config/kitty/kosm.conf: message`,
/// leaving out the parts that are empty.
pub fn write(diagnostics: *const Diagnostics, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writeReport(writer, "error", diagnostics.kosmos, diagnostics.app, diagnostics.file, diagnostics.message());
}

/// Prints `<severity>: kosmos '<kosmos>', app '<app>', file <file>: <message>`, leaving out the
/// parts that are empty. Errors and warnings share this shape.
pub fn writeReport(writer: *std.Io.Writer, severity: []const u8, kosmos: []const u8, app: []const u8, file: []const u8, text: []const u8) std.Io.Writer.Error!void {
    try writer.print("{s}: ", .{severity});
    var separator: []const u8 = "";
    if (kosmos.len != 0) {
        try writer.print("kosmos '{s}'", .{kosmos});
        separator = ", ";
    }
    if (app.len != 0) {
        try writer.print("{s}app '{s}'", .{ separator, app });
        separator = ", ";
    }
    if (file.len != 0) try writer.print("{s}file {s}", .{ separator, file });
    if (separator.len != 0 or file.len != 0) try writer.writeAll(": ");
    try writer.print("{s}\n", .{text});
}

test "write names kosmos, app and file" {
    var diagnostics: Diagnostics = .{ .kosmos = "frost" };
    diagnostics.set("terminal.kitty", "~/.config/kitty/kosm.conf", "no adapter for '{s}'", .{".conf"});
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try diagnostics.write(&writer);
    try std.testing.expectEqualStrings(
        "error: kosmos 'frost', app 'terminal.kitty', file ~/.config/kitty/kosm.conf: no adapter for '.conf'\n",
        writer.buffered(),
    );
}
