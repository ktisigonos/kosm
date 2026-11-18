//! The program `kosm apply` builds for one kosmos: parses its parameters and `--set`s, plans
//! every app, then prints the plan as a diff or commits it all or nothing, records the apply and
//! reloads the apps.

const std = @import("std");
const kosm = @import("kosm");
const Record = @import("kosm_current");
const interface = @import("kosm_interface");
const Arguments = @import("Arguments.zig");
const completions = @import("completions.zig");
const discovery = @import("discovery.zig");
const files = @import("files.zig");
const images = @import("images.zig");
const Places = @import("Places.zig");
const lifetime = @import("lifetime.zig");
const params = @import("params.zig");
const report = @import("report.zig");
const script = @import("script.zig");
const set = @import("set.zig");
const walk = @import("walk.zig");

/// The kosmos a build applies.
pub const Target = @import("Target.zig");
/// What the script runner holds.
pub const ScriptTarget = @import("ScriptTarget.zig");
/// Reports what an installed package provides, for `kosm add` and `kosm update`.
pub const inspect = @import("inspect.zig").inspect;
/// Lists every kosmos and installed package in a config, for `kosm list`.
pub const list = list_module.list;
/// Prints the palettes a kosmos' file declares, for `kosm colors`.
pub const colors = @import("colors.zig").colors;
/// A module `list` looks into.
pub const ListSource = list_module.Source;

const list_module = @import("list.zig");

/// Runs the kosmos in `target` with the process arguments
/// (`[--param value]... [--set path=value]... [--diff] [--config dir]`).
/// Returns the exit status: 0 on success, 1 after printing what went wrong.
pub fn run(init: std.process.Init, comptime target: Target) !u8 {
    const declared = comptime findTarget(target);
    const kosmos = @field(declared.Namespace, declared.function);
    const adapters = comptime discovery.adapters(target.adapter_sources);
    var diagnostics: kosm.Diagnostics = .{ .kosmos = target.name };
    var terminal: Terminal = .{};
    const streams = try terminal.open(init);
    if (!try interface.check(init.environ_map, streams.stderr)) {
        try streams.stderr.flush();
        return 1;
    }

    if (init.environ_map.get(interface.completions_variable) != null) {
        try completions.write(streams.stdout, kosmos);
        try streams.stdout.flush();
        return 0;
    }

    const all_arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const folders: Folders = .{ .config = target.config, .kosmos = target.folder, .named = target.folders };
    return finishRun(apply(init, kosmos, all_arguments[1..], folders, adapters, &diagnostics, streams, .{}), &diagnostics, streams);
}

/// Runs the script kosmos named by the first process argument, with the rest as `run` takes
/// them: reads it and every script below it, then applies it on its Zig kosmos, or on none.
/// Returns the exit status: 0 on success, 1 after printing what went wrong.
pub fn runScript(init: std.process.Init, comptime target: ScriptTarget) !u8 {
    var terminal: Terminal = .{};
    const streams = try terminal.open(init);
    if (!try interface.check(init.environ_map, streams.stderr)) {
        try streams.stderr.flush();
        return 1;
    }
    const all_arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (all_arguments.len < 2) {
        try streams.stderr.writeAll("error: the script runner needs the name of a script kosmos\n");
        try streams.stderr.flush();
        return 1;
    }
    var diagnostics: kosm.Diagnostics = .{ .kosmos = all_arguments[1] };
    return finishRun(applyScript(init, target, all_arguments[2..], &diagnostics, streams), &diagnostics, streams);
}

/// The exit status of an apply that returned `result`, after printing its failure.
fn finishRun(result: anytype, diagnostics: *kosm.Diagnostics, streams: Streams) !u8 {
    const status: u8 = if (result) 0 else |err| switch (err) {
        error.Reported => 1,
        else => return err,
    };
    try streams.stdout.flush();
    if (status != 0) try diagnostics.write(streams.stderr);
    try streams.stderr.flush();
    return status;
}

/// The buffered standard streams a runner reports on; `open` it where it stays.
const Terminal = struct {
    stdout_buffer: [4096]u8 = undefined,
    stderr_buffer: [1024]u8 = undefined,
    stdout: std.Io.File.Writer = undefined,
    stderr: std.Io.File.Writer = undefined,

    fn open(terminal: *Terminal, init: std.process.Init) !Streams {
        terminal.stdout = std.Io.File.stdout().writer(init.io, &terminal.stdout_buffer);
        terminal.stderr = std.Io.File.stderr().writer(init.io, &terminal.stderr_buffer);
        return .{
            .stdout = &terminal.stdout.interface,
            .stderr = &terminal.stderr.interface,
            .stdout_mode = try .detect(init.io, .stdout(), isSet(init.environ_map, "NO_COLOR"), isSet(init.environ_map, "CLICOLOR_FORCE")),
        };
    }
};

/// Whether the environment variable `name` is set and not empty, as no-color.org asks.
fn isSet(environ: *const std.process.Environ.Map, name: []const u8) bool {
    const value = environ.get(name) orelse return false;
    return value.len != 0;
}

/// Where the runner reports: results on stdout, errors and warnings on stderr.
const Streams = struct {
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    /// Whether stdout takes colors: a terminal, unless `NO_COLOR` is set.
    stdout_mode: std.Io.Terminal.Mode,
};

/// The kosmos `target.function` names, or a compile error listing the file's kosmoi.
fn findTarget(comptime target: Target) discovery.Declared {
    if (discovery.findKosmos(target.file, target.function)) |declared| return declared;
    const file_name = target.name[0 .. std.mem.findScalar(u8, target.name, '.') orelse target.name.len];
    const subject = if (std.mem.eql(u8, target.function, "kosmos")) "the default kosmos 'kosmos'" else "'" ++ target.function ++ "'";
    @compileError(target.path ++ ": " ++ subject ++ " is not a kosmos: " ++ discovery.notFoundReason(target.file, target.function) ++
        ". Kosmoi in this file: " ++ discovery.kosmosList(target.file, file_name));
}

/// Failed; `diagnostics` says why.
const Reported = error{Reported};

/// The folders `~~/`, `~~kosmos/` and `~~<name>/` stand for, known when the runner is built.
const Folders = struct {
    config: []const u8,
    kosmos: []const u8,
    named: []const Places.Folder,
};

/// What script kosmoi set on top of the Zig kosmos they build on, the lowest script first; empty
/// when a Zig kosmos is applied itself.
const Layers = struct {
    /// Tables for the kosmos' `Params`, set before the command line's parameters.
    params: []const kosm.Loose = &.{},
    /// Tables for the tree, set before the command line's `--set`s.
    overrides: []const kosm.Loose = &.{},

    /// The params and overrides of `scripts`, each naming its script when its frontend did not.
    fn of(arena: std.mem.Allocator, scripts: []const script.Loaded) std.mem.Allocator.Error!Layers {
        var params_list: std.ArrayList(kosm.Loose) = .empty;
        var overrides: std.ArrayList(kosm.Loose) = .empty;
        for (scripts) |loaded| {
            if (loaded.script.params) |given| try params_list.append(arena, script.withOrigin(given, loaded.path));
            if (loaded.script.overrides) |given| try overrides.append(arena, script.withOrigin(given, loaded.path));
        }
        return .{ .params = params_list.items, .overrides = overrides.items };
    }
};

/// Calls `kosmos` with the command line's parameters on top of `layers.params`, assigns
/// `layers.overrides`, then the `--set`s, and plans and delivers the tree.
fn apply(init: std.process.Init, comptime kosmos: anytype, raw_arguments: []const []const u8, folders: Folders, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams, layers: Layers) !void {
    const arena = init.arena.allocator();
    const arguments = try readArguments(init, ParamsOf(kosmos), raw_arguments, diagnostics);
    const home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{});
    var kosmos_stack: lifetime.Stack = undefined;
    var tree = try callKosmos(kosmos, .{ .arguments = arguments.parameters, .layers = layers.params }, diagnostics, &kosmos_stack, .{
        .arena = arena,
        .io = init.io,
        .places = .{ .home = home, .config = folders.config, .kosmos = folders.kosmos, .folders = folders.named },
        .cache = if (arguments.config) |config| try std.Io.Dir.path.join(arena, &.{ config, images.cache_folder }) else null,
        .diagnostics = diagnostics,
        .stderr = streams.stderr,
    });
    // Its parameters were parsed in the stack below `tree`, and the kosmos ran in its own; both
    // are dead now that it returned.
    try refuseDeadLists(arena, tree, &.{ .below(@intFromPtr(&tree)), kosmos_stack }, diagnostics);
    for (layers.overrides) |overrides| kosm.assign(@TypeOf(tree), arena, &tree, overrides, diagnostics) catch |err| switch (err) {
        error.InvalidAssignment => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };
    try finish(init, &tree, arguments, home, adapters, diagnostics, streams);
}

/// Reads the script kosmos `diagnostics.kosmos` and applies it on what it builds on.
fn applyScript(init: std.process.Init, comptime target: ScriptTarget, raw_arguments: []const []const u8, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const arena = init.arena.allocator();
    const adapters = comptime discovery.adapters(target.adapter_sources);
    const chain = try script.resolve(.{
        .arena = arena,
        .io = init.io,
        .config = target.config,
        .frontends = comptime discovery.frontends(target.adapter_sources),
        .modules = comptime moduleNames(target.kosmoi),
        .diagnostics = diagnostics,
    }, diagnostics.kosmos);
    const base = chain.base orelse return applyStandalone(init, target, raw_arguments, adapters, diagnostics, streams, chain.scripts);
    const layers = try Layers.of(arena, chain.scripts);
    inline for (comptime zigKosmoi(target.kosmoi)) |entry| {
        if (std.mem.eql(u8, base, entry.name)) {
            const folders: Folders = .{ .config = target.config, .kosmos = entry.folder, .named = target.folders };
            return apply(init, @field(entry.Namespace, entry.function), raw_arguments, folders, adapters, diagnostics, streams, layers);
        }
    }
    return fail(diagnostics, "{s} builds on '{s}', but there is no such kosmos; Zig kosmoi: {s}", .{ chain.scripts[0].path, base, comptime zigKosmosNames(target.kosmoi) });
}

/// Builds the tree of a kosmos with no Zig kosmos below it from its scripts alone, then
/// plans and delivers it.
fn applyStandalone(init: std.process.Init, comptime target: ScriptTarget, raw_arguments: []const []const u8, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams, scripts: []const script.Loaded) !void {
    const Tree = discovery.Standalone(target.apps);
    const Build = struct {
        fn build(arena: std.mem.Allocator, given: []const script.Loaded, build_diagnostics: *kosm.Diagnostics) script.Error!Tree {
            return script.standalone(Tree, comptime discovery.standaloneModules(target.apps), arena, given, build_diagnostics);
        }
    };
    const arena = init.arena.allocator();
    const arguments = try readArguments(init, struct {}, raw_arguments, diagnostics);
    if (arguments.parameters.len != 0)
        return fail(diagnostics, "it builds on no kosmos, so it takes no parameters, got '{s}'", .{arguments.parameters[0]});
    const home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{});
    var built: script.Error!Tree = undefined;
    const stack = try callOnKosmosStack(Build.build, .{ arena, scripts, diagnostics }, &built, diagnostics);
    var tree = built catch |err| switch (err) {
        error.Reported => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };
    try refuseDeadLists(arena, tree, &.{stack}, diagnostics);
    try finish(init, &tree, arguments, home, adapters, diagnostics, streams);
}

/// Sorts the runner's arguments, with the relative paths of `Params`' files and images made
/// absolute against the working directory.
fn readArguments(init: std.process.Init, comptime Params: type, raw_arguments: []const []const u8, diagnostics: *kosm.Diagnostics) !Arguments {
    const arena = init.arena.allocator();
    const typed = Arguments.split(arena, raw_arguments) catch |err| switch (err) {
        error.SetWithoutAssignment => return fail(diagnostics, "--set needs path=value", .{}),
        error.ConfigWithoutDirectory => return fail(diagnostics, "--config needs a directory", .{}),
        error.OutOfMemory => return error.OutOfMemory,
    };
    const working_directory = std.process.currentPathAlloc(init.io, arena) catch |err|
        return fail(diagnostics, "cannot read the working directory, which relative paths given as parameters start from: {s}", .{@errorName(err)});
    return typed.withParameters(arena, try params.absolutePaths(Params, arena, working_directory, typed.parameters));
}

/// Fails naming the first list in `tree` that points into one of `dead`.
fn refuseDeadLists(arena: std.mem.Allocator, tree: anytype, dead: []const lifetime.Stack, diagnostics: *kosm.Diagnostics) !void {
    for (dead) |stack| {
        if (try lifetime.findDeadList(arena, tree, stack)) |path|
            return fail(diagnostics, "{s} points into a function that has returned, so what it holds is garbage: write lists of values known only at run time as kosm.keep(T, &.{{ ... }}), or as constants", .{path});
    }
}

/// Assigns the `--set`s inside `tree`, a pointer to the built tree, then plans and delivers it.
fn finish(init: std.process.Init, tree: anytype, arguments: Arguments, home: []const u8, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const arena = init.arena.allocator();
    for (arguments.assignments) |assignment| set.assign(arena, tree, assignment, diagnostics) catch |err| switch (err) {
        error.InvalidAssignment => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };

    var plan: kosm.Plan = .init(init.gpa, init.io);
    defer plan.deinit();
    var warnings: kosm.Warnings = .init(arena);
    const context: walk.Context = .{ .allocator = arena, .home = home, .adapters = adapters.list, .adapter_clashes = adapters.clashes, .plan = &plan, .diagnostics = diagnostics, .warnings = &warnings };
    try planWarning(tree.*, context, streams.stderr);
    try deliver(tree.*, &plan, .{
        .gpa = init.gpa,
        .arena = arena,
        .io = init.io,
        .home = home,
        .diff = arguments.diff,
        .recording = try recording(arena, init.environ_map, diagnostics.kosmos, arguments),
        .diagnostics = diagnostics,
        .streams = streams,
    });
}

/// One Zig kosmos the script runner holds, and the folder of the module declaring it.
const ZigKosmos = struct {
    /// As `kosm apply` spells it: "frost", "frost.iced".
    name: []const u8,
    Namespace: type,
    function: []const u8,
    folder: []const u8,
};

/// Every kosmos every module in `sources` declares.
fn zigKosmoi(comptime sources: []const ScriptTarget.KosmosSource) []const ZigKosmos {
    @setEvalBranchQuota(discovery.branch_quota);
    comptime var found: []const ZigKosmos = &.{};
    inline for (sources) |source| {
        inline for (comptime discovery.declaredKosmoi(source.module)) |declared| {
            const name = comptime if (declared.name.len == 0) source.name else source.name ++ "." ++ declared.name;
            found = found ++ .{ZigKosmos{ .name = name, .Namespace = declared.Namespace, .function = declared.function, .folder = source.folder }};
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

/// The names of every kosmos in `sources`, comma-separated, or "none".
fn zigKosmosNames(comptime sources: []const ScriptTarget.KosmosSource) []const u8 {
    comptime var names: []const u8 = "";
    inline for (comptime zigKosmoi(sources)) |entry| names = names ++ (if (names.len == 0) "" else ", ") ++ entry.name;
    return if (names.len == 0) "none" else names;
}

/// The import name of every module in `sources`.
fn moduleNames(comptime sources: []const ScriptTarget.KosmosSource) []const []const u8 {
    comptime var names: []const []const u8 = &.{};
    inline for (sources) |source| names = names ++ .{source.name};
    const final = names[0..names.len].*;
    return &final;
}

/// Plans every app in `tree`, then prints the warnings gathered, also when planning failed, so
/// they come before the error, the diff and the written files.
fn planWarning(tree: anytype, context: walk.Context, stderr: *std.Io.Writer) !void {
    const planned = walk.planTree(tree, context);
    try context.warnings.write(context.diagnostics.kosmos, stderr);
    try stderr.flush();
    planned catch return error.Reported;
}

/// The record a commit saves, or null when the runner was started without `--config` (only
/// `kosm apply` passes it) or neither $XDG_STATE_HOME nor $HOME is set.
fn recording(arena: std.mem.Allocator, environ: *const std.process.Environ.Map, kosmos: []const u8, arguments: Arguments) !?Recording {
    const config = arguments.config orelse return null;
    const path = try Record.path(arena, environ) orelse return null;
    return .{ .record = .{ .kosmos = kosmos, .arguments = arguments.recorded, .config = config }, .path = path };
}

/// A record of the apply and the file it goes to.
const Recording = struct {
    record: Record,
    path: []const u8,
};

/// What `deliver` needs besides the tree and its plan.
const Delivery = struct {
    gpa: std.mem.Allocator,
    /// Outlives the plan, so a failure's app and file can still be printed after it is freed.
    arena: std.mem.Allocator,
    io: std.Io,
    /// The home directory a reload's `~/` arguments expand to.
    home: []const u8,
    diff: bool,
    /// Saved after a successful commit; null records nothing.
    recording: ?Recording,
    diagnostics: *kosm.Diagnostics,
    streams: Streams,
};

/// Prints the plan as a diff, or commits it, records the apply and then reloads every app in
/// `tree`, also when nothing changed. A failed commit records and reloads nothing.
fn deliver(tree: anytype, plan: *kosm.Plan, delivery: Delivery) !void {
    const stdout = delivery.streams.stdout;
    if (delivery.diff) {
        if (!plan.hasChanges()) return report.nothingToChange(stdout);
        return kosm.diff.writePlan(delivery.gpa, .{ .writer = stdout, .mode = delivery.streams.stdout_mode }, plan);
    }
    if (plan.hasChanges()) {
        var failure: kosm.commit.Failure = .{};
        kosm.commit.writePlan(delivery.gpa, delivery.io, plan, &failure) catch |err| {
            const app = try delivery.arena.dupe(u8, ownerOf(plan, failure.path));
            const file = try delivery.arena.dupe(u8, failure.path);
            delivery.diagnostics.set(app, file, "cannot write it: {s}", .{@errorName(err)});
            return error.Reported;
        };
        for (plan.files.items) |file| {
            if (file.changed() and file.group == null) try report.wrote(stdout, file.display_path);
        }
        for (plan.links.items) |link| {
            if (link.changed() and link.group == null) try report.linked(stdout, link.display_path, link.target);
        }
        const groups = try plan.changedGroups(delivery.gpa);
        defer delivery.gpa.free(groups);
        for (groups) |count| try report.wroteGroup(stdout, count);
    } else try report.nothingToChange(stdout);
    if (delivery.recording) |recorded| {
        recorded.record.save(delivery.io, recorded.path) catch |err|
            try report.recordFailed(delivery.streams.stderr, recorded.path, @errorName(err));
    }
    // The written files are reported before any reload's own output or warning.
    try stdout.flush();
    try walk.reloadTree(tree, delivery.io, delivery.home, delivery.diagnostics.kosmos, delivery.streams.stderr);
}

/// The app planning the file shown as `display_path`, or empty.
fn ownerOf(plan: *const kosm.Plan, display_path: []const u8) []const u8 {
    for (plan.files.items) |file| {
        if (std.mem.eql(u8, file.display_path, display_path)) return file.owner();
    }
    for (plan.links.items) |link| {
        if (std.mem.eql(u8, link.display_path, display_path)) return link.owner;
    }
    return "";
}

/// The `Params` type `kosmos` takes, or an empty struct when it takes none.
fn ParamsOf(comptime kosmos: anytype) type {
    const function = @typeInfo(@TypeOf(kosmos)).@"fn";
    return if (function.param_types.len == 0) struct {} else function.param_types[0].?;
}

/// What a kosmos' `Params` are read from.
const Given = struct {
    /// The command line's parameters, which win.
    arguments: []const []const u8,
    /// Tables a script kosmos sets, the lowest first.
    layers: []const kosm.Loose = &.{},
};

/// Calls `kosmos` with its `Params` read from `given` and their images and files loaded, on its
/// own stack, which `kosmos_stack` is set to. Never inlined, so the parameters are parsed in
/// stack below its caller's. A kosmos failing through `kosm.fail` reports its own message.
noinline fn callKosmos(comptime kosmos: anytype, given: Given, diagnostics: *kosm.Diagnostics, kosmos_stack: *lifetime.Stack, image_context: images.Context) images.Error!discovery.Payload(@typeInfo(@TypeOf(kosmos)).@"fn".return_type.?) {
    const function = @typeInfo(@TypeOf(kosmos)).@"fn";
    var returned: function.return_type.? = undefined;
    kosm.failure.clear();
    if (function.param_types.len == 0) {
        if (given.arguments.len != 0) return fail(diagnostics, "it takes no parameters, got '{s}'", .{given.arguments[0]});
        if (given.layers.len != 0) return fail(diagnostics, "the kosmos it builds on takes no parameters, but a script sets some", .{});
        kosmos_stack.* = try callOnKosmosStack(kosmos, .{}, &returned, diagnostics);
    } else {
        const Params = function.param_types[0].?;
        var start: Params = .{};
        var host_set = false;
        for (given.layers) |layer| {
            kosm.assign(Params, image_context.arena, &start, layer, diagnostics) catch |err| switch (err) {
                error.InvalidAssignment => return error.Reported,
                error.OutOfMemory => return error.OutOfMemory,
            };
            host_set = host_set or script.setsKey(layer, "host");
        }
        var hostname_buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = if (comptime params.hasHost(Params)) try readHostname(&hostname_buffer, diagnostics) else "";
        var parsed = params.parseOnto(Params, start, host_set, given.arguments, hostname, diagnostics) catch return error.Reported;
        try images.fill(Params, &parsed, image_context);
        try files.fill(Params, &parsed, .{ .arena = image_context.arena, .io = image_context.io, .places = image_context.places, .diagnostics = diagnostics });
        kosmos_stack.* = try callOnKosmosStack(kosmos, .{parsed}, &returned, diagnostics);
    }
    if (@typeInfo(@TypeOf(returned)) != .error_union) return returned;
    return returned catch |err| {
        if (@as(anyerror, err) == error.KosmosFailed) {
            if (kosm.failure.message()) |message| return fail(diagnostics, "{s}", .{message});
        }
        return fail(diagnostics, "the kosmos function failed: {s}", .{@errorName(err)});
    };
}

/// How deep the stack a kosmos runs on may grow. Kosmoi build whole apps by value, and a Debug
/// build gives every temporary its own stack slot, so a kosmos wearing many apps outgrows a
/// process' usual 8 or 16 MiB. It is only reserved: memory is used as deep as the kosmos goes.
const kosmos_stack_size = 256 * 1024 * 1024;

/// Calls `function` with `arguments` on a thread with a `kosmos_stack_size` stack, writing what
/// it returns to `returned`, and gives the part of that stack it ran in.
fn callOnKosmosStack(comptime function: anytype, arguments: anytype, returned: *@typeInfo(@TypeOf(function)).@"fn".return_type.?, diagnostics: *kosm.Diagnostics) Reported!lifetime.Stack {
    const Call = struct {
        fn run(call_arguments: @TypeOf(arguments), result: *@TypeOf(returned.*), top: *usize) void {
            top.* = @frameAddress();
            result.* = @call(.auto, function, call_arguments);
        }
    };
    var top: usize = undefined;
    const thread = std.Thread.spawn(.{ .stack_size = kosmos_stack_size }, Call.run, .{ arguments, returned, &top }) catch |err|
        return fail(diagnostics, "cannot start the thread the kosmos runs on: {s}", .{@errorName(err)});
    thread.join();
    return .{ .low = top -| kosmos_stack_size, .high = top };
}

fn readHostname(buffer: *[std.posix.HOST_NAME_MAX]u8, diagnostics: *kosm.Diagnostics) Reported![]const u8 {
    return std.posix.gethostname(buffer) catch |err|
        fail(diagnostics, "cannot read the hostname for Params.host: {s}", .{@errorName(err)});
}

fn fail(diagnostics: *kosm.Diagnostics, comptime format: []const u8, arguments: anytype) Reported {
    diagnostics.set("", "", format, arguments);
    return error.Reported;
}

test {
    std.testing.refAllDecls(Arguments);
    std.testing.refAllDecls(set);
    std.testing.refAllDecls(discovery);
    std.testing.refAllDecls(@import("inspect.zig"));
    std.testing.refAllDecls(list_module);
    std.testing.refAllDecls(@import("colors.zig"));
    std.testing.refAllDecls(completions);
    std.testing.refAllDecls(params);
    std.testing.refAllDecls(images);
    std.testing.refAllDecls(files);
    std.testing.refAllDecls(Places);
    std.testing.refAllDecls(lifetime);
    std.testing.refAllDecls(walk);
    std.testing.refAllDecls(script);
}

const testing = std.testing;

const lines_adapter: kosm.Adapter = .{ .name = "lines", .extensions = &.{".lines"}, .serialize = serializeLines };

fn serializeLines(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    _ = context;
    for (root.table) |entry| try writer.print("{s} = {d}\n", .{ entry.key, entry.value.integer });
}

const ReloadingApp = struct {
    file: []const u8,
    reloads: *usize,

    pub fn apply(self: ReloadingApp, output: *kosm.Output) !void {
        try output.generate(.{ .file = self.file }, .{ .size = 1 });
    }

    pub fn reload(self: ReloadingApp, reloader: *kosm.Reloader) !void {
        self.reloads.* += 1;
        try reloader.run(&.{"true"});
    }
};

/// Plans `tree` against `home` and delivers it, with stdout in `output`. Diagnostics live in `arena`.
fn planAndDeliver(arena: *std.heap.ArenaAllocator, tree: anytype, home: []const u8, diff: bool, diagnostics: *kosm.Diagnostics, output: *std.Io.Writer.Allocating) !void {
    return planAndRecord(arena, tree, home, diff, null, diagnostics, output);
}

/// `planAndDeliver`, saving `recorded` after a commit.
fn planAndRecord(arena: *std.heap.ArenaAllocator, tree: anytype, home: []const u8, diff: bool, recorded: ?Recording, diagnostics: *kosm.Diagnostics, output: *std.Io.Writer.Allocating) !void {
    var plan: kosm.Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    var warning_buffer: [256]u8 = undefined;
    var warnings: std.Io.Writer = .fixed(&warning_buffer);
    var gathered: kosm.Warnings = .init(arena.allocator());
    try planWarning(tree, .{ .allocator = arena.allocator(), .home = home, .adapters = &.{lines_adapter}, .plan = &plan, .diagnostics = diagnostics, .warnings = &gathered }, &warnings);
    try deliver(tree, &plan, .{
        .gpa = testing.allocator,
        .arena = arena.allocator(),
        .io = testing.io,
        .home = home,
        .diff = diff,
        .recording = recorded,
        .diagnostics = diagnostics,
        .streams = .{ .stdout = &output.writer, .stderr = &warnings, .stdout_mode = .no_color },
    });
    try testing.expectEqualStrings("", warnings.buffered());
}

fn tmpPath(tmp: *testing.TmpDir, buffer: *[std.Io.Dir.max_path_bytes]u8) ![]const u8 {
    return buffer[0..try tmp.dir.realPath(testing.io, buffer)];
}

test "a diff writes and reloads nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var reloads: usize = 0;
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();

    try planAndDeliver(&arena, .{ .kitty = ReloadingApp{ .file = "~/a.lines", .reloads = &reloads } }, home, true, &diagnostics, &output);
    try testing.expectEqual(0, reloads);
    try testing.expect(std.mem.find(u8, output.written(), "+size = 1") != null);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "a.lines", .{}));
}

test "a commit reloads every app, also when nothing changed" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var reloads: usize = 0;
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const tree = .{ .kitty = ReloadingApp{ .file = "~/a.lines", .reloads = &reloads } };

    var first: std.Io.Writer.Allocating = .init(testing.allocator);
    defer first.deinit();
    try planAndDeliver(&arena, tree, home, false, &diagnostics, &first);
    try testing.expectEqual(1, reloads);
    try testing.expectEqualStrings("wrote ~/a.lines\n", first.written());

    var second: std.Io.Writer.Allocating = .init(testing.allocator);
    defer second.deinit();
    try planAndDeliver(&arena, tree, home, false, &diagnostics, &second);
    try testing.expectEqual(2, reloads);
    try testing.expectEqualStrings("nothing to change\n", second.written());
}

test "a failed commit reloads nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(testing.io, "locked", .default_dir);
    try tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o500), .{});
    defer tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o700), .{}) catch {};
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var reloads: usize = 0;
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();

    const tree = .{ .kitty = ReloadingApp{ .file = "~/locked/a.lines", .reloads = &reloads } };
    try testing.expectError(error.Reported, planAndDeliver(&arena, tree, home, false, &diagnostics, &output));
    try testing.expectEqual(0, reloads);
    try testing.expectEqualStrings("kitty", diagnostics.app);
    try testing.expectEqualStrings("~/locked/a.lines", diagnostics.file);
}

const WarningApp = struct {
    file: []const u8,

    pub fn apply(self: WarningApp, output: *kosm.Output) !void {
        try output.generate(.{ .file = self.file }, .{ .size = 1 });
        try output.warn(self.file, "font '{s}' is not installed", .{"Maple Mono"});
    }
};

const FailingApp = struct {
    pub fn apply(self: FailingApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
        return error.GlowMissing;
    }
};

/// Plans `tree` as the runner does, with warnings printed to `stderr`.
fn planToStderr(arena: *std.heap.ArenaAllocator, tree: anytype, home: []const u8, plan: *kosm.Plan, diagnostics: *kosm.Diagnostics, stderr: *std.Io.Writer) !void {
    var warnings: kosm.Warnings = .init(arena.allocator());
    try planWarning(tree, .{ .allocator = arena.allocator(), .home = home, .adapters = &.{lines_adapter}, .plan = plan, .diagnostics = diagnostics, .warnings = &warnings }, stderr);
}

test "a warning is printed naming kosmos, app and file, and the plan still writes" {
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var plan: kosm.Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    var buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);

    try planToStderr(&arena, .{ .terminal = .{ .kitty = WarningApp{ .file = "~/a.lines" } } }, "/home/test", &plan, &diagnostics, &stderr);
    try testing.expectEqualStrings("warning: kosmos 'frost', app 'terminal.kitty', file ~/a.lines: font 'Maple Mono' is not installed\n", stderr.buffered());
    try testing.expectEqualStrings("size = 1\n", plan.files.items[0].new);
}

test "warnings gathered before a failing app are still printed" {
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var plan: kosm.Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    var buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);

    const tree = .{ .kitty = WarningApp{ .file = "~/a.lines" }, .bar = FailingApp{} };
    try testing.expectError(error.Reported, planToStderr(&arena, tree, "/home/test", &plan, &diagnostics, &stderr));
    try testing.expectEqualStrings("warning: kosmos 'frost', app 'kitty', file ~/a.lines: font 'Maple Mono' is not installed\n", stderr.buffered());
    try testing.expectEqualStrings("bar", diagnostics.app);
}

/// Plans one app writing `~/a.lines` with `arguments` as the runner's, recording into
/// `XDG_STATE_HOME` = `<home>/state`, then loads what was recorded.
fn applyAndLoadRecord(arena: *std.heap.ArenaAllocator, home: []const u8, arguments: []const []const u8) !?Record {
    var environ: std.process.Environ.Map = .init(arena.allocator());
    try environ.put("XDG_STATE_HOME", try std.Io.Dir.path.join(arena.allocator(), &.{ home, "state" }));
    const split = try Arguments.split(arena.allocator(), arguments);
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost.iced" };
    var reloads: usize = 0;
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    const tree = .{ .kitty = ReloadingApp{ .file = "~/a.lines", .reloads = &reloads } };
    const recorded = (try recording(arena.allocator(), &environ, diagnostics.kosmos, split)).?;
    try planAndRecord(arena, tree, home, split.diff, recorded, &diagnostics, &output);

    var zon_diagnostics: std.zon.parse.Diagnostics = undefined;
    return Record.load(arena.allocator(), testing.io, recorded.path, &zon_diagnostics);
}

test "an apply records the kosmos, its arguments and the config in XDG_STATE_HOME" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const record = (try applyAndLoadRecord(&arena, home, &.{ "--set", "kitty.file=x", "--config", "/c", "--blur", "false" })).?;
    try testing.expectEqualStrings("frost.iced", record.kosmos);
    try testing.expectEqualStrings("/c", record.config);
    try testing.expectEqualDeep(@as([]const []const u8, &.{ "--set", "kitty.file=x", "--blur", "false" }), record.arguments);
    try tmp.dir.access(testing.io, "state/kosm/current.zon", .{});
}

test "a diff records nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(null, try applyAndLoadRecord(&arena, home, &.{ "--config", "/c", "--diff" }));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "state", .{}));
}

test "a failed commit records nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(testing.io, "locked", .default_dir);
    try tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o500), .{});
    defer tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o700), .{}) catch {};
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var environ: std.process.Environ.Map = .init(arena.allocator());
    try environ.put("XDG_STATE_HOME", try std.Io.Dir.path.join(arena.allocator(), &.{ home, "state" }));
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var reloads: usize = 0;
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();

    const recorded = try recording(arena.allocator(), &environ, "frost", .{ .config = "/c" });
    const tree = .{ .kitty = ReloadingApp{ .file = "~/locked/a.lines", .reloads = &reloads } };
    try testing.expectError(error.Reported, planAndRecord(&arena, tree, home, false, recorded, &diagnostics, &output));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "state", .{}));
}

const ScriptParams = struct { script: kosm.File = .{ .path = "./kosmos.txt" } };
const ScriptTree = struct { script: []const u8 };

fn scriptKosmos(given: ScriptParams) !ScriptTree {
    const bytes = try given.script.contents();
    if (std.mem.eql(u8, bytes, "big\n")) return kosm.fail("kosmos.txt:1: hyprland.general.gaps_in: expected an integer, got \"{s}\"", .{"big"});
    if (std.mem.eql(u8, bytes, "broken\n")) return error.Broken;
    return .{ .script = bytes };
}

/// Calls `scriptKosmos` with `arguments`, the kosmos' folder being `folder`.
fn callScriptKosmos(arena: std.mem.Allocator, folder: []const u8, arguments: []const []const u8, diagnostics: *kosm.Diagnostics) !ScriptTree {
    var stack: lifetime.Stack = undefined;
    var stderr: std.Io.Writer.Allocating = .init(arena);
    return callKosmos(scriptKosmos, .{ .arguments = arguments }, diagnostics, &stack, .{
        .arena = arena,
        .io = testing.io,
        .places = .{ .home = folder, .config = folder, .kosmos = folder },
        .cache = null,
        .diagnostics = diagnostics,
        .stderr = &stderr.writer,
    });
}

test "a kosmos reads the file its Params name, next to it by default" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var folder_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const folder = try tmpPath(&tmp, &folder_buffer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmos.txt", .data = "return {}\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "other.txt", .data = "other\n" });
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "test" };

    try testing.expectEqualStrings("return {}\n", (try callScriptKosmos(arena.allocator(), folder, &.{}, &diagnostics)).script);
    const other = try std.Io.Dir.path.join(arena.allocator(), &.{ folder, "other.txt" });
    try testing.expectEqualStrings("other\n", (try callScriptKosmos(arena.allocator(), folder, &.{ "--script", other }, &diagnostics)).script);
}

test "a missing file fails naming its path before the kosmos runs" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var folder_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const folder = try tmpPath(&tmp, &folder_buffer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "test" };

    try testing.expectError(error.Reported, callScriptKosmos(arena.allocator(), folder, &.{ "--script", "~~kosmos/missing.txt" }, &diagnostics));
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try diagnostics.write(&output.writer);
    try testing.expectEqualStrings("error: kosmos 'test', file ~~kosmos/missing.txt: Params.script: cannot read the file: FileNotFound\n", output.written());
}

test "a kosmos failing through kosm.fail is reported with its own message, other errors by name" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var folder_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const folder = try tmpPath(&tmp, &folder_buffer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmos.txt", .data = "big\n" });
    var reported: kosm.Diagnostics = .{ .kosmos = "personal" };
    try testing.expectError(error.Reported, callScriptKosmos(arena.allocator(), folder, &.{}, &reported));
    try reported.write(&output.writer);
    try testing.expectEqualStrings("error: kosmos 'personal': kosmos.txt:1: hyprland.general.gaps_in: expected an integer, got \"big\"\n", output.written());

    output.clearRetainingCapacity();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmos.txt", .data = "broken\n" });
    var named: kosm.Diagnostics = .{ .kosmos = "personal" };
    try testing.expectError(error.Reported, callScriptKosmos(arena.allocator(), folder, &.{}, &named));
    try named.write(&output.writer);
    try testing.expectEqualStrings("error: kosmos 'personal': the kosmos function failed: Broken\n", output.written());
}
