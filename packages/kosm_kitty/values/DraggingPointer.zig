//! The pointer shapes while dragging across text.

const DraggingPointer = @This();

const std = @import("std");
const values = @import("../values.zig");

/// The shape for a normal selection.
shape: values.PointerShape,
/// The shape for a rectangular selection; null: same as `shape`.
rectangle_shape: ?values.PointerShape = null,

/// Writes the value the way kitty.conf spells it.
pub fn format(pointer: DraggingPointer, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try values.writeTag(writer, @tagName(pointer.shape), false);
    if (pointer.rectangle_shape) |shape| {
        try writer.writeByte(' ');
        try values.writeTag(writer, @tagName(shape), false);
    }
}
