//! How a finished command is notified (`notify-on-command-finish-action`). Null flags keep ghostty's defaults.

const NotifyOnCommandFinishAction = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Ring the bell. ghostty's default: on.
bell: ?bool = null,
/// Send a desktop notification. ghostty's default: off.
notify: ?bool = null,

/// Writes the set flags the way ghostty spells them (`bell,no-notify`).
pub fn format(flags: NotifyOnCommandFinishAction, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
