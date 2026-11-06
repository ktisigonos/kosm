//! Passed to an adapter capability: the file's format (D70), and room to explain why a value or
//! a file can't be handled, so kosm can report it with the file and app (G6).

const Context = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const Format = @import("../Format.zig");

/// How this file spells colors, booleans and floats, every layer applied.
format: Format.Resolved,
message_buffer: [message_capacity]u8 = undefined,
message_length: usize = 0,

const message_capacity = 512;

/// Prints `color` in the file's color format.
pub fn writeColor(context: *const Context, writer: *std.Io.Writer, color: Color) std.Io.Writer.Error!void {
    context.format.writeColor(writer, color) catch |err| switch (err) {
        error.WriteFailed => return error.WriteFailed,
        // Kosm checks the format before handing it to an adapter.
        error.InvalidColorFormat => unreachable,
    };
}

/// Prints `value` in the file's boolean spelling.
pub fn writeBoolean(context: *const Context, writer: *std.Io.Writer, value: bool) std.Io.Writer.Error!void {
    return context.format.writeBoolean(writer, value);
}

/// Prints `value` at the file's float precision.
pub fn writeFloat(context: *const Context, writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    return context.format.writeFloat(writer, value);
}

/// Records why a value can't be written and returns the error to pass up.
/// Too-long messages are cut short.
pub fn unsupported(context: *Context, comptime format: []const u8, arguments: anytype) error{UnsupportedValue} {
    context.record(format, arguments);
    return error.UnsupportedValue;
}

/// Records why a file can't be read and returns the error to pass up.
/// Too-long messages are cut short.
pub fn invalidSyntax(context: *Context, comptime format: []const u8, arguments: anytype) error{InvalidSyntax} {
    context.record(format, arguments);
    return error.InvalidSyntax;
}

fn record(context: *Context, comptime format: []const u8, arguments: anytype) void {
    const written = std.fmt.bufPrint(&context.message_buffer, format, arguments) catch blk: {
        break :blk context.message_buffer[0..];
    };
    context.message_length = written.len;
}

/// The message given to `unsupported` or `invalidSyntax`, or empty.
pub fn message(context: *const Context) []const u8 {
    return context.message_buffer[0..context.message_length];
}
