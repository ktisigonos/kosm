//! Which in-app notifications ghostty shows (`app-notifications`); GTK only. Null flags keep ghostty's defaults.

const AppNotifications = @This();

const std = @import("std");
const values = @import("../values.zig");

/// When text is copied to the clipboard. ghostty's default: on.
clipboard_copy: ?bool = null,
/// When the configuration is reloaded. ghostty's default: on.
config_reload: ?bool = null,

/// Writes the set flags the way ghostty spells them (`clipboard-copy,no-config-reload`).
pub fn format(flags: AppNotifications, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
