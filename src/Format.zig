//! How one file spells its values (D69, D70): colors, booleans and float precision. Every
//! field is optional and layers like D61: the user's assignment, then the app's default (both
//! the app's `format` field), then the adapter's `default_format`, then kosm's.

const Format = @This();

const std = @import("std");
const Color = @import("Color.zig");
const ColorFormat = @import("ColorFormat.zig");

/// How colors print when no component is named (D61). Null: the next layer's.
color: ?ColorFormat = null,
/// How booleans print. Null: the next layer's.
boolean: ?Boolean = null,
/// Floats print with at most this many decimals, trailing zeros trimmed (2: `0.5`, `13`),
/// float color components (`alpha_01`) included. 0..12. Null: the next layer's.
float_precision: ?u8 = null,

/// Every choice made, as a file is written with it.
pub const Resolved = @import("Format/Resolved.zig");

/// The spellings of `true` and `false`.
pub const Boolean = enum {
    /// `true` / `false`
    true_false,
    /// `yes` / `no`
    yes_no,
    /// `1` / `0`
    one_zero,
    /// `on` / `off`
    on_off,

    /// The text for `value`.
    pub fn text(boolean: Boolean, value: bool) []const u8 {
        return switch (boolean) {
            .true_false => if (value) "true" else "false",
            .yes_no => if (value) "yes" else "no",
            .one_zero => if (value) "1" else "0",
            .on_off => if (value) "on" else "off",
        };
    }
};

/// Kosm's own layer, under every other: `#rrggbb`, `true`/`false`, 6 decimals.
pub const kosm_default: Resolved = .{ .color = .hex, .boolean = .true_false, .float_precision = Color.default_decimals };

/// The most decimals `float_precision` takes.
pub const max_float_precision = Color.max_decimals;

/// This format's choices, with `fallback`'s for every field left null.
pub fn orElse(format: Format, fallback: Format) Format {
    return .{
        .color = format.color orelse fallback.color,
        .boolean = format.boolean orelse fallback.boolean,
        .float_precision = format.float_precision orelse fallback.float_precision,
    };
}

/// Every choice, with kosm's own for each field still null.
pub fn resolve(format: Format) Resolved {
    return .{
        .color = format.color orelse kosm_default.color,
        .boolean = format.boolean orelse kosm_default.boolean,
        .float_precision = format.float_precision orelse kosm_default.float_precision,
    };
}

/// Whether every field is set, so no lower layer can matter.
pub fn isComplete(format: Format) bool {
    return format.color != null and format.boolean != null and format.float_precision != null;
}

const testing = std.testing;

test "layers fill only the fields above them left null" {
    const user: Format = .{ .boolean = .on_off };
    const app: Format = .{ .boolean = .one_zero, .float_precision = 2 };
    const adapter: Format = .{ .color = .hex8, .boolean = .yes_no };
    const resolved = user.orElse(app).orElse(adapter).resolve();
    try testing.expectEqual(Boolean.on_off, resolved.boolean);
    try testing.expectEqual(2, resolved.float_precision);
    try testing.expectEqualStrings(ColorFormat.hex8.template, resolved.color.template);
    try testing.expectEqual(ColorFormat.hex8.components[0], resolved.color.components[0]);

    const empty: Format = .{};
    const bottom = empty.resolve();
    try testing.expectEqual(Boolean.true_false, bottom.boolean);
    try testing.expectEqual(6, bottom.float_precision);
    try testing.expect(!empty.isComplete());
    try testing.expect(user.orElse(app).orElse(adapter).isComplete());
}
