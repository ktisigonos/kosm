//! What `kosm colors` prints: every theme in a kosmos' tree as the kosmos built it (a base keeps
//! the one its apps were built from), its palette and roles, each color with its hex value, a
//! mark on a palette color the kosmos does not set itself or that is clipped from outside sRGB
//! and, on a terminal, a block in that color.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");

/// Width of a color's block, in spaces.
const block_width = 6;
/// The names are padded to the longest one, `background`, plus a gap.
const name_width = 12;

/// Writes every `kosm.Theme` in `tree` outside its apps, in field order, each under its path in
/// the tree, with an empty line between two. Returns how many it wrote. With `blocks`, a block
/// in each color (truecolor escapes) comes before its hex value.
pub fn writeThemes(writer: *std.Io.Writer, tree: anytype, blocks: bool) std.Io.Writer.Error!usize {
    var count: usize = 0;
    try writeNode(writer, tree, "", blocks, &count);
    return count;
}

fn writeNode(writer: *std.Io.Writer, node: anytype, comptime path: []const u8, blocks: bool, count: *usize) std.Io.Writer.Error!void {
    @setEvalBranchQuota(discovery.branch_quota);
    const Node = @TypeOf(node);
    if (@typeInfo(Node) == .optional) {
        if (node) |present| try writeNode(writer, present, path, blocks, count);
        return;
    }
    if (Node == kosm.Theme) {
        if (count.* > 0) try writer.writeByte('\n');
        count.* += 1;
        return writeTheme(writer, if (path.len == 0) "theme" else path, node, blocks);
    }
    // An app's own theme is the one it was built from, which the tree's already shows.
    if (comptime discovery.isApp(Node) or @typeInfo(Node) != .@"struct") return;
    inline for (@typeInfo(Node).@"struct".field_names) |name| {
        try writeNode(writer, @field(node, name), if (path.len == 0) name else path ++ "." ++ name, blocks, count);
    }
}

/// A line naming the theme (`base.theme: Krystallos, dark`, with its background alpha when
/// below 1), then the palette (black, white, gray and the 12 hues in wheel order, `mixed` after
/// a color the kosmos does not set itself) and the roles, a color per line as `name  #rrggbb`,
/// with `clipped` after one outside sRGB, whose hex value is the nearest in it.
pub fn writeTheme(writer: *std.Io.Writer, path: []const u8, theme: kosm.Theme, blocks: bool) std.Io.Writer.Error!void {
    try writer.print("{s}: ", .{path});
    if (theme.name) |name| try writer.print("{s}, ", .{name});
    try writer.writeAll(@tagName(theme.mode));
    if (theme.background_alpha < 1) try writer.print(", background alpha {d}", .{theme.background_alpha});
    try writer.writeAll("\npalette\n");
    try writeColor(writer, "black", theme.palette.black, false, blocks);
    try writeColor(writer, "white", theme.palette.white, false, blocks);
    try writeColor(writer, "gray", theme.palette.gray, true, blocks);
    inline for (@typeInfo(kosm.Palette.Hue).@"enum".field_names) |hue| {
        try writeColor(writer, hue, @field(theme.palette, hue), @field(theme.input.palette, hue) == null, blocks);
    }
    try writer.writeAll("roles\n");
    inline for (@typeInfo(kosm.Theme.Roles).@"struct".field_names) |role| {
        try writeColor(writer, role, @field(theme.roles, role), false, blocks);
    }
}

fn writeColor(writer: *std.Io.Writer, name: []const u8, color: kosm.Color, mixed: bool, blocks: bool) std.Io.Writer.Error!void {
    const hex = color.hex();
    try writer.writeAll("  ");
    try writer.writeAll(name);
    try writer.splatByteAll(' ', name_width - name.len);
    if (blocks) {
        const digits = hex.slice()[1..];
        // The hex text always holds six digits, so parsing them cannot fail.
        const red = std.fmt.parseInt(u8, digits[0..2], 16) catch unreachable;
        const green = std.fmt.parseInt(u8, digits[2..4], 16) catch unreachable;
        const blue = std.fmt.parseInt(u8, digits[4..6], 16) catch unreachable;
        try writer.print("\x1b[48;2;{d};{d};{d}m", .{ red, green, blue });
        try writer.splatByteAll(' ', block_width);
        try writer.writeAll("\x1b[0m  ");
    }
    try writer.writeAll(hex.slice());
    if (mixed) try writer.writeAll("  mixed");
    if (color.clips(.hex)) try writer.writeAll("  clipped");
    try writer.writeByte('\n');
}

const testing = std.testing;

const frost_palette: kosm.Palette = .{ .black = kosm.hex("000000"), .white = kosm.hex("ffffff"), .red = kosm.hex("ff0000"), .cyan = kosm.hex("00ffff") };

/// An app holding the theme it was built from, which `writeThemes` must not show twice.
const ThemedApp = struct {
    theme: kosm.Theme,

    pub fn apply(self: ThemedApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

const Base = struct { kitty: ?ThemedApp, theme: kosm.Theme };
const Tree = struct { base: Base, spare: ?Base, size: u32 };

fn frostTree() Tree {
    var theme: kosm.Theme = .from(.{ .palette = frost_palette, .mode = .light });
    theme.name = "Frost";
    theme.background_alpha = 0.75;
    return .{ .base = .{ .kitty = .{ .theme = theme }, .theme = theme }, .spare = null, .size = 3 };
}

fn written(tree: anytype, blocks: bool, count: usize) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer text.deinit();
    try testing.expectEqual(count, try writeThemes(&text.writer, tree, blocks));
    return text.toOwnedSlice();
}

test "the themes of a tree are found by path, outside its apps and null optionals" {
    const text = try written(frostTree(), false, 1);
    defer testing.allocator.free(text);
    try testing.expectStringStartsWith(text,
        \\base.theme: Frost, light, background alpha 0.75
        \\palette
        \\  black       #000000
        \\  white       #ffffff
        \\  gray        #
    );
    try testing.expect(std.mem.find(u8, text, "  red         #ff0000\n") != null);
    try testing.expect(std.mem.find(u8, text, "  cyan        #00ffff\n") != null);
    try testing.expect(std.mem.find(u8, text, "\nroles\n  background  #") != null);
    try testing.expect(std.mem.find(u8, text, "\n  error       #") != null);
    try testing.expect(std.mem.find(u8, text, "\x1b") == null);

    var both = frostTree();
    both.spare = both.base;
    const twice = try written(both, false, 2);
    defer testing.allocator.free(twice);
    try testing.expect(std.mem.find(u8, twice, "\n\nspare.theme: Frost, light") != null);
    const none = try written(struct { size: u32 }{ .size = 1 }, false, 0);
    defer testing.allocator.free(none);
    try testing.expectEqualStrings("", none);
}

test "a palette color the kosmos does not set is marked mixed" {
    const text = try written(frostTree(), false, 1);
    defer testing.allocator.free(text);
    const palette_text = text[0..std.mem.find(u8, text, "roles\n").?];
    var lines = std.mem.splitScalar(u8, palette_text, '\n');
    var mixed: usize = 0;
    while (lines.next()) |line| {
        if (std.mem.find(u8, line, "  mixed") != null) mixed += 1;
    }
    // Gray and the ten hues between red and cyan.
    try testing.expectEqual(11, mixed);
}

test "a dark theme without a name or alpha shows only its mode, and clipped colors are marked" {
    const vivid: kosm.Palette = .{ .black = kosm.hex("000000"), .white = kosm.hex("ffffff"), .green = .{ .lightness = 0.9, .chroma = 0.4, .hue = 140 } };
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try writeTheme(&text.writer, "theme", .from(.{ .palette = vivid, .mode = .dark }), false);
    try testing.expectStringStartsWith(text.written(), "theme: dark\npalette\n");
    try testing.expect(std.mem.find(u8, text.written(), "  green       #00ff00  clipped\n") != null);
    try testing.expect(std.mem.find(u8, text.written(), "  white       #ffffff\n") != null);
}

test "with blocks each color is drawn in truecolor before its hex value" {
    const text = try written(frostTree(), true, 1);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.find(u8, text, "  red         \x1b[48;2;255;0;0m      \x1b[0m  #ff0000\n") != null);
    try testing.expect(std.mem.find(u8, text, "palette\n  black       \x1b[48;2;0;0;0m      \x1b[0m  #000000\n") != null);
}
