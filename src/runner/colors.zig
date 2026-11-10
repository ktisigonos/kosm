//! What `kosm colors` prints: every palette a kosmos' file declares, each color with its hex
//! value and, on a terminal, a block in that color.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const interface = @import("kosm_interface");

/// The argument asking for colored blocks. The command line passes it when its own stdout is a
/// terminal, since this program's stdout is the command line's pipe.
pub const blocks_argument = "--blocks";

/// A palette found in a kosmos' file, under its declaration's name.
pub const Named = struct { name: []const u8, palette: kosm.Palette };

/// Width of a color's block, in spaces.
const block_width = 6;
/// The names are padded to the longest one, `magenta`, plus a gap.
const name_width = 9;

/// Prints every public `kosm.Palette` at the top of `File`, the file of kosmos `name`, to
/// stdout and returns 0, or says on stderr that it declares none and returns 1.
pub fn colors(init: std.process.Init, comptime name: []const u8, comptime File: type) !u8 {
    const palettes = comptime declaredPalettes(File);
    var stderr_buffer: [512]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    if (!try interface.check(init.environ_map, &stderr.interface)) {
        try stderr.interface.flush();
        return 1;
    }
    if (palettes.len == 0) {
        try stderr.interface.print("error: kosmos '{s}' declares no public kosm.Palette, so there are no colors to show; make its palette a `pub const` at the top of its file (root.zig for a directory kosmos)\n", .{name});
        try stderr.interface.flush();
        return 1;
    }
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const blocks = for (arguments[1..]) |argument| {
        if (std.mem.eql(u8, argument, blocks_argument)) break true;
    } else false;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    for (palettes, 0..) |named, index| {
        if (index > 0) try stdout.interface.writeByte('\n');
        try write(&stdout.interface, named, blocks);
    }
    try stdout.interface.flush();
    return 0;
}

/// Every public `kosm.Palette` constant declared at the top of `File`.
pub fn declaredPalettes(comptime File: type) []const Named {
    @setEvalBranchQuota(discovery.branch_quota);
    comptime var found: []const Named = &.{};
    inline for (@typeInfo(File).@"struct".decl_names) |name| {
        if (@TypeOf(@field(File, name)) == kosm.Palette) found = found ++ .{Named{ .name = name, .palette = @field(File, name) }};
    }
    const final = found[0..found.len].*;
    return &final;
}

/// One line for the palette's name, then one per color: black, white, gray and the 12 hues in
/// wheel order, each `name  #rrggbb`, with `mixed` after a color the palette does not set
/// itself. With `blocks`, a block in the color (truecolor escapes) comes before its hex value.
pub fn write(writer: *std.Io.Writer, named: Named, blocks: bool) std.Io.Writer.Error!void {
    const resolved = named.palette.resolve();
    try writer.print("{s}\n", .{named.name});
    try writeColor(writer, "black", resolved.black, false, blocks);
    try writeColor(writer, "white", resolved.white, false, blocks);
    try writeColor(writer, "gray", resolved.gray, true, blocks);
    inline for (@typeInfo(kosm.Palette.Hue).@"enum".field_names) |hue| {
        try writeColor(writer, hue, @field(resolved, hue), @field(named.palette, hue) == null, blocks);
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
    try writer.writeByte('\n');
}

const testing = std.testing;

const TestKosmos = struct {
    pub const frost: kosm.Palette = .{ .black = kosm.hex("000000"), .white = kosm.hex("ffffff"), .red = kosm.hex("ff0000"), .cyan = kosm.hex("00ffff") };
    pub const answer = 42;
    const hidden: kosm.Palette = .{ .black = kosm.hex("000000"), .white = kosm.hex("ffffff") };
    pub const dusk: kosm.Palette = .{ .black = kosm.hex("101010"), .white = kosm.hex("f0f0f0") };

    pub fn kosmos() void {
        _ = hidden;
    }
};

test "only the public palettes of a file are found, in order" {
    const found = comptime declaredPalettes(TestKosmos);
    try testing.expectEqual(2, found.len);
    try testing.expectEqualStrings("frost", found[0].name);
    try testing.expectEqualStrings("dusk", found[1].name);
    try testing.expectEqual(0, (comptime declaredPalettes(struct {})).len);
}

test "without blocks a palette is plain text, hues it does not set marked as mixed" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try write(&text.writer, comptime declaredPalettes(TestKosmos)[0], false);
    const written = text.written();
    try testing.expectStringStartsWith(written,
        \\frost
        \\  black    #000000
        \\  white    #ffffff
        \\  gray     #
    );
    try testing.expect(std.mem.find(u8, written, "  red      #ff0000\n") != null);
    try testing.expect(std.mem.find(u8, written, "  cyan     #00ffff\n") != null);
    try testing.expect(std.mem.find(u8, written, "\x1b") == null);
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, written, "\n"), '\n');
    var count: usize = 0;
    var mixed: usize = 0;
    while (lines.next()) |line| {
        count += 1;
        if (std.mem.endsWith(u8, line, "  mixed")) mixed += 1;
    }
    try testing.expectEqual(16, count);
    // Gray and the ten hues between red and cyan.
    try testing.expectEqual(11, mixed);
    // Orange sits between red and cyan on the wheel, so it is neither.
    try testing.expect(std.mem.find(u8, written, "  orange   #ff0000") == null);
    try testing.expect(std.mem.find(u8, written, "  orange   #") != null);
}

test "with blocks each color is drawn in truecolor before its hex value" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try write(&text.writer, comptime declaredPalettes(TestKosmos)[0], true);
    try testing.expect(std.mem.find(u8, text.written(), "  red      \x1b[48;2;255;0;0m      \x1b[0m  #ff0000\n") != null);
    try testing.expect(std.mem.find(u8, text.written(), "  cyan     \x1b[48;2;0;255;255m      \x1b[0m  #00ffff\n") != null);
    try testing.expectStringStartsWith(text.written(), "frost\n  black    \x1b[48;2;0;0;0m      \x1b[0m  #000000\n");
}
