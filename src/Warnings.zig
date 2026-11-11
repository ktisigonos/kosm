//! What an apply reports without failing: each warning names its app and file like an
//! error does. Filled while planning and printed by the runner.

const Warnings = @This();

const std = @import("std");
const Diagnostics = @import("Diagnostics.zig");

/// Holds every warning's text; an arena kosm frees after the apply.
allocator: std.mem.Allocator,
items: std.ArrayList(Warning) = .empty,

/// One warning; its strings live in the `Warnings`' allocator, or outlive it.
pub const Warning = struct {
    /// The app's path in the kosmos tree, or empty.
    app: []const u8,
    /// The file involved, as the app wrote it, or empty.
    file: []const u8,
    message: []const u8,
};

/// Warnings kept in `allocator`, an arena freed after the apply.
pub fn init(allocator: std.mem.Allocator) Warnings {
    return .{ .allocator = allocator };
}

/// Records a warning; `app` and `file` may be empty and must outlive the `Warnings`.
pub fn add(warnings: *Warnings, app: []const u8, file: []const u8, comptime format: []const u8, arguments: anytype) error{OutOfMemory}!void {
    const message = try warnings.allocator.print(format, arguments);
    try warnings.items.append(warnings.allocator, .{ .app = app, .file = file, .message = message });
}

/// Prints each warning as `warning: kosmos 'frost', app 'terminal.kitty', file ...: message`.
pub fn write(warnings: *const Warnings, kosmos: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (warnings.items.items) |warning|
        try Diagnostics.writeReport(writer, "warning", kosmos, warning.app, warning.file, warning.message);
}

test "write names kosmos, app and file, leaving out what is empty" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var warnings: Warnings = .init(arena.allocator());
    try warnings.add("terminal.kitty", "~/.config/kitty/kosm.conf", "reload failed: exit code {d}", .{1});
    try warnings.add("", "", "plain", .{});
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try warnings.write("frost", &writer);
    try std.testing.expectEqualStrings(
        "warning: kosmos 'frost', app 'terminal.kitty', file ~/.config/kitty/kosm.conf: reload failed: exit code 1\n" ++
            "warning: kosmos 'frost': plain\n",
        writer.buffered(),
    );
}
