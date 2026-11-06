//! The `kosm` command (section 10). For now only `kosm apply`: build the one kosmos in the
//! config project with `zig build`, then run it (D45, D66).

const std = @import("std");

const usage =
    \\usage: kosm apply <kosmos>[.<variant>] [--<param> value]... [--set path=value]... [--diff] [--config dir]
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

    const command = Apply.parse(arena, arguments[1..]) catch |err| {
        switch (err) {
            error.NoCommand => {},
            error.UnknownCommand => try stderr.interface.print("error: unknown command '{s}'\n", .{arguments[1]}),
            error.MissingKosmos => try stderr.interface.writeAll("error: kosm apply needs a kosmos, e.g. kosm apply frost\n"),
            error.MissingConfigDirectory => try stderr.interface.writeAll("error: --config needs a directory\n"),
            error.OutOfMemory => return error.OutOfMemory,
        }
        try stderr.interface.writeAll(usage);
        return 1;
    };
    const config = command.config orelse blk: {
        const home = init.environ_map.get("HOME") orelse {
            try stderr.interface.writeAll("error: HOME is not set; pass --config\n");
            return 1;
        };
        break :blk try std.Io.Dir.path.join(arena, &.{ home, default_config });
    };
    try stderr.interface.flush();

    if (!try build(init.io, arena, config, command.kosmos)) return 1;
    const runner = try std.Io.Dir.path.join(arena, &.{ config, runner_path });
    const runner_arguments = try std.mem.concat(arena, []const u8, &.{ &.{runner}, command.runner_arguments });
    const err = std.process.replace(init.io, .{ .argv = runner_arguments });
    try stderr.interface.print("error: cannot run {s}: {s}\n", .{ runner, @errorName(err) });
    return 1;
}

/// Runs `zig build -Dkosmos=<kosmos>` in the config project; compile errors go straight to
/// stderr, so they point at the user's files (D45). Returns whether it succeeded.
fn build(io: std.Io, arena: std.mem.Allocator, config: []const u8, kosmos: []const u8) !bool {
    const kosmos_option = try std.fmt.allocPrint(arena, "-Dkosmos={s}", .{kosmos});
    var child = try std.process.spawn(io, .{ .argv = &.{ "zig", "build", kosmos_option }, .cwd = .{ .path = config } });
    const term = try child.wait(io);
    return term.success();
}

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

test "apply without a kosmos, a dangling --config or another command is an error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.NoCommand, Apply.parse(arena.allocator(), &.{}));
    try testing.expectError(error.UnknownCommand, Apply.parse(arena.allocator(), &.{"aply"}));
    try testing.expectError(error.MissingKosmos, Apply.parse(arena.allocator(), &.{"apply"}));
    try testing.expectError(error.MissingKosmos, Apply.parse(arena.allocator(), &.{ "apply", "--diff" }));
    try testing.expectError(error.MissingConfigDirectory, Apply.parse(arena.allocator(), &.{ "apply", "frost", "--config" }));
}
