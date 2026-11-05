//! A set of modifier keys, written `ctrl+shift`.

const Modifiers = @This();

const std = @import("std");
const values = @import("../values.zig");

ctrl: bool = false,
shift: bool = false,
alt: bool = false,
super: bool = false,
hyper: bool = false,
meta: bool = false,

/// Writes the value the way kitty.conf spells it.
pub fn format(modifiers: Modifiers, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    _ = try values.writeFlags(writer, modifiers, "+", false);
}
