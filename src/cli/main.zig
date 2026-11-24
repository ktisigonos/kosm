//! The `kosm` command: `kosm init`, `kosm apply`, which builds the one kosmos in the config
//! project with `zig build` and runs it (a script kosmos runs on the runner every script shares,
//! rebuilt only when Zig code changed), `kosm list`, `kosm colors`, `kosm new`,
//! `kosm current`, the package commands `kosm add`, `kosm remove` and `kosm update`, `kosm clean`,
//! `kosm build`, and
//! `kosm source` and `kosm relay`, the native messaging host browser extensions use. Applying a directory kosmos also refreshes its own
//! manifest. Every build runs with the kosm sources `Sources` finds.

const std = @import("std");
const Record = @import("kosm_current");
const package_commands = @import("package_commands.zig");
const directory_package = @import("directory_package.zig");
const Context = @import("Context.zig");
const init_command = @import("init.zig");
const list_command = @import("list.zig");
const clean_command = @import("clean.zig");
const build_command = @import("build_kosmoi.zig");
const complete_command = @import("complete.zig");
const completions = @import("completions.zig");
const new_command = @import("new.zig");
const scripts = @import("scripts.zig");
const known_kosmoi = @import("known_kosmoi.zig");
const source_command = @import("source.zig");
const relay_command = @import("relay.zig");
const Sources = @import("Sources.zig");
const Settings = @import("Settings.zig");
const interface = @import("kosm_interface");

const usage =
    \\usage: kosm init [--config dir]
    \\       kosm new kosmos|app|adapter|frontend|modifier|style|family|package <name> [--language <frontend>] [--config dir]
    \\       kosm apply <kosmos>[.<group>]...[.<variant>] [--<param> value]... [--set path=value]... [--diff] [--config dir]
    \\       kosm list [<kosmos> | --kosmoi | --apps | --adapters | --frontends | --packages ...] [--config dir]
    \\       kosm colors <kosmos>[.<group>]...[.<variant>] [--<param> value]... [--set path=value]... [--config dir]
    \\       kosm current
    \\       kosm source [<dir> | --default]
    \\       kosm add <url>[#ref] [--config dir]
    \\       kosm remove <name> [--config dir]
    \\       kosm update [name] [--config dir]
    \\       kosm clean [--config dir]
    \\       kosm build [<kosmos>... | --except <kosmos>... | --all] [--config dir]
    \\       kosm completions fish|bash|zsh
    \\       kosm relay <file>
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
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
    // A failing stderr has nowhere left to be reported.
    defer stderr.interface.flush() catch {};

    const command = Command.parse(arena, arguments[1..]) catch |err| {
        switch (err) {
            error.NoCommand => {},
            error.UnknownCommand => try stderr.interface.print("error: unknown command '{s}'\n", .{arguments[1]}),
            error.MissingKosmos => try stderr.interface.print("error: kosm {s} needs a kosmos, e.g. kosm {s} frost\n", .{ arguments[1], arguments[1] }),
            error.MissingConfigDirectory => try stderr.interface.writeAll("error: --config needs a directory\n"),
            error.MissingArgument, error.UnexpectedArgument => try stderr.interface.print("error: kosm {s} takes {s}\n", .{ arguments[1], expectedArguments(arguments[1]) }),
            error.UnknownKind => try stderr.interface.writeAll("error: kosm new makes a kosmos, an app, an adapter, a frontend, a modifier, a palette style, a variation family or a package, e.g. kosm new app my_bar\n"),
            error.MissingLanguage => try stderr.interface.writeAll("error: --language needs a frontend's name, e.g. --language lua\n"),
            error.ConfigNotRead => try stderr.interface.print("error: kosm {s} reads no config project, so it takes no --config\n", .{arguments[1]}),
            error.OutOfMemory => return error.OutOfMemory,
        }
        try stderr.interface.writeAll(usage);
        return 1;
    };
    switch (command) {
        .current => return printCurrent(init, &stderr.interface),
        .source => |directory| return source_command.source(init, directory, &stderr.interface),
        .completions => |shell| return printCompletions(init, shell),
        .relay => |file| return relay_command.relay(init, file, &stderr.interface),
        else => {},
    }
    const builds = try Builds.prepare(init, &stderr.interface) orelse return 1;
    switch (command) {
        .apply, .colors => |apply| return runApply(init, builds, apply, &stderr.interface),
        .init => |init_arguments| return runInit(init, builds, init_arguments, &stderr.interface),
        .new => |new| return runNew(init, builds, new, &stderr.interface),
        .build => |build_arguments| return runBuildCommand(init, builds, build_arguments, &stderr.interface),
        .add, .remove, .update, .clean => |config_command| return runConfigCommand(init, builds, command, config_command, &stderr.interface),
        .list => |list| return runList(init, builds, list, &stderr.interface),
        .complete => |words| return runComplete(init, builds, words),
        .current, .source, .completions, .relay => unreachable, // Handled above.
    }
}

/// What every `zig build` kosm runs, and every program it builds, runs with.
const Builds = struct {
    /// Kosm's environment plus the interface number the runner checks.
    environ: *const std.process.Environ.Map,
    /// The sources builds use in place of a config's pinned kosm, or null for the pinned one.
    sources: ?Sources,
    /// Shared by every context of the command, so which kosm it builds with is said once.
    sources_announced: *bool,

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
        const sources_announced = try arena.create(bool);
        sources_announced.* = false;
        return .{ .environ = environ, .sources = sources, .sources_announced = sources_announced };
    }

    fn context(builds: Builds, init: std.process.Init, config: []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) Context {
        return .{ .io = init.io, .arena = init.arena.allocator(), .config = config, .environ_map = builds.environ, .sources = builds.sources, .sources_announced = builds.sources_announced, .stdout = stdout, .stderr = stderr };
    }
};

/// What each command takes, for argument errors.
fn expectedArguments(command: []const u8) []const u8 {
    if (std.mem.eql(u8, command, "add")) return "one url, e.g. kosm add git+https://example.com/kosm_kitty#main";
    if (std.mem.eql(u8, command, "remove")) return "one package name, e.g. kosm remove kosm_kitty";
    if (std.mem.eql(u8, command, "update")) return "at most one package name";
    if (std.mem.eql(u8, command, "list")) return "at most one kosmos, e.g. kosm list frost, or the kinds to list: --kosmoi, --apps, --adapters, --frontends, --packages";
    if (std.mem.eql(u8, command, "build")) return "kosmoi, --except and kosmoi, or --all, e.g. kosm build frost nord";
    if (std.mem.eql(u8, command, "completions")) return "one shell: fish, bash or zsh";
    if (std.mem.eql(u8, command, "new")) return "a kind and a name, e.g. kosm new app my_bar";
    if (std.mem.eql(u8, command, "source")) return "at most one directory, or --default";
    if (std.mem.eql(u8, command, "relay")) return "one file, e.g. kosm relay ~/.local/share/kosm/firefox/values.json";
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
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    const context = builds.context(init, config, &stdout.interface, stderr);
    init_command.init(context, init_command.official) catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    try completions.install(init.io, arena, init.environ_map, &stdout.interface, stderr);
    return 0;
}

/// Scaffolds a directory package, or a script in `--language`, in the config project.
fn runNew(init: std.process.Init, builds: Builds, command: New, stderr: *std.Io.Writer) !u8 {
    const config = try configPath(init, command.config, stderr) orelse return 1;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    var context = builds.context(init, config, &stdout.interface, stderr);
    context.show_build_output = true;
    const working_directory = try std.process.currentPathAlloc(init.io, init.arena.allocator());
    new_command.new(context, command.kind, command.name, command.language, working_directory) catch |err| switch (err) {
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

    var context = builds.context(init, config, stderr, stderr);
    context.show_build_output = true;
    const is_script = scripts.isScript(context, command.kosmos) catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    const runner_arguments = if (is_script) script: {
        if (!try prepareScripts(context)) return 1;
        const base = scripts.baseOf(context, command.kosmos) catch |err| switch (err) {
            error.Failed => return 1,
            else => |other| return other,
        };
        // Showing colors writes nothing, so it leaves stale manifests to the next apply.
        if (!command.colors) if (base) |name| if (!try refreshManifest(init, builds, config, name, command.diff, stderr)) return 1;
        break :script try scriptRunnerArguments(arena, config, command);
    } else zig: {
        // The runner of scripts checks a script's name itself; a Zig kosmos' is checked here,
        // where a misspelling would otherwise fail compiling.
        known_kosmoi.check(context, command.kosmos, .kosmos, "") catch |err| switch (err) {
            error.Failed => return 1,
            else => |other| return other,
        };
        if (!try build(context, command.kosmos)) return 1;
        if (!command.colors and !try refreshManifest(init, builds, config, command.kosmos, command.diff, stderr)) return 1;
        const runner = try std.Io.Dir.path.join(arena, &.{ config, runner_path });
        const builds_on_kosmoi = scripts.buildsOnKosmoi(context, runner) catch |err| switch (err) {
            error.Failed => return 1,
            else => |other| return other,
        };
        // Only the runner of scripts holds every kosmos one may build on.
        if (builds_on_kosmoi) {
            if (!try prepareScripts(context)) return 1;
            break :zig try scriptRunnerArguments(arena, config, command);
        }
        break :zig try std.mem.concat(arena, []const u8, &.{ &.{runner}, command.runner_arguments, &.{ "--config", config } });
    };
    const runner = runner_arguments[0];
    const environ = if (command.colors) colors: {
        const with_colors = try arena.create(std.process.Environ.Map);
        with_colors.* = try builds.environ.clone(arena);
        try with_colors.put(interface.colors_variable, "1");
        break :colors with_colors;
    } else builds.environ;
    const err = std.process.replace(init.io, .{ .argv = runner_arguments, .environ_map = environ });
    try stderr.print("error: cannot run {s}: {s}\n", .{ runner, @errorName(err) });
    return 1;
}

/// Builds the runner of scripts when it is stale; returns whether it is ready. A script is read
/// when the runner starts, so only changed Zig code builds anything.
fn prepareScripts(context: Context) !bool {
    const prepared = scripts.prepare(context) catch |err| switch (err) {
        error.Failed => return false,
        else => |other| return other,
    };
    try context.stderr.flush();
    return prepared;
}

/// The command line running `command`'s kosmos in the runner of scripts.
fn scriptRunnerArguments(arena: std.mem.Allocator, config: []const u8, command: Apply) ![]const []const u8 {
    const runner = try std.Io.Dir.path.join(arena, &.{ config, scripts.runner_path });
    return std.mem.concat(arena, []const u8, &.{ &.{ runner, command.kosmos }, command.runner_arguments, &.{ "--config", config } });
}

/// Brings the manifest of directory kosmos `kosmos` up to date, or on `diff` only says what
/// would change. Returns whether the apply can go on.
fn refreshManifest(init: std.process.Init, builds: Builds, config: []const u8, kosmos: []const u8, diff: bool, stderr: *std.Io.Writer) !bool {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    const context = builds.context(init, config, &stdout.interface, stderr);
    directory_package.refreshApplied(context, kosmos, if (diff) .report else .write) catch |err| switch (err) {
        error.Failed => return false,
        else => |other| return other,
    };
    // The runner replaces this process, so nothing buffered may be left behind.
    try stdout.interface.flush();
    try stderr.flush();
    return true;
}

/// Runs `kosm list` against the config project.
fn runList(init: std.process.Init, builds: Builds, command: List, stderr: *std.Io.Writer) !u8 {
    const config = try configPath(init, command.config, stderr) orelse return 1;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    var context = builds.context(init, config, &stdout.interface, stderr);
    context.show_build_output = true;
    list_command.list(context, command.kosmos, command.kinds) catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    return 0;
}

/// Runs `kosm add`, `kosm remove`, `kosm update` or `kosm clean` against the config project.
fn runConfigCommand(init: std.process.Init, builds: Builds, command: Command, config_command: ConfigCommand, stderr: *std.Io.Writer) !u8 {
    const config = try configPath(init, config_command.config, stderr) orelse return 1;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    var context = builds.context(init, config, &stdout.interface, stderr);
    context.show_build_output = true;
    const result = switch (command) {
        .add => package_commands.add(context, config_command.argument.?),
        .remove => package_commands.remove(context, config_command.argument.?),
        .update => package_commands.update(context, config_command.argument),
        .clean => clean_command.clean(context),
        .apply, .colors, .list, .current, .init, .new, .build, .source, .completions, .complete, .relay => unreachable, // main passes only the four above.
    };
    result catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    // Updating is when kosm is brought up to date, so its completions are too.
    if (command == .update) try completions.install(init.io, init.arena.allocator(), init.environ_map, &stdout.interface, stderr);
    return 0;
}

/// Prints the completion script of `shell`.
fn printCompletions(init: std.process.Init, shell: completions.Shell) !u8 {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    try stdout.interface.writeAll(shell.script());
    try stdout.interface.flush();
    return 0;
}

/// Prints what completes the last of `words`, the words typed after `kosm`. Whatever goes
/// wrong, a shell asking for completions gets no error, only fewer candidates.
fn runComplete(init: std.process.Init, builds: Builds, words: []const []const u8) !u8 {
    var given: ?[]const u8 = null;
    for (words, 0..) |word, index| {
        if (std.mem.eql(u8, word, "--config") and index + 2 < words.len) given = words[index + 1];
    }
    var discarded: std.Io.Writer.Discarding = .init(&.{});
    const config = try configPath(init, given, &discarded.writer) orelse "";
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    try complete_command.complete(builds.context(init, config, &stdout.interface, &discarded.writer), words);
    try stdout.interface.flush();
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
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
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
    list: List,
    /// Like `apply`, printing the themes of the tree its kosmos builds instead of applying it.
    colors: Apply,
    /// The shell whose completion script to print.
    completions: completions.Shell,
    /// The file to forward to a browser extension.
    relay: []const u8,
    /// The words typed after `kosm`, for the completion scripts; not in the usage.
    complete: []const []const u8,
    add: ConfigCommand,
    remove: ConfigCommand,
    update: ConfigCommand,
    clean: ConfigCommand,
    build: Build,

    const ParseError = Apply.ParseError || New.ParseError || Build.ParseError || error{ConfigNotRead};

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
        if (std.mem.eql(u8, arguments[0], "completions")) {
            if (arguments.len < 2) return error.MissingArgument;
            if (arguments.len > 2) return error.UnexpectedArgument;
            return .{ .completions = std.meta.stringToEnum(completions.Shell, arguments[1]) orelse return error.UnexpectedArgument };
        }
        if (std.mem.eql(u8, arguments[0], "relay")) {
            if (arguments.len < 2) return error.MissingArgument;
            if (arguments.len > 2) return error.UnexpectedArgument;
            return .{ .relay = arguments[1] };
        }
        if (std.mem.eql(u8, arguments[0], "complete")) {
            const separated = arguments.len > 1 and std.mem.eql(u8, arguments[1], "--");
            return .{ .complete = arguments[if (separated) 2 else 1..] };
        }
        if (std.mem.eql(u8, arguments[0], "init")) return .{ .init = try .parse(arguments[1..], .none) };
        if (std.mem.eql(u8, arguments[0], "new")) return .{ .new = try .parse(arguments[1..]) };
        if (std.mem.eql(u8, arguments[0], "list")) return .{ .list = try .parse(arena, arguments[1..]) };
        if (std.mem.eql(u8, arguments[0], "colors")) return .{ .colors = try Apply.parse(arena, arguments) };
        if (std.mem.eql(u8, arguments[0], "add")) return .{ .add = try .parse(arguments[1..], .required) };
        if (std.mem.eql(u8, arguments[0], "remove")) return .{ .remove = try .parse(arguments[1..], .required) };
        if (std.mem.eql(u8, arguments[0], "update")) return .{ .update = try .parse(arguments[1..], .optional) };
        if (std.mem.eql(u8, arguments[0], "clean")) return .{ .clean = try .parse(arguments[1..], .none) };
        if (std.mem.eql(u8, arguments[0], "build")) return .{ .build = try .parse(arena, arguments[1..]) };
        return .{ .apply = try Apply.parse(arena, arguments) };
    }
};

/// `kosm list` read: at most one kosmos, or the kinds to list alone.
const List = struct {
    kosmos: ?[]const u8 = null,
    /// Some of `list_command.kind_flags`, as typed.
    kinds: []const []const u8 = &.{},
    /// The `--config` directory, or null for the default.
    config: ?[]const u8 = null,

    const ParseError = ConfigCommand.ParseError || std.mem.Allocator.Error;

    /// Reads the arguments after `list`. `--config dir` may appear anywhere.
    fn parse(arena: std.mem.Allocator, arguments: []const []const u8) ParseError!List {
        var command: List = .{};
        var kinds: std.ArrayList([]const u8) = .empty;
        var index: usize = 0;
        while (index < arguments.len) : (index += 1) {
            const argument = arguments[index];
            if (std.mem.eql(u8, argument, "--config")) {
                index += 1;
                if (index == arguments.len) return error.MissingConfigDirectory;
                command.config = arguments[index];
            } else if (isKindFlag(argument)) {
                if (command.kosmos != null) return error.UnexpectedArgument;
                try kinds.append(arena, argument);
            } else if (command.kosmos != null or kinds.items.len > 0 or std.mem.startsWith(u8, argument, "-")) {
                return error.UnexpectedArgument;
            } else command.kosmos = argument;
        }
        command.kinds = kinds.items;
        return command;
    }

    fn isKindFlag(argument: []const u8) bool {
        for (list_command.kind_flags) |flag| {
            if (std.mem.eql(u8, argument, flag)) return true;
        }
        return false;
    }
};

/// A command working on a config project, with at most one argument and `--config`:
/// `init`, `list`, `add`, `remove`, `update` or `clean`.
const ConfigCommand = struct {
    /// add: the url and ref; remove: the name; update: the name, or null for every package;
    /// list: the kosmos, or null for everything; init and clean: always null.
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

/// `kosm new <kind> <name> [--language <frontend>] [--config dir]`.
const New = struct {
    kind: new_command.Kind,
    name: []const u8,
    /// The frontend's name `--language` gives, or null for Zig.
    language: ?[]const u8,
    /// The `--config` directory, or null for the default.
    config: ?[]const u8,

    const ParseError = ConfigCommand.ParseError || error{ UnknownKind, MissingLanguage };

    /// Reads the arguments after `new`. `--language` and `--config` may appear anywhere.
    fn parse(arguments: []const []const u8) ParseError!New {
        var words: [2][]const u8 = undefined;
        var count: usize = 0;
        var config: ?[]const u8 = null;
        var language: ?[]const u8 = null;
        var index: usize = 0;
        while (index < arguments.len) : (index += 1) {
            if (std.mem.eql(u8, arguments[index], "--config")) {
                index += 1;
                if (index == arguments.len) return error.MissingConfigDirectory;
                config = arguments[index];
            } else if (std.mem.eql(u8, arguments[index], "--language")) {
                index += 1;
                if (index == arguments.len) return error.MissingLanguage;
                language = arguments[index];
            } else if (count == words.len or std.mem.startsWith(u8, arguments[index], "-")) {
                return error.UnexpectedArgument;
            } else {
                words[count] = arguments[index];
                count += 1;
            }
        }
        if (count < words.len) return error.MissingArgument;
        const kind = std.meta.stringToEnum(new_command.Kind, words[0]) orelse return error.UnknownKind;
        return .{ .kind = kind, .name = words[1], .language = language, .config = config };
    }
};

/// `kosm build [<kosmos>... | --except <kosmos>... | --all] [--config dir]`.
const Build = struct {
    /// What the command line picks, or null for `kosm.zon`'s choice.
    selection: ?Settings.Selection,
    /// The `--config` directory, or null for the default.
    config: ?[]const u8,

    const ParseError = ConfigCommand.ParseError || error{OutOfMemory};

    /// Reads the arguments after `build`. `--config dir` may appear anywhere; `--except` comes
    /// before the kosmoi it leaves out, and `--all` stands alone.
    fn parse(arena: std.mem.Allocator, arguments: []const []const u8) ParseError!Build {
        var names: std.ArrayList([]const u8) = .empty;
        var except = false;
        var all = false;
        var config: ?[]const u8 = null;
        var index: usize = 0;
        while (index < arguments.len) : (index += 1) {
            const argument = arguments[index];
            if (std.mem.eql(u8, argument, "--config")) {
                index += 1;
                if (index == arguments.len) return error.MissingConfigDirectory;
                config = arguments[index];
            } else if (std.mem.eql(u8, argument, "--except")) {
                if (except or all or names.items.len != 0) return error.UnexpectedArgument;
                except = true;
            } else if (std.mem.eql(u8, argument, "--all")) {
                if (except or all or names.items.len != 0) return error.UnexpectedArgument;
                all = true;
            } else if (all or std.mem.startsWith(u8, argument, "-")) {
                return error.UnexpectedArgument;
            } else try names.append(arena, argument);
        }
        const selection: ?Settings.Selection = if (all) .all else if (except) blk: {
            if (names.items.len == 0) return error.MissingArgument;
            break :blk .{ .except = names.items };
        } else if (names.items.len != 0) .{ .only = names.items } else null;
        return .{ .selection = selection, .config = config };
    }
};

/// Compiles the kosmoi the command line or `kosm.zon` picks.
fn runBuildCommand(init: std.process.Init, builds: Builds, command: Build, stderr: *std.Io.Writer) !u8 {
    const config = try configPath(init, command.config, stderr) orelse return 1;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    var context = builds.context(init, config, &stdout.interface, stderr);
    context.show_build_output = true;
    build_command.build(context, command.selection) catch |err| switch (err) {
        error.Failed => return 1,
        else => |other| return other,
    };
    return 0;
}

/// `kosm apply` or `kosm colors` with its arguments sorted: kosm's own, and the ones the kosmos
/// gets.
const Apply = struct {
    /// As typed: "frost" or "frost.iced".
    kosmos: []const u8,
    /// The `--config` directory, or null for the default.
    config: ?[]const u8,
    /// Parameters, `--set`s and `--diff`, in order, for the kosmos runner.
    runner_arguments: []const []const u8,
    /// Whether `--diff` is among them, read like the runner reads it.
    diff: bool,
    /// `kosm colors`: print the themes of the tree instead of applying it.
    colors: bool = false,

    const ParseError = error{ NoCommand, UnknownCommand, MissingKosmos, MissingConfigDirectory, OutOfMemory };

    /// Reads `apply <kosmos> ...` or `colors <kosmos> ...` (without the program name).
    /// `--config dir` may appear anywhere.
    fn parse(arena: std.mem.Allocator, arguments: []const []const u8) ParseError!Apply {
        if (arguments.len == 0) return error.NoCommand;
        const colors = std.mem.eql(u8, arguments[0], "colors");
        if (!colors and !std.mem.eql(u8, arguments[0], "apply")) return error.UnknownCommand;
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
        return .{ .kosmos = rest.items[0], .config = config, .runner_arguments = rest.items[1..], .diff = diff, .colors = colors };
    }
};

test {
    std.testing.refAllDecls(package_commands);
    std.testing.refAllDecls(@import("Packages.zig"));
    std.testing.refAllDecls(@import("manifest.zig"));
    std.testing.refAllDecls(directory_package);
    std.testing.refAllDecls(init_command);
    std.testing.refAllDecls(list_command);
    std.testing.refAllDecls(clean_command);
    std.testing.refAllDecls(build_command);
    std.testing.refAllDecls(scripts);
    std.testing.refAllDecls(complete_command);
    std.testing.refAllDecls(completions);
    std.testing.refAllDecls(relay_command);
    std.testing.refAllDecls(new_command);
    std.testing.refAllDecls(Sources);
    std.testing.refAllDecls(Settings);
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

test "relay takes exactly one file" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("/v.json", (try Command.parse(arena.allocator(), &.{ "relay", "/v.json" })).relay);
    try testing.expectError(error.MissingArgument, Command.parse(arena.allocator(), &.{"relay"}));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "relay", "/v.json", "x" }));
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

test "init takes only --config, and list at most one kosmos or the kinds to list" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("/c", (try Command.parse(arena.allocator(), &.{ "init", "--config", "/c" })).init.config.?);
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "init", "frost" }));
    try testing.expectEqualStrings("frost.iced", (try Command.parse(arena.allocator(), &.{ "list", "frost.iced" })).list.kosmos.?);
    try testing.expectEqual(null, (try Command.parse(arena.allocator(), &.{"list"})).list.kosmos);
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "list", "a", "b" }));
    const kinds = (try Command.parse(arena.allocator(), &.{ "list", "--apps", "--config", "/c", "--frontends" })).list;
    try testing.expectEqual(2, kinds.kinds.len);
    try testing.expectEqualStrings("--frontends", kinds.kinds[1]);
    try testing.expectEqualStrings("/c", kinds.config.?);
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "list", "frost", "--apps" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "list", "--apps", "frost" }));
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "list", "--themes" }));
    const colors = (try Command.parse(arena.allocator(), &.{ "colors", "frost.light", "--set", "kitty=null", "--config", "/c" })).colors;
    try testing.expectEqualStrings("frost.light", colors.kosmos);
    try testing.expectEqualStrings("/c", colors.config.?);
    try testing.expectEqual(2, colors.runner_arguments.len);
    try testing.expect(colors.colors and !colors.diff);
    try testing.expect(!(try Command.parse(arena.allocator(), &.{ "apply", "frost" })).apply.colors);
    try testing.expectError(error.MissingKosmos, Command.parse(arena.allocator(), &.{"colors"}));
    try testing.expectEqual(completions.Shell.fish, (try Command.parse(arena.allocator(), &.{ "completions", "fish" })).completions);
    try testing.expectError(error.UnexpectedArgument, Command.parse(arena.allocator(), &.{ "completions", "csh" }));
    try testing.expectEqual(2, (try Command.parse(arena.allocator(), &.{ "complete", "--", "apply", "" })).complete.len);
}

test "new takes a kind, a name, --language and --config anywhere" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const command = (try Command.parse(arena.allocator(), &.{ "new", "--config", "/c", "app", "--language", "lua", "my_bar" })).new;
    try testing.expectEqual(.app, command.kind);
    try testing.expectEqualStrings("my_bar", command.name);
    try testing.expectEqualStrings("lua", command.language.?);
    try testing.expectEqualStrings("/c", command.config.?);
    try testing.expectEqual(null, (try Command.parse(arena.allocator(), &.{ "new", "frontend", "keys" })).new.language);
    try testing.expectError(error.MissingLanguage, Command.parse(arena.allocator(), &.{ "new", "kosmos", "frost", "--language" }));
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

test "build takes kosmoi, --except and kosmoi, or --all, and --config anywhere" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const parse = struct {
        fn parse(allocator: std.mem.Allocator, arguments: []const []const u8) !Build {
            return (try Command.parse(allocator, arguments)).build;
        }
    }.parse;
    const allocator = arena.allocator();
    try testing.expectEqual(null, (try parse(allocator, &.{"build"})).selection);
    const only = try parse(allocator, &.{ "build", "frost", "--config", "/c", "nord.iced" });
    try testing.expectEqualStrings("nord.iced", only.selection.?.only[1]);
    try testing.expectEqualStrings("/c", only.config.?);
    try testing.expectEqualStrings("frost", (try parse(allocator, &.{ "build", "--except", "frost" })).selection.?.except[0]);
    try testing.expectEqual(.all, (try parse(allocator, &.{ "build", "--all" })).selection.?);
    try testing.expectError(error.MissingArgument, parse(allocator, &.{ "build", "--except" }));
    try testing.expectError(error.UnexpectedArgument, parse(allocator, &.{ "build", "frost", "--except", "nord" }));
    try testing.expectError(error.UnexpectedArgument, parse(allocator, &.{ "build", "--all", "frost" }));
    try testing.expectError(error.UnexpectedArgument, parse(allocator, &.{ "build", "--except", "--all" }));
    try testing.expectError(error.UnexpectedArgument, parse(allocator, &.{ "build", "--diff" }));
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
/// A kosmos reading a file in another local module's folder, which reports the path and bytes
/// it got.
const test_reader =
    \\const kosm = @import("kosm");
    \\
    \\pub fn kosmos(params: struct { note: kosm.File = .{ .path = "~~my_bar/note.txt" } }) !struct { bar: @import("my_bar").Writer } {
    \\    return kosm.fail("read {s}: {s}", .{ params.note.path, try params.note.contents() });
    \\}
    \\
;
/// A kosmos nothing imports, which does not compile.
const test_broken =
    \\const kosm = @import("kosm");
    \\pub const adapter: kosm.Adapter = .{ .name = 7 };
    \\
;

test "local packages provide their adapters, kosmoi and folders wherever they live, and only what an apply reaches is built" {
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
        .{ "project/kosmoi/reader.zig", test_reader },
        .{ "project/apps/my_bar/note.txt", "bar note" },
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

    const built = try context.runZig(&.{ "build", "-Dkosmos=reader" });
    try testing.expect(built.term.success());
    const read = try context.run(&.{ try std.Io.Dir.path.join(arena, &.{ context.config, runner_path }), "--diff", "--config", context.config });
    try testing.expect(!read.term.success());
    const note = try std.Io.Dir.path.join(arena, &.{ context.config, "apps/my_bar/note.txt" });
    try testing.expectEqualStrings(try arena.print("error: kosmos 'reader': read {s}: bar note\n", .{note}), read.stderr);

    try tmp.dir.deleteFile(testing.io, "project/apps/broken.zig");
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/reader.zig");
    // The starting kosmos needs the real official packages, so it can't be listed here.
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    stdout.clearRetainingCapacity();
    try list_command.list(context, null, &.{});
    try testing.expect(std.mem.startsWith(u8, stdout.written(),
        \\kosmoi:
        \\  frost   kosmoi/frost.zig
        \\  nord    kosmoi/nord/
        \\  my_bar  apps/my_bar/
        \\
    ));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "home/out.nord", .{}));
}

/// A kosmos and an app whose stacks outgrow a process' usual 8 or 16 MiB, as a Debug build of
/// many large apps does.
const test_deep = test_header ++ testAdapter("deep") ++
    \\pub const Deep = struct {
    \\    pub fn apply(self: Deep, output: *kosm.Output) !void {
    \\        var scratch: [64 * 1024 * 1024]u8 = undefined;
    \\        @memset(&scratch, 1);
    \\        std.mem.doNotOptimizeAway(&scratch);
    \\        _ = self;
    \\        try output.generate(.{ .file = "~/out.deep" }, .{ .written = scratch[0] });
    \\    }
    \\};
    \\
    \\pub fn kosmos() struct { own: Deep } {
    \\    var scratch: [64 * 1024 * 1024]u8 = undefined;
    \\    @memset(&scratch, 1);
    \\    std.mem.doNotOptimizeAway(&scratch);
    \\    return .{ .own = .{} };
    \\}
    \\
;
/// A kosmos returning a list that lives in its own stack.
const test_dangling = test_header ++
    \\pub const Listed = struct {
    \\    items: []const u32,
    \\    pub fn apply(self: Listed, output: *kosm.Output) !void {
    \\        _ = self;
    \\        _ = output;
    \\    }
    \\};
    \\
    \\pub fn kosmos() struct { listed: Listed } {
    \\    var items = [_]u32{ 1, 2 };
    \\    std.mem.doNotOptimizeAway(&items);
    \\    return .{ .listed = .{ .items = &items } };
    \\}
    \\
;

test "a kosmos and its apps run on a stack deeper than the process', and a list left in a kosmos' stack is refused" {
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
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/deep.zig", .data = test_deep });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/dangling.zig", .data = test_dangling });

    try testing.expect(std.mem.find(u8, try testApplyDiff(context, "deep"), "+deep written\n") != null);

    const built = try context.runZig(&.{ "build", "-Dkosmos=dangling" });
    try testing.expect(built.term.success());
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    const applied = try context.run(&.{ runner, "--diff", "--config", context.config });
    try testing.expect(!applied.term.success());
    try testing.expect(std.mem.find(u8, applied.stderr, "listed.items points into a function that has returned") != null);
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
