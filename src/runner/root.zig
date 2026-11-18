//! The program `kosm apply` builds for one kosmos: parses its parameters and `--set`s, plans
//! every app, then prints the plan as a diff or commits it all or nothing, records the apply and
//! reloads the apps.

const std = @import("std");
const kosm = @import("kosm");
const Record = @import("kosm_current");
const interface = @import("kosm_interface");
const Arguments = @import("Arguments.zig");
const bindings = @import("bindings.zig");
const Runtime = @import("Runtime.zig");
const completions = @import("completions.zig");
const completion_types = @import("completion_types.zig");
const discovery = @import("discovery.zig");
const files = @import("files.zig");
const kosmos_call = @import("kosmos_call.zig");
const images = @import("images.zig");
const Places = @import("Places.zig");
const lifetime = @import("lifetime.zig");
const params = @import("params.zig");
const report = @import("report.zig");
const script = @import("script.zig");
const set = @import("set.zig");
const Sources = @import("Sources.zig");
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
    if (std.mem.eql(u8, all_arguments[1], write_completions_flag)) {
        var diagnostics: kosm.Diagnostics = .{ .kosmos = "" };
        return finishRun(writeFrontendCompletions(init, target, all_arguments[2..], &diagnostics), &diagnostics, streams);
    }
    var diagnostics: kosm.Diagnostics = .{ .kosmos = all_arguments[1] };
    if (init.environ_map.get(interface.completions_variable) != null) {
        return finishRun(writeScriptCompletions(init, target, &diagnostics, streams), &diagnostics, streams);
    }
    return finishRun(applyScript(init, target, all_arguments[2..], &diagnostics, streams), &diagnostics, streams);
}

/// Makes the script runner write every frontend's completion files instead of running a script:
/// `--write-completions <completions folder> <editor folder> [<module>=<root file>]...`.
pub const write_completions_flag = "--write-completions";

/// Writes the files each frontend gives for every type a script may set into
/// `<completions folder>/<frontend>/`, and each frontend's editor file into the editor folder.
/// The modules' root files are read for doc comments.
fn writeFrontendCompletions(init: std.process.Init, comptime target: ScriptTarget, arguments: []const []const u8, diagnostics: *kosm.Diagnostics) !void {
    const arena = init.arena.allocator();
    if (arguments.len < 2) return fail(diagnostics, "{s} needs a completions folder and an editor folder", .{write_completions_flag});
    var modules: std.ArrayList(Sources.Module) = .empty;
    for (arguments[2..]) |argument| {
        const equals = std.mem.findScalar(u8, argument, '=') orelse return fail(diagnostics, "{s}: expected <module>=<root file>, got '{s}'", .{ write_completions_flag, argument });
        try modules.append(arena, .{ .name = argument[0..equals], .root = argument[equals + 1 ..] });
    }
    var sources: Sources = .{ .arena = arena, .io = init.io, .modules = modules.items };
    const completion = try describeScriptTypes(arena, target, &sources);
    inline for (comptime discovery.frontends(target.adapter_sources)) |declared| {
        const frontend = declared.frontend;
        if (frontend.complete) |complete| {
            const folder = try std.Io.Dir.path.join(arena, &.{ arguments[0], frontend.name });
            for (try complete(arena, completion)) |file| try writeOutput(init.io, arena, folder, file, diagnostics);
        }
        if (frontend.editor_file) |file| try writeOutput(init.io, arena, arguments[1], file, diagnostics);
    }
}

/// Every type a script may set: every Zig kosmos' parameters and tree, the apps a kosmos
/// without a base chooses from, and the theme input.
fn describeScriptTypes(arena: std.mem.Allocator, comptime target: ScriptTarget, sources: *Sources) !kosm.Frontend.Completion {
    @setEvalBranchQuota(discovery.branch_quota);
    var builder: completion_types.Builder = .{ .arena = arena, .sources = sources };
    var kosmoi: std.ArrayList(kosm.Frontend.Completion.Kosmos) = .empty;
    inline for (target.kosmoi) |source| {
        inline for (comptime discovery.declaredKosmoi(source.module)) |declared| {
            const name = comptime if (declared.name.len == 0) source.name else source.name ++ "." ++ declared.name;
            try kosmoi.append(arena, try builder.kosmos(.{
                .name = name,
                .module = source.name,
                .path = comptime functionPath(declared),
                .function = @TypeOf(@field(declared.Namespace, declared.function)),
            }));
        }
    }
    const standalone = try builder.appsRecord(discovery.Standalone(target.apps), comptime discovery.standalonePackages(target.apps), "kosm.Standalone");
    const theme = try builder.declaredRecord(kosm.Theme.Input, "kosm", &.{ "Theme", "Input" });
    const namespaces = try ScriptLibrary(target).describe(&builder);
    return .{ .records = builder.records.items, .kosmoi = kosmoi.items, .standalone = standalone, .theme = theme, .namespaces = namespaces };
}

/// The names leading from a module's root to `declared`'s function: `&.{ "group", "iced" }`.
fn functionPath(comptime declared: discovery.Declared) []const []const u8 {
    comptime var path: []const []const u8 = &.{};
    if (declared.name.len != 0) {
        comptime var segments = std.mem.splitScalar(u8, declared.name, '.');
        inline while (comptime segments.next()) |segment| path = path ++ .{segment};
    }
    // A variant is named after its function, a group's own kosmos after the group.
    if (path.len == 0 or !std.mem.eql(u8, path[path.len - 1], declared.function)) path = path ++ .{declared.function};
    const final = path[0..path.len].*;
    return &final;
}

/// Writes `file` below `folder`, creating the folders it needs.
fn writeOutput(io: std.Io, arena: std.mem.Allocator, folder: []const u8, file: kosm.Frontend.Completion.File, diagnostics: *kosm.Diagnostics) !void {
    const path = try std.Io.Dir.path.join(arena, &.{ folder, file.path });
    if (std.Io.Dir.path.dirname(path)) |directory| std.Io.Dir.cwd().createDirPath(io, directory) catch |err|
        return fail(diagnostics, "cannot create {s}: {s}", .{ directory, @errorName(err) });
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = file.contents }) catch |err|
        return fail(diagnostics, "cannot write {s}: {s}", .{ path, @errorName(err) });
}

/// The chain of script kosmos `diagnostics.kosmos`, read through the frontends.
/// Scripts' calls run with `runtime`.
fn resolveScript(init: std.process.Init, comptime target: ScriptTarget, diagnostics: *kosm.Diagnostics, runtime: *Runtime) !script.Chain {
    return script.resolve(.{
        .arena = init.arena.allocator(),
        .io = init.io,
        .config = target.config,
        .frontends = comptime discovery.frontends(target.adapter_sources),
        .modules = comptime moduleNames(target.kosmoi),
        .kosmoi = comptime kosmosNames(target.kosmoi),
        .library = ScriptLibrary(target).library(runtime),
        .calls_folder = &runtime.scripts_folder,
        .diagnostics = diagnostics,
    }, diagnostics.kosmos);
}

/// Every module, kosmos and value of the config a script may call.
fn ScriptLibrary(comptime target: ScriptTarget) type {
    comptime var roots: []const bindings.Root = &.{};
    inline for (target.kosmoi) |source| roots = roots ++ .{bindings.Root{ .name = source.name, .module = source.module }};
    const final = roots[0..roots.len].*;
    return bindings.Library(&final, kosmos_call.zigKosmoi(target.kosmoi));
}

/// What scripts' calls need, with images cached in the config `raw_arguments` name, if any.
fn scriptRuntime(init: std.process.Init, comptime target: ScriptTarget, raw_arguments: []const []const u8, stderr: *std.Io.Writer, diagnostics: *kosm.Diagnostics) !Runtime {
    const arena = init.arena.allocator();
    const typed = Arguments.split(arena, raw_arguments) catch Arguments{};
    return .{
        .arena = arena,
        .io = init.io,
        .home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{}),
        .config = target.config,
        .folders = target.folders,
        .scripts_folder = try std.Io.Dir.path.join(arena, &.{ target.config, script.directory }),
        .cache = if (typed.config) |config| try std.Io.Dir.path.join(arena, &.{ config, images.cache_folder }) else null,
        .stderr = stderr,
    };
}

/// The tree types every Zig kosmos in `sources` returns, each once.
fn treeTypes(comptime sources: []const ScriptTarget.KosmosSource) []const type {
    comptime var found: []const type = &.{};
    inline for (comptime kosmos_call.zigKosmoi(sources)) |entry| {
        const Tree = discovery.Payload(@typeInfo(@TypeOf(@field(entry.Namespace, entry.function))).@"fn".return_type.?);
        const known = inline for (found) |Earlier| {
            if (Earlier == Tree) break true;
        } else false;
        if (!known) found = found ++ .{Tree};
    }
    const final = found[0..found.len].*;
    return &final;
}

/// What completes a script's arguments: the Zig kosmos it builds on (a `base` line), then that
/// kosmos' parameters and `--set` paths, or without one the `--set` paths of every app.
fn writeScriptCompletions(init: std.process.Init, comptime target: ScriptTarget, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const stdout = streams.stdout;
    var runtime = try scriptRuntime(init, target, &.{}, streams.stderr, diagnostics);
    const chain = try resolveScript(init, target, diagnostics, &runtime);
    if (chain.tree) |tree| {
        inline for (comptime treeTypes(target.kosmoi)) |Tree| {
            if (tree.as(Tree) != null) return completions.writeSetPaths(stdout, Tree);
        }
        return notATree(diagnostics, chain.scripts[0].path, tree);
    }
    const base = chain.base orelse return completions.writeSetPaths(stdout, discovery.Standalone(target.apps));
    inline for (comptime kosmos_call.zigKosmoi(target.kosmoi)) |entry| {
        if (std.mem.eql(u8, base, entry.name)) {
            try stdout.print("{s}\t{s}\n", .{ completions.base_kind, entry.name });
            return completions.write(stdout, @field(entry.Namespace, entry.function));
        }
    }
    return fail(diagnostics, "{s} builds on '{s}', but there is no such kosmos; Zig kosmoi: {s}", .{ chain.scripts[0].path, base, comptime zigKosmosNames(target.kosmoi) });
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
    params: []const kosmos_call.Layer = &.{},
    /// Tables for the tree, set before the command line's `--set`s.
    overrides: []const kosm.Loose = &.{},

    /// The params and overrides of `scripts`, each naming its script when its frontend did not.
    fn of(arena: std.mem.Allocator, scripts: []const script.Loaded) std.mem.Allocator.Error!Layers {
        var params_list: std.ArrayList(kosmos_call.Layer) = .empty;
        var overrides: std.ArrayList(kosm.Loose) = .empty;
        for (scripts) |loaded| {
            if (loaded.script.params) |given| try params_list.append(arena, .{ .values = script.withOrigin(given, loaded.path), .folder = loaded.folder });
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
    var tree = try kosmos_call.callKosmos(kosmos, .{ .arguments = arguments.parameters, .layers = layers.params }, diagnostics, &kosmos_stack, .{
        .arena = arena,
        .io = init.io,
        .places = .{ .home = home, .config = folders.config, .kosmos = folders.kosmos, .folders = folders.named },
        .cache = if (arguments.config) |config| try std.Io.Dir.path.join(arena, &.{ config, images.cache_folder }) else null,
        .diagnostics = diagnostics,
        .stderr = streams.stderr,
    });
    // Its parameters were parsed in the stack below `tree`, and the kosmos ran in its own; both
    // are dead now that it returned.
    try kosmos_call.refuseDeadLists(arena, tree, &.{ .below(@intFromPtr(&tree)), kosmos_stack }, diagnostics);
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
    var runtime = try scriptRuntime(init, target, raw_arguments, streams.stderr, diagnostics);
    const chain = try resolveScript(init, target, diagnostics, &runtime);
    if (chain.tree) |tree| {
        inline for (comptime treeTypes(target.kosmoi)) |Tree| {
            if (tree.as(Tree)) |built| return applyBuilt(init, built.*, raw_arguments, adapters, diagnostics, streams, chain.scripts);
        }
        return notATree(diagnostics, chain.scripts[0].path, tree);
    }
    const base = chain.base orelse return applyStandalone(init, target, raw_arguments, adapters, diagnostics, streams, chain.scripts);
    const layers = try Layers.of(arena, chain.scripts);
    inline for (comptime kosmos_call.zigKosmoi(target.kosmoi)) |entry| {
        if (std.mem.eql(u8, base, entry.name)) {
            const folders: Folders = .{ .config = target.config, .kosmos = entry.folder, .named = target.folders };
            return apply(init, @field(entry.Namespace, entry.function), raw_arguments, folders, adapters, diagnostics, streams, layers);
        }
    }
    return fail(diagnostics, "{s} builds on '{s}', but there is no such kosmos; Zig kosmoi: {s}", .{ chain.scripts[0].path, base, comptime zigKosmosNames(target.kosmoi) });
}

fn notATree(diagnostics: *kosm.Diagnostics, path: []const u8, tree: kosm.Frontend.Handle) Reported {
    return fail(diagnostics, "{s} returns a {s}, which is not the tree of a kosmos; return the tree a kosmos under kosmoi gives", .{ path, tree.type.name });
}

/// Applies `tree`, which the lowest of `scripts` built by calling Zig code, with the overrides
/// of the scripts above it and the command line's `--set`s.
fn applyBuilt(init: std.process.Init, tree: anytype, raw_arguments: []const []const u8, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams, scripts: []const script.Loaded) !void {
    const arena = init.arena.allocator();
    const arguments = try readArguments(init, struct {}, raw_arguments, diagnostics);
    if (arguments.parameters.len != 0)
        return fail(diagnostics, "{s} builds its own tree, so it takes no parameters, got '{s}'", .{ scripts[0].path, arguments.parameters[0] });
    const layers = try Layers.of(arena, scripts[1..]);
    for (scripts[1..]) |loaded| {
        if (loaded.script.params != null)
            return fail(diagnostics, "{s}: it sets parameters, but {s} builds its own tree and takes none", .{ loaded.path, scripts[0].path });
    }
    var built = tree;
    for (layers.overrides) |overrides| kosm.assign(@TypeOf(built), arena, &built, overrides, diagnostics) catch |err| switch (err) {
        error.InvalidAssignment => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };
    const home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{});
    try finish(init, &built, arguments, home, adapters, diagnostics, streams);
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
    const stack = try kosmos_call.callOnKosmosStack(Build.build, .{ arena, scripts, diagnostics }, &built, diagnostics);
    var tree = built catch |err| switch (err) {
        error.Reported => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };
    try kosmos_call.refuseDeadLists(arena, tree, &.{stack}, diagnostics);
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

/// The names of every kosmos in `sources`, comma-separated, or "none".
fn zigKosmosNames(comptime sources: []const ScriptTarget.KosmosSource) []const u8 {
    comptime var names: []const u8 = "";
    inline for (comptime kosmos_call.zigKosmoi(sources)) |entry| names = names ++ (if (names.len == 0) "" else ", ") ++ entry.name;
    return if (names.len == 0) "none" else names;
}

/// The name and origin of every kosmos in `sources`.
fn kosmosNames(comptime sources: []const ScriptTarget.KosmosSource) []const script.KosmosName {
    comptime var names: []const script.KosmosName = &.{};
    inline for (comptime kosmos_call.zigKosmoi(sources)) |entry| names = names ++ .{script.KosmosName{ .name = entry.name, .origin = entry.origin }};
    const final = names[0..names.len].*;
    return &final;
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
    std.testing.refAllDecls(completion_types);
    std.testing.refAllDecls(Sources);
    std.testing.refAllDecls(params);
    std.testing.refAllDecls(images);
    std.testing.refAllDecls(files);
    std.testing.refAllDecls(Places);
    std.testing.refAllDecls(lifetime);
    std.testing.refAllDecls(walk);
    std.testing.refAllDecls(script);
    std.testing.refAllDecls(kosmos_call);
    std.testing.refAllDecls(@import("bindings.zig"));
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
    return callScriptKosmosOn(arena, folder, &.{}, arguments, diagnostics);
}

/// Calls `scriptKosmos` with `arguments` on top of scripts' `layers`, the kosmos' folder being
/// `folder`.
fn callScriptKosmosOn(arena: std.mem.Allocator, folder: []const u8, layers: []const kosmos_call.Layer, arguments: []const []const u8, diagnostics: *kosm.Diagnostics) !ScriptTree {
    var stack: lifetime.Stack = undefined;
    var stderr: std.Io.Writer.Allocating = .init(arena);
    return kosmos_call.callKosmos(scriptKosmos, .{ .arguments = arguments, .layers = layers }, diagnostics, &stack, .{
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

test "a relative path a script sets starts from that script's folder" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var folder_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const folder = try tmpPath(&tmp, &folder_buffer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try tmp.dir.createDirPath(testing.io, "kosmoi/personal");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmoi/note.txt", .data = "top\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "kosmoi/personal/note.txt", .data = "variant\n" });
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "test" };
    const entries: []const kosm.Loose.Entry = &.{.{ .key = "script", .value = .{ .value = .{ .text = "note.txt" } } }};
    const table: kosm.Loose = .{ .value = .{ .table = entries } };
    const top = try std.Io.Dir.path.join(arena.allocator(), &.{ folder, "kosmoi" });
    const variant = try std.Io.Dir.path.join(arena.allocator(), &.{ folder, "kosmoi/personal" });

    try testing.expectEqualStrings("top\n", (try callScriptKosmosOn(arena.allocator(), folder, &.{.{ .values = table, .folder = top }}, &.{}, &diagnostics)).script);
    try testing.expectEqualStrings("variant\n", (try callScriptKosmosOn(arena.allocator(), folder, &.{ .{ .values = table, .folder = top }, .{ .values = table, .folder = variant } }, &.{}, &diagnostics)).script);
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
