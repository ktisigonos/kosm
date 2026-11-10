//! The `kosm` command (section 10). For now `kosm init`, `kosm apply`, which builds
//! the one kosmos in the config project with `zig build` and runs it, `kosm list`
//!, `kosm new`, `kosm current`, and the package commands `kosm add`, `kosm remove` and
//! `kosm update`, and `kosm source`. Applying a directory kosmos also refreshes its own
//! manifest. Every build runs with the kosm sources `Sources` finds.

const std = @import("std");
const Record = @import("kosm_current");
const package_commands = @import("package_commands.zig");
const directory_package = @import("directory_package.zig");
const Context = @import("Context.zig");
const init_command = @import("init.zig");
const list_command = @import("list.zig");
const new_command = @import("new.zig");
const source_command = @import("source.zig");
const Sources = @import("Sources.zig");
const interface = @import("kosm_interface");

const usage =
    \\usage: kosm init [--config dir]
    \\       kosm new kosmos|app|adapter <name> [--config dir]
    \\       kosm apply <kosmos>[.<variant>] [--<param> value]... [--set path=value]... [--diff] [--config dir]
    \\       kosm list [kosmos] [--config dir]
    \\       kosm current
    \\       kosm source [<dir> | --default]
    \\       kosm add <url>[#ref] [--config dir]
    \\       kosm remove <name> [--config dir]
    \\       kosm update [name] [--config dir]
    \\
;

/// Where the config project lives unless `--config` says otherwise, under $HOME.
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
            error.MissingArgument, error.UnexpectedArgument => try stderr.interface.print("error: kosm {s} takes {s}\n", .{ arguments[1], expectedArguments(arguments[1]) }),
            error.UnknownKind => try stderr.interface.writeAll("error: kosm new makes a kosmos, an app or an adapter, e.g. kosm new app my_bar\n"),
            error.ConfigNotRead => try stderr.interface.print("error: kosm {s} reads no config project, so it takes no --config\n", .{arguments[1]}),
            error.OutOfMemory => return error.OutOfMemory,
        }
        try stderr.interface.writeAll(usage);
        return 1;
    };
    switch (command) {
        .current => return printCurrent(init, &stderr.interface),
        .source => |directory| return source_command.source(init, directory, &stderr.interface),
        else => {},
    }
    const builds = try Builds.prepare(init, &stderr.interface) orelse return 1;
    switch (command) {
        .apply => |apply| return runApply(init, builds, apply, &stderr.interface),
        .init => |init_arguments| return runInit(init, builds, init_arguments, &stderr.interface),
        .new => |new| return runNew(init, builds, new, &stderr.interface),
        .add, .remove, .update, .list => |config_command| return runConfigCommand(init, builds, command, config_command, &stderr.interface),
        .current, .source => unreachable, // Handled above.
    }
}

/// What every `zig build` kosm runs, and every program it builds, runs with.
const Builds = struct {
    /// Kosm's environment plus the interface number the runner checks.
    environ: *const std.process.Environ.Map,
    /// The sources builds use in place of a config's pinned kosm, or null for the pinned one.
    sources: ?Sources,

    /// Null after printing why the sources can't be found (a broken `kosm source` record).
    fn prepare(init: std.process.Init, stderr: *std.Io.Writer) !?Builds {
        const arena = init.arena.allocator();
        const environ = try arena.create(std.process.Environ.Map);
        environ.* = try init.environ_map.clone(arena);
        try environ.put(interface.environment_variable, try std.fmt.allocPrint(arena, "{d}", .{interface.version}));
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const sources = Sources.find(init.io, arena, init.environ_map, &diagnostics) catch |err| {
            const path = try Sources.overridePath(arena, init.environ_map) orelse "";
            switch (err) {
                error.ParseZon => try stderr.print("{f}\n", .{diagnostics.fmt(path)}),
                else => try stderr.print("error: cannot read {s}: {s}; fix it, or remove it with kosm source --default\n", .{ path, @errorName(err) }),
            }
            return null;
        };
        return .{ .environ = environ, .sources = sources };
    }

    fn context(builds: Builds, init: std.process.Init, config: []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) Context {
        return .{ .io = init.io, .arena = init.arena.allocator(), .config = config, .environ_map = builds.environ, .sources = builds.sources, .stdout = stdout, .stderr = stderr };
    }
};

/// What each command takes, for argument errors.
fn expectedArguments(command: []const u8) []const u8 {
    if (std.mem.eql(u8, command, "add")) return "one url, e.g. kosm add git+https://example.com/kosm_kitty#main";
    if (std.mem.eql(u8, command, "remove")) return "one package name, e.g. kosm remove kosm_kitty";
    if (std.mem.eql(u8, command, "update")) return "at most one package name";
    if (std.mem.eql(u8, command, "list")) return "at most one kosmos, e.g. kosm list frost";
    if (std.mem.eql(u8, command, "new")) return "a kind and a name, e.g. kosm new app my_bar";
    if (std.mem.eql(u8, command, "source")) return "at most one directory, or --default";
    return "no arguments";
}

/// The config project's absolute path: `--config` or the default. Null after printing
/// why there is none.
fn configPath(init: std.process.Init, given: ?[]const u8, stderr: *std.Io.Writer) !?[]const u8 {
    const arena = init.arena.allocator();
    const given_config = given orelse blk: {
        const home = init.environ_map.get("HOME") orelse {
            try stderr.writeAll("error: HOME is not set; pass --config\n");
            return null;
        };
        break :blk try std.Io.Dir.path.join(arena, &.{ home, default_config });
    };
    return std.Io.Dir.cwd().realPathFileAlloc(init.io, given_config, arena) catch |err| {
        try stderr.print("error: cannot open the config project {s}: {s}\n", .{ given_config, @errorName(err) });
        return null;
    };
}

/// Creates the config directory when it is missing, then whatever the project lacks in it.
fn runInit(init: std.process.Init, builds: Builds, command: ConfigCommand, stderr: *std.Io.Writer) !u8 {
    const arena = init.arena.allocator();
    const given = command.config orelse blk: {
        const home = init.environ_map.get("HOME") orelse {
            try stderr.writeAll("error: HOME is not set; pass --config\n");
            return 1;
        };
        break :blk try std.Io.Dir.path.join(arena, &.{ home, default_config });
    };
    std.Io.Dir.cwd().createDirPath(init.io, given) catch |err| {
        try stderr.print("error: cannot create the config project {s}: {s}\n", .{ given, @errorName(err) });
        return 1;
    };
    const config = try configPath(init, given, stderr) orelse return 1;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    const context = builds.context(init, config, &stdout.interface, stderr);
    init_command.init(context, init_command.official) catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    return 0;
}

/// Scaffolds a directory package in the config project.
fn runNew(init: std.process.Init, builds: Builds, command: New, stderr: *std.Io.Writer) !u8 {
    const config = try configPath(init, command.config, stderr) orelse return 1;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    const context = builds.context(init, config, &stdout.interface, stderr);
    new_command.new(context, command.kind, command.name) catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    return 0;
}

/// Builds and runs the kosmos; only returns when it could not be run.
fn runApply(init: std.process.Init, builds: Builds, command: Apply, stderr: *std.Io.Writer) !u8 {
    const arena = init.arena.allocator();
    // The runner records this path for `kosm current`, which may run from anywhere.
    const config = try configPath(init, command.config, stderr) orelse return 1;
    try stderr.flush();

    if (!try build(builds.context(init, config, stderr, stderr), command.kosmos)) return 1;
    if (!try refreshManifest(init, builds, config, command, stderr)) return 1;
    const runner = try std.Io.Dir.path.join(arena, &.{ config, runner_path });
    const runner_arguments = try std.mem.concat(arena, []const u8, &.{ &.{runner}, command.runner_arguments, &.{ "--config", config } });
    const err = std.process.replace(init.io, .{ .argv = runner_arguments, .environ_map = builds.environ });
    try stderr.print("error: cannot run {s}: {s}\n", .{ runner, @errorName(err) });
    return 1;
}

/// Brings a directory kosmos' manifest up to date, or on `--diff` only says what would
/// change. Returns whether the apply can go on.
fn refreshManifest(init: std.process.Init, builds: Builds, config: []const u8, command: Apply, stderr: *std.Io.Writer) !bool {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const context = builds.context(init, config, &stdout.interface, stderr);
    directory_package.refreshApplied(context, command.kosmos, if (command.diff) .report else .write) catch |err| switch (err) {
        error.Failed => return false,
        else => |other| return other,
    };
    // The runner replaces this process, so nothing buffered may be left behind.
    try stdout.interface.flush();
    try stderr.flush();
    return true;
}

/// Runs `kosm add`, `kosm remove`, `kosm update` or `kosm list` against the config project.
fn runConfigCommand(init: std.process.Init, builds: Builds, command: Command, config_command: ConfigCommand, stderr: *std.Io.Writer) !u8 {
    const config = try configPath(init, config_command.config, stderr) orelse return 1;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    const context = builds.context(init, config, &stdout.interface, stderr);
    const result = switch (command) {
        .add => package_commands.add(context, config_command.argument.?),
        .remove => package_commands.remove(context, config_command.argument.?),
        .update => package_commands.update(context, config_command.argument),
        .list => list_command.list(context, config_command.argument),
        .apply, .current, .init, .new, .source => unreachable, // main passes only these four here.
    };
    result catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    return 0;
}

/// Prints the last successful apply as the command that repeats it.
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
/// stderr, so they point at the user's files. Returns whether it succeeded.
fn build(context: Context, kosmos: []const u8) !bool {
    const kosmos_option = try std.fmt.allocPrint(context.arena, "-Dkosmos={s}", .{kosmos});
    const argv = try context.zigArguments(&.{ "build", kosmos_option });
    var child = try std.process.spawn(context.io, .{ .argv = argv, .cwd = .{ .path = context.config }, .environ_map = context.environ_map });
    const term = try child.wait(context.io);
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
    init: ConfigCommand,
    apply: Apply,
    current,
    /// The directory, `--default`, or null to print which sources builds use.
    source: ?[]const u8,
    new: New,
    list: ConfigCommand,
    add: ConfigCommand,
    remove: ConfigCommand,
    update: ConfigCommand,

    const ParseError = Apply.ParseError || New.ParseError || error{ConfigNotRead};

    /// Reads the arguments without the program name.
    fn parse(arena: std.mem.Allocator, arguments: []const []const u8) ParseError!Command {
        if (arguments.len == 0) return error.NoCommand;
        if (std.mem.eql(u8, arguments[0], "current")) {
            for (arguments[1..]) |argument| {
                if (std.mem.eql(u8, argument, "--config")) return error.ConfigNotRead;
            }
            if (arguments.len != 1) return error.UnexpectedArgument;
            return .current;
        }
        if (std.mem.eql(u8, arguments[0], "source")) {
            for (arguments[1..]) |argument| {
                if (std.mem.eql(u8, argument, "--config")) return error.ConfigNotRead;
            }
            if (arguments.len > 2) return error.UnexpectedArgument;
            return .{ .source = if (arguments.len == 2) arguments[1] else null };
        }
        if (std.mem.eql(u8, arguments[0], "init")) return .{ .init = try .parse(arguments[1..], .none) };
        if (std.mem.eql(u8, arguments[0], "new")) return .{ .new = try .parse(arguments[1..]) };
        if (std.mem.eql(u8, arguments[0], "list")) return .{ .list = try .parse(arguments[1..], .optional) };
        if (std.mem.eql(u8, arguments[0], "add")) return .{ .add = try .parse(arguments[1..], .required) };
        if (std.mem.eql(u8, arguments[0], "remove")) return .{ .remove = try .parse(arguments[1..], .required) };
        if (std.mem.eql(u8, arguments[0], "update")) return .{ .update = try .parse(arguments[1..], .optional) };
        return .{ .apply = try Apply.parse(arena, arguments) };
    }
};

/// A command working on a config project, with at most one argument and `--config`:
/// `init`, `list`, `add`, `remove` or `update`.
const ConfigCommand = struct {
    /// add: the url and ref; remove: the name; update: the name, or null for every package;
    /// list: the kosmos, or null for everything; init: always null.
    argument: ?[]const u8,
    /// The `--config` directory, or null for the default.
    config: ?[]const u8,

    const Argument = enum { required, optional, none };
    const ParseError = error{ MissingArgument, UnexpectedArgument, MissingConfigDirectory };

    /// Reads the arguments after the command's name. `--config dir` may appear anywhere.
    fn parse(arguments: []const []const u8, argument: Argument) ParseError!ConfigCommand {
        var command: ConfigCommand = .{ .argument = null, .config = null };
        var index: usize = 0;
        while (index < arguments.len) : (index += 1) {
            if (std.mem.eql(u8, arguments[index], "--config")) {
                index += 1;
                if (index == arguments.len) return error.MissingConfigDirectory;
                command.config = arguments[index];
            } else if (argument == .none or command.argument != null or std.mem.startsWith(u8, arguments[index], "-")) {
                return error.UnexpectedArgument;
            } else command.argument = arguments[index];
        }
        if (argument == .required and command.argument == null) return error.MissingArgument;
        return command;
    }
};

/// `kosm new <kind> <name> [--config dir]`.
const New = struct {
    kind: new_command.Kind,
    name: []const u8,
    /// The `--config` directory, or null for the default.
    config: ?[]const u8,

    const ParseError = ConfigCommand.ParseError || error{UnknownKind};

    /// Reads the arguments after `new`. `--config dir` may appear anywhere.
    fn parse(arguments: []const []const u8) ParseError!New {
        var words: [2][]const u8 = undefined;
        var count: usize = 0;
        var config: ?[]const u8 = null;
        var index: usize = 0;
        while (index < arguments.len) : (index += 1) {
            if (std.mem.eql(u8, arguments[index], "--config")) {
                index += 1;
                if (index == arguments.len) return error.MissingConfigDirectory;
                config = arguments[index];
            } else if (count == words.len or std.mem.startsWith(u8, arguments[index], "-")) {
                return error.UnexpectedArgument;
            } else {
                words[count] = arguments[index];
                count += 1;
            }
        }
        if (count < words.len) return error.MissingArgument;
        const kind = std.meta.stringToEnum(new_command.Kind, words[0]) orelse return error.UnknownKind;
        return .{ .kind = kind, .name = words[1], .config = config };
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
    /// Whether `--diff` is among them, read like the runner reads it.
    diff: bool,

    const ParseError = error{ NoCommand, UnknownCommand, MissingKosmos, MissingConfigDirectory, OutOfMemory };

    /// Reads `apply <kosmos> ...` (without the program name). `--config dir` may appear anywhere.
    fn parse(arena: std.mem.Allocator, arguments: []const []const u8) ParseError!Apply {
        if (arguments.len == 0) return error.NoCommand;
        if (!std.mem.eql(u8, arguments[0], "apply")) return error.UnknownCommand;
        var config: ?[]const u8 = null;
        var diff = false;
        var rest: std.ArrayList([]const u8) = .empty;
        var index: usize = 1;
        while (index < arguments.len) : (index += 1) {
            if (std.mem.eql(u8, arguments[index], "--config")) {
                index += 1;
                if (index == arguments.len) return error.MissingConfigDirectory;
                config = arguments[index];
                continue;
            }
            try rest.append(arena, arguments[index]);
            if (std.mem.eql(u8, arguments[index], "--diff")) diff = true;
            // The value of a --set is never a flag, as in the runner.
            if (std.mem.eql(u8, arguments[index], "--set") and index + 1 < arguments.len) {
                index += 1;
                try rest.append(arena, arguments[index]);
            }
        }
        if (rest.items.len == 0 or std.mem.startsWith(u8, rest.items[0], "-")) return error.MissingKosmos;
        return .{ .kosmos = rest.items[0], .config = config, .runner_arguments = rest.items[1..], .diff = diff };
    }
};

test {
    std.testing.refAllDecls(package_commands);
    std.testing.refAllDecls(@import("Packages.zig"));
    std.testing.refAllDecls(@import("manifest.zig"));
    std.testing.refAllDecls(directory_package);
    std.testing.refAllDecls(init_command);
    std.testing.refAllDecls(list_command);
    std.testing.refAllDecls(new_command);
    std.testing.refAllDecls(Sources);
}

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
    try testing.expect(command.diff);
}

test "a --set whose value is --diff is no diff, as in the runner" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const command = try Apply.parse(arena.allocator(), &.{ "apply", "frost", "--set", "--diff" });
    try testing.expect(!command.diff);
    try testing.expectEqual(2, command.runner_arguments.len);
}

test "current takes no arguments" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(.current, try Command.parse(arena.allocator(), &.{"current"}));
    try testing.expectError(error.ConfigNotRead, Command.parse(arena.allocator(), &.{ "current", "--config", "/c" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "current", "frost" }));
}

test "source takes at most one directory or --default, and no --config" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(null, (try Command.parse(arena.allocator(), &.{"source"})).source);
    try testing.expectEqualStrings("--default", (try Command.parse(arena.allocator(), &.{ "source", "--default" })).source.?);
    try testing.expectEqualStrings("/src/kosm", (try Command.parse(arena.allocator(), &.{ "source", "/src/kosm" })).source.?);
    try testing.expectError(error.ConfigNotRead, Command.parse(arena.allocator(), &.{ "source", "--config", "/c" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "source", "/a", "/b" }));
}

test "package commands take their one argument and --config anywhere" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const add = try Command.parse(arena.allocator(), &.{ "add", "--config", "/c", "git+https://example.com/x#main" });
    try testing.expectEqualStrings("git+https://example.com/x#main", add.add.argument.?);
    try testing.expectEqualStrings("/c", add.add.config.?);
    const update = try Command.parse(arena.allocator(), &.{"update"});
    try testing.expectEqual(null, update.update.argument);
    try testing.expectEqualStrings("kosm_css", (try Command.parse(arena.allocator(), &.{ "remove", "kosm_css" })).remove.argument.?);
}

test "init takes only --config, and list at most one kosmos" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("/c", (try Command.parse(arena.allocator(), &.{ "init", "--config", "/c" })).init.config.?);
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "init", "frost" }));
    try testing.expectEqualStrings("frost.iced", (try Command.parse(arena.allocator(), &.{ "list", "frost.iced" })).list.argument.?);
    try testing.expectEqual(null, (try Command.parse(arena.allocator(), &.{"list"})).list.argument);
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "list", "a", "b" }));
}

test "new takes a kind, a name and --config anywhere" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const command = (try Command.parse(arena.allocator(), &.{ "new", "--config", "/c", "app", "my_bar" })).new;
    try testing.expectEqual(.app, command.kind);
    try testing.expectEqualStrings("my_bar", command.name);
    try testing.expectEqualStrings("/c", command.config.?);
    try testing.expectError(error.UnknownKind, Command.parse(arena.allocator(), &.{ "new", "theme", "frost" }));
    try testing.expectError(error.MissingArgument, Command.parse(arena.allocator(), &.{ "new", "kosmos" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "new", "app", "a", "b" }));
}

test "package commands with a missing, extra or unknown argument are errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.MissingArgument, Command.parse(arena.allocator(), &.{"add"}));
    try testing.expectError(error.MissingArgument, Command.parse(arena.allocator(), &.{ "remove", "--config", "/c" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "remove", "a", "b" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "update", "--diff" }));
    try testing.expectError(error.MissingConfigDirectory, Command.parse(arena.allocator(), &.{ "update", "--config" }));
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

/// An adapter `name` for `.name` files, writing one `name key` line per value, so a diff shows
/// which adapter wrote a file.
fn testAdapter(comptime name: []const u8) []const u8 {
    return
    \\pub const adapter: kosm.Adapter = .{ .name = "
    ++ name ++
        \\", .extensions = &.{".
    ++ name ++
        \\"}, .serialize = serialize };
        \\
        \\fn serialize(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
        \\    _ = context;
        \\    for (root.table) |entry| try writer.print("
    ++ name ++
        \\ {s}\n", .{entry.key});
        \\}
        \\
        \\/// Writes `~/out.
    ++ name ++
        \\` through the adapter above.
        \\pub const Writer = struct {
        \\    pub fn apply(self: Writer, output: *kosm.Output) !void {
        \\        _ = self;
        \\        try output.generate(.{ .file = "~/out.
    ++ name ++
        \\" }, .{ .written = 1 });
        \\    }
        \\};
        \\
    ;
}

const test_header =
    \\const std = @import("std");
    \\const kosm = @import("kosm");
    \\
;

/// A directory kosmos with its own adapter, importing a directory app from a private file.
const test_nord_root = test_header ++ testAdapter("nord") ++
    \\const parts = @import("parts.zig");
    \\
    \\pub fn kosmos() struct { own: Writer, bar: parts.Bar } {
    \\    return .{ .own = .{}, .bar = .{} };
    \\}
    \\
;
const test_nord_parts =
    \\pub const Bar = @import("my_bar").Writer;
    \\
;
/// A directory app with its own adapter and its own kosmos.
const test_my_bar_root = test_header ++ testAdapter("bar") ++
    \\pub fn kosmos() struct { bar: Writer } {
    \\    return .{ .bar = .{} };
    \\}
    \\
;
/// A single-file kosmos with its own adapter.
const test_frost = test_header ++ testAdapter("frost") ++
    \\pub fn kosmos() struct { own: Writer } {
    \\    return .{ .own = .{} };
    \\}
    \\
;
/// A kosmos nothing imports, which does not compile.
const test_broken =
    \\const kosm = @import("kosm");
    \\pub const adapter: kosm.Adapter = .{ .name = 7 };
    \\
;

test "local packages provide their adapters and kosmoi wherever they live, and only what an apply reaches is built" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var stdout: std.Io.Writer.Allocating = .init(arena);
    var stderr: std.Io.Writer.Allocating = .init(arena);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", arena);
    // Assumes the tests run from the repository root, as `zig build test` does.
    const repository_root = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", arena);
    var environ = try testing.environ.createMap(arena);
    _ = environ.swapRemove("ZIG_PROGRESS");
    // Shared with the other config tests, so the compiled std stays warm.
    try environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ repository_root, ".zig-cache/kosm-test-global-cache" }));
    try environ.put("HOME", try std.Io.Dir.path.join(arena, &.{ root, "home" }));
    try tmp.dir.createDirPath(testing.io, "home");
    try tmp.dir.createDirPath(testing.io, "project");
    const test_kosm = @import("test_kosm.zig");
    const context: Context = .{
        .io = testing.io,
        .arena = arena,
        .config = try std.Io.Dir.path.join(arena, &.{ root, "project" }),
        .environ_map = &environ,
        .sources = try test_kosm.sources(arena, testing.io),
        .stdout = &stdout.writer,
        .stderr = &stderr.writer,
    };
    try init_command.init(context, try test_kosm.stub(arena, testing.io, tmp.dir, root));
    const files = [_]struct { []const u8, []const u8 }{
        .{ "project/kosmoi/nord/root.zig", test_nord_root },
        .{ "project/kosmoi/nord/parts.zig", test_nord_parts },
        .{ "project/apps/my_bar/root.zig", test_my_bar_root },
        .{ "project/kosmoi/frost.zig", test_frost },
        .{ "project/apps/broken.zig", test_broken },
    };
    for (files) |file| {
        try tmp.dir.createDirPath(testing.io, std.Io.Dir.path.dirname(file[0]).?);
        try tmp.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    }

    const nord = try testApplyDiff(context, "nord");
    try testing.expect(std.mem.find(u8, nord, "+nord written\n") != null);
    try testing.expect(std.mem.find(u8, nord, "+bar written\n") != null);
    try testing.expect(std.mem.find(u8, try testApplyDiff(context, "frost"), "+frost written\n") != null);
    try testing.expect(std.mem.find(u8, try testApplyDiff(context, "my_bar"), "+bar written\n") != null);

    try tmp.dir.deleteFile(testing.io, "project/apps/broken.zig");
    // The starting kosmos needs the real official packages, so it can't be listed here.
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    stdout.clearRetainingCapacity();
    try list_command.list(context, null);
    try testing.expect(std.mem.startsWith(u8, stdout.written(),
        \\kosmoi:
        \\  frost   kosmoi/frost.zig
        \\  nord    kosmoi/nord/
        \\  my_bar  apps/my_bar/
        \\
    ));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "home/out.nord", .{}));
}

/// Builds kosmos `name` in the config and runs it with `--diff`; returns the diff.
fn testApplyDiff(context: Context, name: []const u8) ![]const u8 {
    const built = try context.runZig(&.{ "build", try context.arena.print("-Dkosmos={s}", .{name}) });
    if (!built.term.success()) std.debug.print("{s}\n", .{built.stderr});
    try testing.expect(built.term.success());
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    const applied = try context.run(&.{ runner, "--diff", "--config", context.config });
    if (!applied.term.success()) std.debug.print("{s}\n", .{applied.stderr});
    try testing.expect(applied.term.success());
    return applied.stdout;
}
