//! Passed to an adapter capability: the file's color format (D61), and room to explain
//! why a value can't be written, so kosm can report it with the file and app (G6).

const Context = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const ColorFormat = @import("../ColorFormat.zig");

/// How colors without an explicit component are printed in this file.
color_format: ColorFormat,
message_buffer: [message_capacity]u8 = undefined,
message_length: usize = 0,

const message_capacity = 512;

/// Prints `color` in the file's color format.
pub fn writeColor(context: *const Context, writer: *std.Io.Writer, color: Color) std.Io.Writer.Error!void {
    context.color_format.write(color, writer) catch |err| switch (err) {
        error.WriteFailed => return error.WriteFailed,
        // Kosm checks the format before handing it to an adapter.
        error.InvalidColorFormat => unreachable,
    };
}

/// Records why a value can't be written and returns the error to pass up.
/// Too-long messages are cut short.
pub fn unsupported(context: *Context, comptime format: []const u8, arguments: anytype) error{UnsupportedValue} {
    const written = std.fmt.bufPrint(&context.message_buffer, format, arguments) catch blk: {
        break :blk context.message_buffer[0..];
    };
    context.message_length = written.len;
    return error.UnsupportedValue;
}

/// The message given to `unsupported`, or empty.
pub fn message(context: *const Context) []const u8 {
    return context.message_buffer[0..context.message_length];
}
