//! What programs in kitty may do with the clipboard and the primary selection.

const ClipboardControl = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Writing the clipboard is allowed.
write_clipboard: bool = false,
/// Reading the clipboard is allowed.
read_clipboard: bool = false,
/// Writing the primary selection is allowed.
write_primary: bool = false,
/// Reading the primary selection is allowed.
read_primary: bool = false,
/// Reading the clipboard asks first.
read_clipboard_ask: bool = false,
/// Reading the primary selection asks first.
read_primary_ask: bool = false,

/// Writes the value the way kitty.conf spells it.
pub fn format(control: ClipboardControl, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    _ = try values.writeFlags(writer, control, " ", false);
}
