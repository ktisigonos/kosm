//! How a file prints a color when no component is named (D61): a runtime value with the
//! template-and-components shape of `Color.format` (D47), so it can live in an app field.

const ColorFormat = @This();

const std = @import("std");
const Color = @import("Color.zig");

/// Text with one `{}` per component; `{{` and `}}` are literal braces. Build it with `init`.
template: []const u8,
/// The values filling the template's placeholders, in order.
components: []const Color.Component,

/// `#rrggbb`, clipped to the gamut.
pub const hex: ColorFormat = .init("#{}", &.{.hex});
/// `#rrggbbaa`, clipped to the gamut.
pub const hex8: ColorFormat = .init("#{}", &.{.hex8});
/// `#RRGGBB`, clipped to the gamut.
pub const hex_upper: ColorFormat = .init("#{}", &.{.hex_upper});
/// `#RRGGBBAA`, clipped to the gamut.
pub const hex8_upper: ColorFormat = .init("#{}", &.{.hex8_upper});

/// A format whose template and components are checked at compile time, like `Color.format`.
pub fn init(comptime template: []const u8, comptime components: []const Color.Component) ColorFormat {
    comptime Color.checkTemplate(template, components.len);
    return .{ .template = template, .components = components };
}

/// Errors from `write`.
pub const WriteError = std.Io.Writer.Error || error{InvalidColorFormat};

/// Prints `color` in this format, float components with at most `decimals` decimals. A template
/// that does not match its components (only possible when the fields were set by hand instead
/// of through `init`) is `error.InvalidColorFormat`.
pub fn write(format: ColorFormat, color: Color, decimals: u8, writer: *std.Io.Writer) WriteError!void {
    var component_index: usize = 0;
    var index: usize = 0;
    while (index < format.template.len) : (index += 1) {
        const character = format.template[index];
        const next = if (index + 1 < format.template.len) format.template[index + 1] else 0;
        if ((character == '{' or character == '}') and next == character) {
            try writer.writeByte(character);
            index += 1;
        } else if (character == '{' and next == '}') {
            if (component_index == format.components.len) return error.InvalidColorFormat;
            try writer.writeAll(color.formatComponent(format.components[component_index], decimals).slice());
            component_index += 1;
            index += 1;
        } else if (character == '{' or character == '}') {
            return error.InvalidColorFormat;
        } else {
            try writer.writeByte(character);
        }
    }
    if (component_index != format.components.len) return error.InvalidColorFormat;
}

const testing = std.testing;

fn expectWritten(expected: []const u8, format: ColorFormat, color: Color) !void {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try format.write(color, Color.default_decimals, &writer);
    try testing.expectEqualStrings(expected, writer.buffered());
}

test "runtime formats print like Color.format" {
    const color = try Color.parseHex("#5e81ac80");
    try expectWritten("#5e81ac", hex, color);
    try expectWritten("#5e81ac80", hex8, color);
    const rgba: ColorFormat = .init("rgba({}, {}, {}, {})", &.{ .red_255, .green_255, .blue_255, .alpha_01 });
    try expectWritten("rgba(94, 129, 172, 0.501961)", rgba, color);
    try expectWritten("{5e81ac}", .init("{{{}}}", &.{.hex}), color);
    try expectWritten("#5E81AC80", hex8_upper, color);
}

test "a hand-built format with the wrong component count is an error" {
    const color = try Color.parseHex("#5e81ac");
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    const too_few: ColorFormat = .{ .template = "{} {}", .components = &.{.hex} };
    try testing.expectError(error.InvalidColorFormat, too_few.write(color, 6, &writer));
    const too_many: ColorFormat = .{ .template = "{}", .components = &.{ .hex, .hex } };
    try testing.expectError(error.InvalidColorFormat, too_many.write(color, 6, &writer));
    const lone_brace: ColorFormat = .{ .template = "{x}", .components = &.{} };
    try testing.expectError(error.InvalidColorFormat, lone_brace.write(color, 6, &writer));
}
