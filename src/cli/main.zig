//! The `kosm` command (section 10). For now `kosm apply`, which builds the one kosmos in the
//! config project with `zig build` and runs it (D45, D66), and `kosm current` (D75).

const std = @import("std");
const Record = @import("kosm_current");

const usage =
    \\usage: kosm apply <kosmos>[.<variant>] [--<param> value]... [--set path=value]... [--diff] [--config dir]
    \\       kosm current
    \\
;

/// Where the config project lives unless `--config` says otherwise (D66), under $HOME.
const default_config = ".config/kosm";
/// What `addConfigProject` installs for `-Dkosmos=...`.
const runner_path = "zig-out/bin/kosmos";

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const arguments = try init.minimal.args.toSlice(arena);
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    // A failing stderr has nowhere left to be reported.
    defer stderr.interface.flush() catch {};

    const command = Command.parse(arena, arguments[1..]) catch |err| {
        switch (err) {
            error.NoCommand => {},
            error.UnknownCommand => try stderr.interface.print("error: unknown command '{s}'\n", .{arguments[1]}),
            error.MissingKosmos => try stderr.interface.writeAll("error: kosm apply needs a kosmos, e.g. kosm apply frost\n"),
            error.MissingConfigDirectory => try stderr.interface.writeAll("error: --config needs a directory\n"),
            error.UnexpectedArgument => try stderr.interface.writeAll("error: kosm current takes no arguments\n"),
            error.CurrentWithConfig => try stderr.interface.writeAll("error: kosm current reads no config project, so it takes no --config (D66)\n"),
            error.OutOfMemory => return error.OutOfMemory,
        }
        try stderr.interface.writeAll(usage);
        return 1;
    };
    switch (command) {
        .apply => |apply| return runApply(init, apply, &stderr.interface),
        .current => return printCurrent(init, &stderr.interface),
    }
}

/// Builds and runs the kosmos; only returns when it could not be run.
fn runApply(init: std.process.Init, command: Apply, stderr: *std.Io.Writer) !u8 {
    const arena = init.arena.allocator();
    const given_config = command.config orelse blk: {
        const home = init.environ_map.get("HOME") orelse {
            try stderr.writeAll("error: HOME is not set; pass --config\n");
            return 1;
        };
        break :blk try std.Io.Dir.path.join(arena, &.{ home, default_config });
    };
    // The runner records this path for `kosm current`, which may run from anywhere (D75).
    const config = std.Io.Dir.cwd().realPathFileAlloc(init.io, given_config, arena) catch |err| {
        try stderr.print("error: cannot open the config project {s}: {s}\n", .{ given_config, @errorName(err) });
        return 1;
    };
    try stderr.flush();

    if (!try build(init.io, arena, config, command.kosmos)) return 1;
    const runner = try std.Io.Dir.path.join(arena, &.{ config, runner_path });
    const runner_arguments = try std.mem.concat(arena, []const u8, &.{ &.{runner}, command.runner_arguments, &.{ "--config", config } });
    const err = std.process.replace(init.io, .{ .argv = runner_arguments });
    try stderr.print("error: cannot run {s}: {s}\n", .{ runner, @errorName(err) });
    return 1;
}

/// Prints the last successful apply as the command that repeats it (D75).
fn printCurrent(init: std.process.Init, stderr: *std.Io.Writer) !u8 {
    const arena = init.arena.allocator();
    const path = try Record.path(arena, init.environ_map) orelse {
        try stderr.writeAll("error: neither XDG_STATE_HOME nor HOME is set, so there is no state directory\n");
        return 1;
    };
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const loaded = Record.load(arena, init.io, path, &diagnostics) catch |err| {
        switch (err) {
            error.ParseZon => try stderr.print("{f}\n", .{diagnostics.fmt(path)}),
            else => try stderr.print("error: cannot read {s}: {s}\n", .{ path, @errorName(err) }),
        }
        return 1;
    };
    const record = loaded orelse {
        try stderr.print("error: no kosmos has been applied yet ({s} does not exist)\n", .{path});
        return 1;
    };
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try record.writeCommand(try defaultConfig(init.io, arena, init.environ_map), &stdout.interface);
    try stdout.interface.flush();
    return 0;
}

/// Runs `zig build -Dkosmos=<kosmos>` in the config project; compile errors go straight to
/// stderr, so they point at the user's files (D45). Returns whether it succeeded.
fn build(io: std.Io, arena: std.mem.Allocator, config: []const u8, kosmos: []const u8) !bool {
    const kosmos_option = try std.fmt.allocPrint(arena, "-Dkosmos={s}", .{kosmos});
    var child = try std.process.spawn(io, .{ .argv = &.{ "zig", "build", kosmos_option }, .cwd = .{ .path = config } });
    const term = try child.wait(io);
    return term.success();
}

/// `~/.config/kosm` resolved like `kosm apply` resolves `--config`, so a symlinked default
/// still matches the record; null without $HOME.
fn defaultConfig(io: std.Io, arena: std.mem.Allocator, environ: *const std.process.Environ.Map) !?[]const u8 {
    const home = environ.get("HOME") orelse return null;
    const config = try std.Io.Dir.path.join(arena, &.{ home, default_config });
    // A default that can't be resolved can't be the recorded config either.
    return std.Io.Dir.cwd().realPathFileAlloc(io, config, arena) catch config;
}

/// A command line, read.
const Command = union(enum) {
    apply: Apply,
    current,

    const ParseError = Apply.ParseError || error{ UnexpectedArgument, CurrentWithConfig };

    /// Reads the arguments without the program name.
    fn parse(arena: std.mem.Allocator, arguments: []const []const u8) ParseError!Command {
        if (arguments.len == 0) return error.NoCommand;
        if (std.mem.eql(u8, arguments[0], "current")) {
            for (arguments[1..]) |argument| {
                if (std.mem.eql(u8, argument, "--config")) return error.CurrentWithConfig;
            }
            if (arguments.len != 1) return error.UnexpectedArgument;
            return .current;
        }
        return .{ .apply = try Apply.parse(arena, arguments) };
    }
};

/// `kosm apply` with its arguments sorted: kosm's own, and the ones the kosmos gets.
const Apply = struct {
    /// As typed: "frost" or "frost.iced".
    kosmos: []const u8,
    /// The `--config` directory, or null for the default.
    config: ?[]const u8,
    /// Parameters, `--set`s and `--diff`, in order, for the kosmos runner.
    runner_arguments: []const []const u8,

    const ParseError = error{ NoCommand, UnknownCommand, MissingKosmos, MissingConfigDirectory, OutOfMemory };

    /// Reads `apply <kosmos> ...` (without the program name). `--config dir` may appear anywhere.
    fn parse(arena: std.mem.Allocator, arguments: []const []const u8) ParseError!Apply {
        if (arguments.len == 0) return error.NoCommand;
        if (!std.mem.eql(u8, arguments[0], "apply")) return error.UnknownCommand;
        var config: ?[]const u8 = null;
        var rest: std.ArrayList([]const u8) = .empty;
        var index: usize = 1;
        while (index < arguments.len) : (index += 1) {
            if (std.mem.eql(u8, arguments[index], "--config")) {
                index += 1;
                if (index == arguments.len) return error.MissingConfigDirectory;
                config = arguments[index];
            } else try rest.append(arena, arguments[index]);
        }
        if (rest.items.len == 0 or std.mem.startsWith(u8, rest.items[0], "-")) return error.MissingKosmos;
        return .{ .kosmos = rest.items[0], .config = config, .runner_arguments = rest.items[1..] };
    }
};

const testing = std.testing;

test "apply keeps --config for itself and passes the rest on in order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const command = try Apply.parse(arena.allocator(), &.{ "apply", "frost.iced", "--blur", "false", "--config", "/tmp/c", "--diff" });
    try testing.expectEqualStrings("frost.iced", command.kosmos);
    try testing.expectEqualStrings("/tmp/c", command.config.?);
    try testing.expectEqual(3, command.runner_arguments.len);
    try testing.expectEqualStrings("--blur", command.runner_arguments[0]);
    try testing.expectEqualStrings("--diff", command.runner_arguments[2]);
}

test "current takes no arguments" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(.current, try Command.parse(arena.allocator(), &.{"current"}));
    try testing.expectError(error.CurrentWithConfig, Command.parse(arena.allocator(), &.{ "current", "--config", "/c" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "current", "frost" }));
}

test "apply without a kosmos, a dangling --config or another command is an error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.NoCommand, Apply.parse(arena.allocator(), &.{}));
    try testing.expectError(error.UnknownCommand, Apply.parse(arena.allocator(), &.{"aply"}));
    try testing.expectError(error.MissingKosmos, Apply.parse(arena.allocator(), &.{"apply"}));
    try testing.expectError(error.MissingKosmos, Apply.parse(arena.allocator(), &.{ "apply", "--diff" }));
    try testing.expectError(error.MissingConfigDirectory, Apply.parse(arena.allocator(), &.{ "apply", "frost", "--config" }));
}
