//! The last successful apply, kept in the state directory for `kosm current` (D75).

const Record = @This();

const std = @import("std");

/// The kosmos as typed: "frost" or "frost.iced".
kosmos: []const u8,
/// Its parameters and `--set`s, in the order typed; never `--diff` or `--config`.
arguments: []const []const u8,
/// The config project's absolute path.
config: []const u8,

/// Where the record lives under the state directory.
const relative_path = "kosm/current.zon";
/// The state directory under $HOME when $XDG_STATE_HOME is unset.
const default_state_home = ".local/state";

/// `$XDG_STATE_HOME/kosm/current.zon`, else `$HOME/.local/state/kosm/current.zon`; null when
/// neither is set. A relative $XDG_STATE_HOME is ignored, as the XDG spec asks.
pub fn path(allocator: std.mem.Allocator, environ: *const std.process.Environ.Map) std.mem.Allocator.Error!?[]const u8 {
    if (environ.get("XDG_STATE_HOME")) |state_home| {
        if (std.Io.Dir.path.isAbsolute(state_home)) return try std.Io.Dir.path.join(allocator, &.{ state_home, relative_path });
    }
    const home = environ.get("HOME") orelse return null;
    return try std.Io.Dir.path.join(allocator, &.{ home, default_state_home, relative_path });
}

/// Replaces the record at `file_path` atomically, creating its directories.
pub fn save(record: Record, io: std.Io, file_path: []const u8) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, file_path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    var buffer: [1024]u8 = undefined;
    var file_writer = atomic.file.writer(io, &buffer);
    record.writeZon(&file_writer.interface) catch return file_writer.err orelse error.WriteFailed;
    file_writer.interface.flush() catch return file_writer.err orelse error.WriteFailed;
    try atomic.replace(io);
}

fn writeZon(record: Record, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try std.zon.stringify.serialize(record, .{}, writer);
    try writer.writeByte('\n');
}

pub const LoadError = error{ ParseZon, OutOfMemory } || std.Io.Dir.ReadFileAllocError;

/// Reads the record at `file_path` into `arena`; null when there is none yet. On
/// `error.ParseZon`, `diagnostics` says what is wrong with the file.
pub fn load(arena: std.mem.Allocator, io: std.Io, file_path: []const u8, diagnostics: *std.zon.parse.Diagnostics) LoadError!?Record {
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, file_path, arena, .limited(max_size), .of(u8), 0) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |other| return other,
    };
    return try std.zon.parse.fromSlice(Record, .{ .gpa = arena, .arena = arena, .source = source, .diagnostics = diagnostics });
}

/// A record is a few lines; anything bigger is not one.
const max_size = 1024 * 1024;

/// Prints the command that applies this record again:
/// `kosm apply frost.iced --accent '#ff0000' --config /home/user/.config/kosm`.
pub fn writeCommand(record: Record, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll("kosm apply ");
    try writeShellWord(writer, record.kosmos);
    for (record.arguments) |argument| {
        try writer.writeByte(' ');
        try writeShellWord(writer, argument);
    }
    try writer.writeAll(" --config ");
    try writeShellWord(writer, record.config);
    try writer.writeByte('\n');
}

/// Writes `word` so a POSIX shell reads it back unchanged, quoting only when needed.
fn writeShellWord(writer: *std.Io.Writer, word: []const u8) std.Io.Writer.Error!void {
    const plain = word.len != 0 and for (word) |character| {
        if (!isPlainShellCharacter(character)) break false;
    } else true;
    if (plain) return writer.writeAll(word);
    try writer.writeByte('\'');
    for (word) |character| {
        if (character == '\'') try writer.writeAll("'\\''") else try writer.writeByte(character);
    }
    try writer.writeByte('\'');
}

fn isPlainShellCharacter(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or std.mem.findScalar(u8, "_-./=:,+@%", character) != null;
}

const testing = std.testing;

test "path prefers an absolute XDG_STATE_HOME and falls back to HOME" {
    var environ: std.process.Environ.Map = .init(testing.allocator);
    defer environ.deinit();
    try testing.expectEqual(null, try path(testing.allocator, &environ));

    try environ.put("HOME", "/home/user");
    const from_home = (try path(testing.allocator, &environ)).?;
    defer testing.allocator.free(from_home);
    try testing.expectEqualStrings("/home/user/.local/state/kosm/current.zon", from_home);

    try environ.put("XDG_STATE_HOME", "relative/state");
    const ignoring_relative = (try path(testing.allocator, &environ)).?;
    defer testing.allocator.free(ignoring_relative);
    try testing.expectEqualStrings("/home/user/.local/state/kosm/current.zon", ignoring_relative);

    try environ.put("XDG_STATE_HOME", "/state");
    const from_state_home = (try path(testing.allocator, &environ)).?;
    defer testing.allocator.free(from_state_home);
    try testing.expectEqualStrings("/state/kosm/current.zon", from_state_home);
}

test "a saved record loads back, and a missing one is null" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory = buffer[0..try tmp.dir.realPath(testing.io, &buffer)];
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const file_path = try std.Io.Dir.path.join(arena.allocator(), &.{ directory, "kosm", "current.zon" });
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    try testing.expectEqual(null, try load(arena.allocator(), testing.io, file_path, &diagnostics));

    const record: Record = .{ .kosmos = "frost.iced", .arguments = &.{ "--blur", "false", "--set", "kitty.title=\"a\"" }, .config = "/c" };
    try record.save(testing.io, file_path);
    const loaded = (try load(arena.allocator(), testing.io, file_path, &diagnostics)).?;
    try testing.expectEqualDeep(record, loaded);
}

test "a broken record is a parse error" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "current.zon", .data = ".{ .kosmos = 1 }" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory = buffer[0..try tmp.dir.realPath(testing.io, &buffer)];
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const file_path = try std.Io.Dir.path.join(arena.allocator(), &.{ directory, "current.zon" });
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    try testing.expectError(error.ParseZon, load(arena.allocator(), testing.io, file_path, &diagnostics));
}

test "the command quotes only the words a shell would split or expand" {
    const record: Record = .{ .kosmos = "frost.iced", .arguments = &.{ "--accent", "#ff0000", "--set", "kitty.title=it's", "--name", "" }, .config = "/home/user/.config/kosm" };
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try record.writeCommand(&writer);
    try testing.expectEqualStrings(
        "kosm apply frost.iced --accent '#ff0000' --set 'kitty.title=it'\\''s' --name '' --config /home/user/.config/kosm\n",
        writer.buffered(),
    );
}
