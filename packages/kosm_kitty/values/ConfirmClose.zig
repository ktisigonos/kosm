//! When closing an OS window or tab asks first.

const ConfirmClose = @This();

const std = @import("std");

/// Ask when closing with at least this many windows; 0 never asks, negative values do not
/// count windows sitting at a shell prompt.
windows: i32,
/// Count windows running background jobs too.
count_background: bool = false,

/// Writes the value the way kitty.conf spells it.
pub fn format(confirm: ConfirmClose, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d}", .{confirm.windows});
    if (confirm.count_background) try writer.writeAll(" count-background");
}
