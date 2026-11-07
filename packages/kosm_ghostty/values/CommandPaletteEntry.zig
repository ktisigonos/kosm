//! A custom entry of the command palette.

const CommandPaletteEntry = @This();

const std = @import("std");
const Joined = @import("../Joined.zig");
const Action = @import("action.zig").Action;

/// The name shown in the palette.
title: []const u8,
/// A longer explanation shown under it. null: none.
description: ?[]const u8 = null,
/// What the entry does.
action: Action,

/// Writes the value the way ghostty spells it (`title:"Reset",action:"csi:0m"`), every field a
/// quoted Zig string.
pub fn write(entry: CommandPaletteEntry, joined: *Joined) Joined.Error!void {
    const writer = joined.writer();
    try writer.print("title:\"{f}\"", .{std.zig.fmtString(entry.title)});
    if (entry.description) |description| try writer.print(",description:\"{f}\"", .{std.zig.fmtString(description)});
    try writer.writeAll(",action:\"");
    try entry.action.write(joined, .quoted);
    try joined.writer().writeByte('"');
}
