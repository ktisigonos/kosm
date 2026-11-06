//! What the runner tells the user after a successful apply. All of its wording lives here.

const std = @import("std");

/// A file the commit wrote, as the app named it (`~/.config/kitty/kosm.conf`).
pub fn wrote(writer: *std.Io.Writer, path: []const u8) std.Io.Writer.Error!void {
    try writer.print("wrote {s}\n", .{path});
}

/// The plan matches the disk, so nothing was (or would be) written.
pub fn nothingToChange(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll("nothing to change\n");
}

/// A reload that failed after the commit (D74): a warning, since the files are written and the
/// program may simply not be running.
pub fn reloadFailed(writer: *std.Io.Writer, kosmos: []const u8, app: []const u8, reason: []const u8) std.Io.Writer.Error!void {
    try writer.print("warning: kosmos '{s}', app '{s}': reload failed: {s}\n", .{ kosmos, app, reason });
}

/// The record for `kosm current` could not be saved (D75): a warning, since the files are written.
pub fn recordFailed(writer: *std.Io.Writer, path: []const u8, reason: []const u8) std.Io.Writer.Error!void {
    try writer.print("warning: cannot record this apply for kosm current in {s}: {s}\n", .{ path, reason });
}
