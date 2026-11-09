//! Reads a ghostty config file into the tree kosm matches paths against: every
//! `key = value` line is one entry of the file's table, so a repeated key (`font-family`,
//! `palette`, `keybind`) is one match per line. A value's bytes run from the first character
//! after `=` to the last on the line, quotes included, as ghostty trims them.

const std = @import("std");
const kosm = @import("kosm");
const Node = kosm.Adapter.Node;

/// An adapter `parser`: the file as one table. Nodes point into `source`.
pub fn parse(allocator: std.mem.Allocator, source: []const u8, context: *kosm.Adapter.Context) kosm.Adapter.ParseError!Node {
    var entries: std.ArrayList(Node) = .empty;
    var line_start: usize = 0;
    var line_number: usize = 1;
    while (line_start < source.len) : (line_number += 1) {
        const line_end = std.mem.indexOfScalarPos(u8, source, line_start, '\n') orelse source.len;
        if (try entry(source, line_start, line_end, line_number, context)) |node| try entries.append(allocator, node);
        line_start = line_end + 1;
    }
    return .{ .key = null, .kind = .table, .position = 0, .value = .{ .start = 0, .end = source.len }, .children = entries.items };
}

/// The entry on one line, or null for a blank or comment line.
fn entry(source: []const u8, line_start: usize, line_end: usize, line_number: usize, context: *kosm.Adapter.Context) kosm.Adapter.ParseError!?Node {
    const start = skipSpace(source, line_start, line_end);
    const end = trimEnd(source, start, line_end);
    if (start == end or source[start] == '#') return null;
    const equals = std.mem.indexOfScalarPos(u8, source[0..end], start, '=') orelse
        return context.invalidSyntax("line {d}: expected 'key = value'", .{line_number});
    const key_end = trimEnd(source, start, equals);
    if (key_end == start) return context.invalidSyntax("line {d}: the key before '=' is missing", .{line_number});
    const value_start = skipSpace(source, equals + 1, end);
    return .{
        .key = source[start..key_end],
        .kind = .scalar,
        .position = start,
        .value = .{ .start = value_start, .end = end },
    };
}

fn skipSpace(source: []const u8, start: usize, end: usize) usize {
    var index = start;
    while (index < end and isSpace(source[index])) index += 1;
    return index;
}

fn trimEnd(source: []const u8, start: usize, end: usize) usize {
    var index = end;
    while (index > start and isSpace(source[index - 1])) index -= 1;
    return index;
}

fn isSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r';
}

const testing = std.testing;

fn parseForTest(allocator: std.mem.Allocator, source: []const u8) !Node {
    var context: kosm.Adapter.Context = .{ .format = kosm.Format.kosm_default };
    return parse(allocator, source, &context);
}

fn valueText(source: []const u8, node: Node) []const u8 {
    return source[node.value.?.start..node.value.?.end];
}

test "every option line is an entry, repeated keys included, comments and blanks skipped" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source =
        \\config-file = Ricer
        \\gtk-single-instance = true
        \\
        \\  # Conflicts with many common binds, such as ones in lazy git
        \\keybind = ctrl+enter=unbind
        \\palette =  0 = 041C26
        \\palette = 15=#b7dce5
        \\foreground=a3c5cc
        \\title = "  spaced  "
        \\font-family =
        \\custom-shader = ./shaders/ghostty-cursor-shaders/cursor_warp.glsl
    ;
    const root = try parseForTest(arena.allocator(), source);
    const entries = root.children;
    try testing.expectEqual(9, entries.len);
    try testing.expectEqualStrings("config-file", entries[0].key.?);
    try testing.expectEqualStrings("Ricer", valueText(source, entries[0]));
    try testing.expectEqualStrings("ctrl+enter=unbind", valueText(source, entries[2]));
    try testing.expectEqualStrings("palette", entries[3].key.?);
    try testing.expectEqualStrings("0 = 041C26", valueText(source, entries[3]));
    try testing.expectEqualStrings("15=#b7dce5", valueText(source, entries[4]));
    try testing.expectEqualStrings("foreground", entries[5].key.?);
    try testing.expectEqualStrings("a3c5cc", valueText(source, entries[5]));
    try testing.expectEqualStrings("\"  spaced  \"", valueText(source, entries[6]));
    try testing.expectEqualStrings("", valueText(source, entries[7]));
    try testing.expectEqualStrings("./shaders/ghostty-cursor-shaders/cursor_warp.glsl", valueText(source, entries[8]));
}

test "a value keeps a # inside it, since ghostty has no trailing comments" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source = "background = #282c34\r\nselection-word-chars = #x\n";
    const root = try parseForTest(arena.allocator(), source);
    try testing.expectEqualStrings("#282c34", valueText(source, root.children[0]));
    try testing.expectEqualStrings("#x", valueText(source, root.children[1]));
}

test "a line that is not an option is an error naming it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var context: kosm.Adapter.Context = .{ .format = kosm.Format.kosm_default };
    try testing.expectError(error.InvalidSyntax, parse(arena.allocator(), "font-size = 13\nfont-size 13\n", &context));
    try testing.expectEqualStrings("line 2: expected 'key = value'", context.message());
    try testing.expectError(error.InvalidSyntax, parse(arena.allocator(), " = 13\n", &context));
    try testing.expectEqualStrings("line 1: the key before '=' is missing", context.message());
}
