//! `kosm completions <shell>`: prints the shell's completion script. Each script only asks
//! `kosm complete` what to offer, so what completes lives in one place.

const std = @import("std");

/// The shells kosm completes in.
pub const Shell = enum {
    fish,
    bash,
    zsh,

    /// The script the shell loads; its header says where to install it.
    pub fn script(shell: Shell) []const u8 {
        return switch (shell) {
            .fish => @embedFile("completions/kosm.fish"),
            .bash => @embedFile("completions/kosm.bash"),
            .zsh => @embedFile("completions/kosm.zsh"),
        };
    }
};

/// A completion script installed where its shell loads it by itself, outside the user's config.
const Installed = struct {
    shell: Shell,
    /// The folder below the data home (`XDG_DATA_HOME`, by default `~/.local/share`).
    folder: []const u8,
    file: []const u8,
};

/// zsh loads no folder of the user's by itself, so it keeps `kosm completions zsh`.
const installed = [_]Installed{
    .{ .shell = .fish, .folder = "fish/vendor_completions.d", .file = "kosm.fish" },
    .{ .shell = .bash, .folder = "bash-completion/completions", .file = "kosm" },
};

/// Writes the fish and bash scripts where each shell loads them by itself, rewriting one only
/// when it differs from this kosm's, and prints each it wrote to `stdout`. bash's folder follows
/// `BASH_COMPLETION_USER_DIR` when set, as bash-completion does. A script that cannot be written
/// is a warning on `stderr`, since completion is no reason to fail the command that installs it.
pub fn install(io: std.Io, arena: std.mem.Allocator, environ: *const std.process.Environ.Map, stdout: *std.Io.Writer, stderr: *std.Io.Writer) (std.mem.Allocator.Error || std.Io.Writer.Error)!void {
    const data_home = environ.get("XDG_DATA_HOME") orelse home: {
        const home = environ.get("HOME") orelse return stderr.writeAll("warning: HOME is not set, so kosm's shell completions are not installed\n");
        break :home try std.Io.Dir.path.join(arena, &.{ home, ".local/share" });
    };
    for (installed) |entry| {
        const folder = if (entry.shell == .bash) if (environ.get("BASH_COMPLETION_USER_DIR")) |user| try std.Io.Dir.path.join(arena, &.{ user, "completions" }) else null else null;
        const path = try std.Io.Dir.path.join(arena, &.{ folder orelse try std.Io.Dir.path.join(arena, &.{ data_home, entry.folder }), entry.file });
        const written = writeIfChanged(io, arena, path, entry.shell.script()) catch |err| {
            try stderr.print("warning: cannot install kosm's {s} completions at {s}: {s}\n", .{ @tagName(entry.shell), path, @errorName(err) });
            continue;
        };
        if (written) try stdout.print("installed {s} completions at {s}\n", .{ @tagName(entry.shell), path });
    }
}

/// Writes `contents` to `path`, creating its folder, unless the file holds them already;
/// returns whether it wrote.
fn writeIfChanged(io: std.Io, arena: std.mem.Allocator, path: []const u8, contents: []const u8) !bool {
    const current = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(contents.len + 1)) catch |err| switch (err) {
        error.FileNotFound => null,
        error.StreamTooLong => null,
        else => |other| return other,
    };
    if (current) |bytes| if (std.mem.eql(u8, bytes, contents)) return false;
    try std.Io.Dir.cwd().createDirPath(io, std.Io.Dir.path.dirname(path).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = contents });
    return true;
}

test "install writes fish and bash scripts where they load, once, following the data home" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    var environ: std.process.Environ.Map = .init(allocator);
    try environ.put("HOME", root);
    var stdout: std.Io.Writer.Allocating = .init(allocator);
    var stderr: std.Io.Writer.Allocating = .init(allocator);

    try install(std.testing.io, allocator, &environ, &stdout.writer, &stderr.writer);
    try std.testing.expectEqualStrings(try allocator.print("installed fish completions at {s}/.local/share/fish/vendor_completions.d/kosm.fish\ninstalled bash completions at {s}/.local/share/bash-completion/completions/kosm\n", .{ root, root }), stdout.written());
    try std.testing.expectEqualStrings(Shell.fish.script(), try tmp.dir.readFileAlloc(std.testing.io, ".local/share/fish/vendor_completions.d/kosm.fish", allocator, .unlimited));
    try std.testing.expectEqualStrings(Shell.bash.script(), try tmp.dir.readFileAlloc(std.testing.io, ".local/share/bash-completion/completions/kosm", allocator, .unlimited));

    stdout.clearRetainingCapacity();
    try install(std.testing.io, allocator, &environ, &stdout.writer, &stderr.writer);
    try std.testing.expectEqualStrings("", stdout.written());
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".local/share/fish/vendor_completions.d/kosm.fish", .data = "# an older kosm's\n" });
    try install(std.testing.io, allocator, &environ, &stdout.writer, &stderr.writer);
    try std.testing.expect(std.mem.startsWith(u8, stdout.written(), "installed fish completions at "));
    try std.testing.expectEqualStrings(Shell.fish.script(), try tmp.dir.readFileAlloc(std.testing.io, ".local/share/fish/vendor_completions.d/kosm.fish", allocator, .unlimited));

    stdout.clearRetainingCapacity();
    try environ.put("XDG_DATA_HOME", try std.Io.Dir.path.join(allocator, &.{ root, "data" }));
    try environ.put("BASH_COMPLETION_USER_DIR", try std.Io.Dir.path.join(allocator, &.{ root, "bash" }));
    try install(std.testing.io, allocator, &environ, &stdout.writer, &stderr.writer);
    try std.testing.expectEqualStrings(try allocator.print("installed fish completions at {s}/data/fish/vendor_completions.d/kosm.fish\ninstalled bash completions at {s}/bash/completions/kosm\n", .{ root, root }), stdout.written());
    try std.testing.expectEqualStrings("", stderr.written());
}

test "a script that cannot be written is a warning, and the other is still installed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    // A file where fish's folder would be.
    try tmp.dir.createDirPath(std.testing.io, "data");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "data/fish", .data = "" });
    var environ: std.process.Environ.Map = .init(allocator);
    try environ.put("XDG_DATA_HOME", try std.Io.Dir.path.join(allocator, &.{ root, "data" }));
    var stdout: std.Io.Writer.Allocating = .init(allocator);
    var stderr: std.Io.Writer.Allocating = .init(allocator);
    try install(std.testing.io, allocator, &environ, &stdout.writer, &stderr.writer);
    try std.testing.expect(std.mem.startsWith(u8, stderr.written(), "warning: cannot install kosm's fish completions at "));
    try std.testing.expect(std.mem.startsWith(u8, stdout.written(), "installed bash completions at "));
}

test "every shell's script asks kosm complete for the words typed so far" {
    inline for (comptime std.enums.values(Shell)) |shell| {
        const script = shell.script();
        try std.testing.expect(std.mem.find(u8, script, "kosm complete -- ") != null);
        try std.testing.expect(std.mem.find(u8, script, "kosm completions " ++ @tagName(shell)) != null);
        try std.testing.expect(std.mem.find(u8, script, "--config") != null);
    }
}
