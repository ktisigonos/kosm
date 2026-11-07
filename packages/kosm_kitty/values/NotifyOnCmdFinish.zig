//! A notification when a long-running command finishes.

const NotifyOnCmdFinish = @This();

const std = @import("std");
const Joined = @import("../Joined.zig");
const values = @import("../values.zig");

/// When to notify.
when: enum { never, unfocused, invisible, always },
/// The shortest command, in seconds, that counts as long-running.
min_seconds: f64 = 5,
/// What to do; null: kitty's default, a desktop notification.
action: ?Action = null,

/// What happens when a command finishes.
pub const Action = union(enum) {
    notify: ClearOn,
    bell,
    notify_bell: ClearOn,
    /// A command line to run.
    command: []const u8,

    /// Writes the value the way kitty.conf spells it.
    pub fn format(action: Action, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try values.writeTag(writer, @tagName(action), false);
        switch (action) {
            .notify, .notify_bell => |clear_on| {
                try writer.writeByte(' ');
                _ = try values.writeFlags(writer, clear_on, " ", false);
            },
            .bell => {},
            .command => |command| try writer.print(" {s}", .{command}),
        }
    }
};

/// What clears a notification; none set: kitty's default.
pub const ClearOn = struct {
    /// The window gains focus.
    focus: bool = false,
    /// The next command finishes.
    next: bool = false,
};

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(notify: NotifyOnCmdFinish, joined: *Joined) Joined.Error!void {
    try joined.writer().print("{s} ", .{@tagName(notify.when)});
    try joined.float(notify.min_seconds);
    if (notify.action) |action| try joined.writer().print(" {f}", .{action});
}
