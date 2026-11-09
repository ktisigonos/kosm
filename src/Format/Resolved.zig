//! A file's format with every choice made: what adapters and templates write with.

const Resolved = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const ColorFormat = @import("../ColorFormat.zig");
const Format = @import("../Format.zig");
const Boolean = Format.Boolean;

/// How colors print when no component is named.
color: ColorFormat,
/// How booleans print.
boolean: Boolean,
/// Floats print with at most this many decimals, 0..12.
float_precision: u8,

/// Errors from `writeColor`.
pub const WriteError = ColorFormat.WriteError;

/// Prints `color` in the file's color format, float components at the file's precision.
pub fn writeColor(format: Resolved, writer: *std.Io.Writer, color: Color) WriteError!void {
    return format.color.write(color, format.float_precision, writer);
}

/// Prints one color component at the file's precision.
pub fn writeComponent(format: Resolved, writer: *std.Io.Writer, color: Color, component: Color.Component) std.Io.Writer.Error!void {
    return writer.writeAll(color.formatComponent(component, format.float_precision).slice());
}

/// Prints `value` in the file's spelling.
pub fn writeBoolean(format: Resolved, writer: *std.Io.Writer, value: bool) std.Io.Writer.Error!void {
    return writer.writeAll(format.boolean.text(value));
}

/// Prints `value` with at most the file's decimals, trailing zeros trimmed.
pub fn writeFloat(format: Resolved, writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    return writer.print("{d}", .{Color.roundDecimals(value, format.float_precision)});
}

const testing = std.testing;

test "floats and float color components follow the precision" {
    const two: Resolved = .{ .color = .init("{}", &.{.alpha_01}), .boolean = .yes_no, .float_precision = 2 };
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try two.writeFloat(&writer, 0.456);
    try writer.writeByte(' ');
    try two.writeFloat(&writer, 13);
    try writer.writeByte(' ');
    try two.writeColor(&writer, try Color.parseHex("#00000080"));
    try writer.writeByte(' ');
    try two.writeBoolean(&writer, false);
    try testing.expectEqualStrings("0.46 13 0.5 no", writer.buffered());
}

test "the default precision prints widened f32 values without noise" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    const empty: Format = .{};
    const format = empty.resolve();
    try format.writeFloat(&writer, @as(f32, 6.4));
    try testing.expectEqualStrings("6.4", writer.buffered());
}
