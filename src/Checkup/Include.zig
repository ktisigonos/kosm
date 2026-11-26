//! A file of a program that must read a file an app writes, and the line in it that does.

const Include = @This();

const std = @import("std");

/// The program's file holding the line, starting with `~/` or `/`
/// (`~/.config/kitty/kitty.conf`).
file: []const u8,
/// The line that makes the program read the app's file (`include kosm.conf`), which
/// `kosm doctor` tells the user to add when `file` holds no line matching it.
line: []const u8,
/// Other spellings of `line` that read the same file (`include ./kosm.conf`). Default: none.
matches: []const []const u8 = &.{},

/// Whether one line of `contents`, with the whitespace around it trimmed, is `line` or one of
/// `matches`.
pub fn isIn(include: Include, contents: []const u8) bool {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, trimmed, include.line)) return true;
        for (include.matches) |match| {
            if (std.mem.eql(u8, trimmed, match)) return true;
        }
    }
    return false;
}

const testing = std.testing;

test "a line is found with the whitespace around it trimmed, in any line of the file" {
    const include: Include = .{ .file = "~/.config/kitty/kitty.conf", .line = "include kosm.conf" };
    try testing.expect(include.isIn("font_size 12\n  include kosm.conf\t\r\nmap ctrl+t new_tab\n"));
    try testing.expect(include.isIn("include kosm.conf"));
    try testing.expect(!include.isIn(""));
    try testing.expect(!include.isIn("# include kosm.conf\n"));
    try testing.expect(!include.isIn("include kosm.conf.bak\n"));
    try testing.expect(!include.isIn("include kosm\n.conf\n"));
}

test "another spelling counts when matches lists it" {
    const include: Include = .{ .file = "~/.config/kitty/kitty.conf", .line = "include kosm.conf", .matches = &.{"include ./kosm.conf"} };
    try testing.expect(include.isIn("include ./kosm.conf\n"));
    try testing.expect(!include.isIn("include ~/.config/kitty/kosm.conf\n"));
}
