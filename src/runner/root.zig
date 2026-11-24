//! The program `kosm apply` builds for one kosmos: parses its parameters and `--set`s, plans
//! every app, then prints the plan as a diff or commits it all or nothing, records the apply and
//! reloads the apps. For `kosm colors` it prints the themes of the tree instead of planning it.

const std = @import("std");
const kosm = @import("kosm");
const Record = @import("kosm_current");
const interface = @import("kosm_interface");
const kosmos_names = @import("kosm_names");
const Arguments = @import("Arguments.zig");
const apply_lock = @import("apply_lock.zig");
const Latest = Record.Latest;
const bindings = @import("bindings.zig");
const Runtime = @import("Runtime.zig");
const colors = @import("colors.zig");
const completions = @import("completions.zig");
const completion_types = @import("completion_types.zig");
const discovery = @import("discovery.zig");
const files = @import("files.zig");
const hosting = @import("hosting.zig");
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
/// Writes the Zig module of each app written through a frontend, for the build of a config.
pub const generateApps = @import("app_modules.zig").run;
/// Lists every kosmos and installed package in a config, for `kosm list`.
pub const list = list_module.list;
/// A module `list` looks into.
pub const ListSource = list_module.Source;

const list_module = @import("list.zig");

/// Runs the kosmos in `target` with the process arguments
/// (`[--param value]... [--set path=value]... [--diff] [--config dir]`).
/// Returns the exit status: 0 on success, 1 after printing what went wrong.
pub fn run(init: std.process.Init, comptime target: Target) !u8 {
    const Body = struct {
        fn call(given: std.process.Init) !u8 {
            return runHere(given, target);
        }
    };
    return onRunnerStack(init, Body.call);
}

/// `run` on the stack it was called on.
fn runHere(init: std.process.Init, comptime target: Target) !u8 {
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

    if (init.environ_map.get(interface.runner_variable) != null) {
        // Only the runner of scripts builds other kosmoi and runs apps, adapters, modifiers,
        // palette styles and packages' values written through a frontend.
        if (comptime kosmos_call.buildsOnKosmoi(ParamsOf(kosmos)) or hosting.holdsScriptApps(TreeOf(kosmos)) or hosting.holdsScriptAdapters(target.adapter_sources) or hosting.holdsScriptColors(target.adapter_sources) or hosting.holdsScriptExports(target.adapter_sources)) try streams.stdout.writeAll(interface.script_runner ++ "\n");
        try streams.stdout.flush();
        return 0;
    }
    if (init.environ_map.get(interface.completions_variable) != null) {
        try completions.write(streams.stdout, kosmos);
        try streams.stdout.flush();
        return 0;
    }

    const all_arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const folders: Folders = .{ .config = target.config, .kosmos = target.folder, .named = target.folders };
    return finishRun(applyAnnounced(init, kosmos, all_arguments[1..], folders, adapters, &diagnostics, streams), &diagnostics, streams);
}

/// Runs the script kosmos named by the first process argument, with the rest as `run` takes
/// them: reads it and every script below it, then applies it on its Zig kosmos, or on none.
/// Returns the exit status: 0 on success, 1 after printing what went wrong.
pub fn runScript(init: std.process.Init, comptime target: ScriptTarget) !u8 {
    const Body = struct {
        fn call(given: std.process.Init) !u8 {
            return runScriptHere(given, target);
        }
    };
    return onRunnerStack(init, Body.call);
}

/// Calls `body` with `init` on a thread with a stack as large as a kosmos', and gives what it
/// returns. Planning, delivering and reloading pass the tree and its apps by value, which in a
/// Debug build outgrows a process' usual 8 or 16 MiB as a kosmos does.
fn onRunnerStack(init: std.process.Init, comptime body: anytype) !u8 {
    const Result = @typeInfo(@TypeOf(body)).@"fn".return_type.?;
    const Call = struct {
        fn run(given: std.process.Init, result: *Result) void {
            result.* = body(given);
        }
    };
    var result: Result = undefined;
    const thread = std.Thread.spawn(.{ .stack_size = kosmos_call.kosmos_stack_size }, Call.run, .{ init, &result }) catch |err| {
        var buffer: [256]u8 = undefined;
        var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
        try stderr.interface.print("error: cannot start the thread kosm runs on: {s}\n", .{@errorName(err)});
        try stderr.interface.flush();
        return 1;
    };
    thread.join();
    return result;
}

/// `runScript` on the stack it was called on.
fn runScriptHere(init: std.process.Init, comptime target: ScriptTarget) !u8 {
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
    if (std.mem.eql(u8, all_arguments[1], interface.list_scripts_flag)) {
        var diagnostics: kosm.Diagnostics = .{ .kosmos = "" };
        return finishRun(writeScriptKosmoi(init, target, streams, &diagnostics), &diagnostics, streams);
    }
    if (std.mem.eql(u8, all_arguments[1], interface.list_frontends_flag)) {
        inline for (comptime discovery.frontends(target.adapter_sources)) |declared| {
            try streams.stdout.print("{s}\t{s}\n", .{ declared.frontend.name, declared.package });
        }
        try streams.stdout.flush();
        return 0;
    }
    if (std.mem.eql(u8, all_arguments[1], interface.scaffold_flag)) {
        var diagnostics: kosm.Diagnostics = .{ .kosmos = "" };
        return finishRun(writeScaffold(target, all_arguments[2..], streams.stdout, &diagnostics), &diagnostics, streams);
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
    // A frontend written through a frontend writes its completion through the host.
    var hosted: ScriptHosting(target) = .{ .state = .{ .arena = arena, .io = init.io, .config = target.config, .folders = target.folders, .library = .{} } };
    hosted.start();
    defer hosted.stop();
    inline for (comptime discovery.frontends(target.adapter_sources)) |declared| {
        const frontend = declared.frontend;
        if (frontend.complete) |complete| {
            const folder = try std.Io.Dir.path.join(arena, &.{ arguments[0], frontend.name });
            var context: kosm.Frontend.Context = .{ .arena = arena, .path = frontend.name };
            const written = complete(&context, completion) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidScript => return fail(diagnostics, "the {s} frontend cannot write its completion: {s}", .{ frontend.name, context.message orelse "it did not say why" }),
            };
            for (written) |file| try writeOutput(init.io, arena, folder, file, diagnostics);
        }
        if (frontend.editor_file) |file| try writeOutput(init.io, arena, arguments[1], file, diagnostics);
    }
}

/// Prints the extension and the scaffold `arguments` (a frontend's name and a kind) name, as
/// `interface.scaffold_flag` says.
fn writeScaffold(comptime target: ScriptTarget, arguments: []const []const u8, stdout: *std.Io.Writer, diagnostics: *kosm.Diagnostics) (Reported || std.Io.Writer.Error)!void {
    if (arguments.len != 2) return fail(diagnostics, "{s} needs a frontend's name and a kind", .{interface.scaffold_flag});
    const language = arguments[0];
    const kind = arguments[1];
    inline for (comptime discovery.frontends(target.adapter_sources)) |declared| {
        const frontend = declared.frontend;
        if (std.mem.eql(u8, frontend.name, language)) {
            inline for (@typeInfo(kosm.Frontend.Scaffolds).@"struct".field_names) |field_name| {
                if (std.mem.eql(u8, field_name, kind)) {
                    // A package's root holds an app, so a frontend without a scaffold of its own for one gives its app's.
                    const given: ?[]const u8 = if (comptime std.mem.eql(u8, field_name, "package")) frontend.scaffolds.package orelse frontend.scaffolds.app else @field(frontend.scaffolds, field_name);
                    const scaffold = given orelse
                        return fail(diagnostics, "the {s} frontend gives no {s} scaffold", .{ language, kind });
                    if (frontend.extensions.len == 0) return fail(diagnostics, "the {s} frontend claims no extension, so its scripts cannot be named", .{language});
                    try stdout.print("{s}\n{s}\n{s}", .{ frontend.extensions[0], declared.package, scaffold });
                    return;
                }
            }
            return fail(diagnostics, "{s} is not a kind kosm new scaffolds: kosmos, app, package, adapter, frontend, modifier, style or family", .{kind});
        }
    }
    return fail(diagnostics, "no frontend of this config is named '{s}'; kosm list --frontends lists them", .{language});
}

/// Prints every script kosmos and each variant it gives, `name<TAB>file` per line.
fn writeScriptKosmoi(init: std.process.Init, comptime target: ScriptTarget, streams: Streams, diagnostics: *kosm.Diagnostics) !void {
    var runtime = try scriptRuntime(init, target, &.{}, streams.stderr, diagnostics);
    var hosted: ScriptHosting(target) = .{ .state = .{ .arena = runtime.arena, .io = init.io, .config = target.config, .folders = target.folders, .library = ScriptLibrary(target).library(&runtime) } };
    hosted.start();
    defer hosted.stop();
    for (try script.listAll(KosmosBuilder(target).scriptContext(&runtime, diagnostics))) |kosmos| {
        try streams.stdout.print("{s}\t{s}\n", .{ kosmos.name, kosmos.origin });
    }
}

/// Fails with the closest names unless `name` is a Zig kosmos of `target` or a script kosmos
/// or variant in the config. The failure names no kosmos, since `name` is none.
fn checkKnown(comptime target: ScriptTarget, runtime: *Runtime, name: []const u8, diagnostics: *kosm.Diagnostics) script.Error!void {
    const zig_names = comptime zigKosmosNameList(target.kosmoi);
    if (kosmos_names.isKnown(name, zig_names)) return;
    const scripts = try script.listAll(KosmosBuilder(target).scriptContext(runtime, diagnostics));
    var known: std.ArrayList([]const u8) = try .initCapacity(runtime.arena, zig_names.len + scripts.len);
    known.appendSliceAssumeCapacity(zig_names);
    for (scripts) |kosmos| known.appendAssumeCapacity(kosmos.name);
    if (kosmos_names.isKnown(name, known.items)) return;
    diagnostics.kosmos = "";
    return fail(diagnostics, "{s}", .{try kosmos_names.unknownMessage(runtime.arena, name, known.items)});
}

/// Fails because the lowest of `scripts` builds on `base`, which is no kosmos.
fn unknownBase(comptime target: ScriptTarget, runtime: *Runtime, scripts: []const script.Loaded, base: []const u8, diagnostics: *kosm.Diagnostics) script.Error {
    var inner: kosm.Diagnostics = .{ .kosmos = "" };
    checkKnown(target, runtime, base, &inner) catch |err| switch (err) {
        error.Reported => return fail(diagnostics, "{s}: {s}", .{ scripts[0].path, inner.message() }),
        error.OutOfMemory => return error.OutOfMemory,
    };
    return fail(diagnostics, "{s} builds on '{s}', which is no Zig kosmos", .{ scripts[0].path, base });
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
    if (!staysInside(file.path)) return fail(diagnostics, "a frontend gave the file '{s}' to write; it is a path inside its folder, without '..'", .{file.path});
    const path = try std.Io.Dir.path.join(arena, &.{ folder, file.path });
    if (std.Io.Dir.path.dirname(path)) |directory| std.Io.Dir.cwd().createDirPath(io, directory) catch |err|
        return fail(diagnostics, "cannot create {s}: {s}", .{ directory, @errorName(err) });
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = file.contents }) catch |err|
        return fail(diagnostics, "cannot write {s}: {s}", .{ path, @errorName(err) });
}

/// Whether `path` is relative and never climbs out of the folder it is relative to.
fn staysInside(path: []const u8) bool {
    if (path.len == 0 or std.Io.Dir.path.isAbsolute(path)) return false;
    var segments = std.mem.tokenizeAny(u8, path, "/\\");
    while (segments.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return false;
    }
    return true;
}

/// The chain of script kosmos `name`, read through the frontends. Scripts' calls run with
/// `runtime`.
fn resolveScript(comptime target: ScriptTarget, runtime: *Runtime, name: []const u8, diagnostics: *kosm.Diagnostics) !script.Chain {
    var context = KosmosBuilder(target).scriptContext(runtime, diagnostics);
    context.building = &runtime.building;
    return script.resolve(context, name);
}

/// Every module, kosmos and value of the config a script may call.
fn ScriptLibrary(comptime target: ScriptTarget) type {
    comptime var roots: []const bindings.Root = &.{};
    inline for (target.kosmoi) |source| roots = roots ++ .{bindings.Root{ .name = source.name, .module = source.module }};
    const final = roots[0..roots.len].*;
    return bindings.Library(&final, kosmos_call.zigKosmoi(target.kosmoi));
}

/// The host apps written through a frontend run through.
fn ScriptHost(comptime target: ScriptTarget) type {
    return hosting.Hosting(comptime discovery.frontends(target.adapter_sources), ScriptLibrary(target), comptime hosting.handledTypes(target.kosmoi, target.reached));
}

/// The host scripts' functions run through, from `start` until `stop`; it must not move
/// meanwhile.
fn ScriptHosting(comptime target: ScriptTarget) type {
    return struct {
        const Hosting = @This();

        state: ScriptHost(target).State,
        host: kosm.Frontend.Host = undefined,

        fn start(hosted: *Hosting) void {
            hosted.host = ScriptHost(target).host(&hosted.state);
            kosm.Frontend.Host.install(&hosted.host);
        }

        fn stop(_: *Hosting) void {
            kosm.Frontend.Host.install(null);
        }
    };
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

/// The tree types a script may return, each once: what every Zig kosmos in `sources` returns,
/// and every struct of apps a module of `sources` declares at its top (a base).
fn treeTypes(comptime sources: []const ScriptTarget.KosmosSource) []const type {
    comptime var found: []const type = &.{};
    inline for (comptime kosmos_call.zigKosmoi(sources)) |entry| {
        found = withType(found, discovery.Payload(@typeInfo(@TypeOf(@field(entry.Namespace, entry.function))).@"fn".return_type.?));
    }
    inline for (sources) |source| {
        inline for (comptime discovery.exportedTrees(source.module)) |Tree| found = withType(found, Tree);
    }
    const final = found[0..found.len].*;
    return &final;
}

fn withType(comptime found: []const type, comptime T: type) []const type {
    inline for (found) |Earlier| {
        if (Earlier == T) return found;
    }
    return found ++ .{T};
}

/// What completes a script's arguments: the Zig kosmos it builds on (a `base` line), then that
/// kosmos' parameters and `--set` paths, or without one the `--set` paths of every app.
fn writeScriptCompletions(init: std.process.Init, comptime target: ScriptTarget, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const stdout = streams.stdout;
    var runtime = try scriptRuntime(init, target, &.{}, streams.stderr, diagnostics);
    var hosted: ScriptHosting(target) = .{ .state = .{ .arena = runtime.arena, .io = init.io, .config = target.config, .folders = target.folders, .library = ScriptLibrary(target).library(&runtime) } };
    hosted.start();
    defer hosted.stop();
    // A Zig kosmos sent here (one in a script kosmos' folder) completes as its own runner would.
    if (try script.locate(KosmosBuilder(target).scriptContext(&runtime, diagnostics), diagnostics.kosmos) == null) {
        inline for (comptime kosmos_call.zigKosmoi(target.kosmoi)) |entry| {
            if (std.mem.eql(u8, diagnostics.kosmos, entry.name)) return completions.write(stdout, @field(entry.Namespace, entry.function));
        }
    }
    const chain = try resolveScript(target, &runtime, diagnostics.kosmos, diagnostics);
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
    return unknownBase(target, &runtime, chain.scripts, base, diagnostics);
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
        terminal.stdout = std.Io.File.stdout().writerStreaming(init.io, &terminal.stdout_buffer);
        terminal.stderr = std.Io.File.stderr().writerStreaming(init.io, &terminal.stderr_buffer);
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

/// `apply` for a kosmos alone in its runner, once it has said it is the newest apply.
fn applyAnnounced(init: std.process.Init, comptime kosmos: anytype, raw_arguments: []const []const u8, folders: Folders, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const latest = try announceApply(init, raw_arguments, diagnostics);
    return apply(init, kosmos, raw_arguments, folders, adapters, diagnostics, streams, .{}, null, latest);
}

/// Says this apply is the newest before anything is built, so a later apply wins over this one
/// even when this one takes longer to build: takes the token the command line announced, else
/// announces one. Null on `--diff`, for `kosm colors`, and when there is no state directory.
fn announceApply(init: std.process.Init, raw_arguments: []const []const u8, diagnostics: *kosm.Diagnostics) !?Latest {
    if (init.environ_map.get(interface.colors_variable) != null) return null;
    // Arguments that do not split are reported once they are read for the apply.
    const typed = Arguments.split(init.arena.allocator(), raw_arguments) catch return null;
    if (typed.diff) return null;
    const path = try Record.statePath(init.arena.allocator(), init.environ_map, Latest.file_name) orelse return null;
    if (init.environ_map.get(interface.apply_token_variable)) |token| {
        return Latest.adopt(path, token) orelse
            fail(diagnostics, "{s} is '{s}', which is no token the command line announced; it is {d} hex digits", .{ interface.apply_token_variable, token, Latest.token_length });
    }
    return Latest.announce(init.io, path) catch |err|
        fail(diagnostics, "cannot write {s}, which tells an older apply that this one is newer: {s}", .{ path, @errorName(err) });
}

/// Calls `kosmos` with the command line's parameters on top of `layers.params`, assigns
/// `layers.overrides`, then the `--set`s, and plans and delivers the tree.
/// `kosmoi` builds the kosmoi its `Params` name, in the runner of scripts.
fn apply(init: std.process.Init, comptime kosmos: anytype, raw_arguments: []const []const u8, folders: Folders, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams, layers: Layers, kosmoi: ?kosmos_call.Builder, latest: ?Latest) !void {
    const arena = init.arena.allocator();
    const arguments = try readArguments(init, ParamsOf(kosmos), raw_arguments, diagnostics);
    const home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{});
    var kosmos_stack: lifetime.Stack = undefined;
    var tree = try kosmos_call.callKosmos(kosmos, .{ .arguments = arguments.parameters, .layers = layers.params, .kosmoi = kosmoi }, diagnostics, &kosmos_stack, .{
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
    try assignOverrides(arena, &tree, layers.overrides, diagnostics);
    try finish(init, &tree, arguments, home, adapters, diagnostics, streams, latest);
}

/// Assigns each of `overrides` in `tree`, the lowest script's first.
fn assignOverrides(arena: std.mem.Allocator, tree: anytype, overrides: []const kosm.Loose, diagnostics: *kosm.Diagnostics) !void {
    for (overrides) |given| kosm.assign(@TypeOf(tree.*), arena, tree, given, diagnostics) catch |err| switch (err) {
        error.InvalidAssignment => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };
}

/// Reads the script kosmos `diagnostics.kosmos` and applies it on what it builds on.
fn applyScript(init: std.process.Init, comptime target: ScriptTarget, raw_arguments: []const []const u8, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const arena = init.arena.allocator();
    const latest = try announceApply(init, raw_arguments, diagnostics);
    const adapters = comptime discovery.adapters(target.adapter_sources);
    var runtime = try scriptRuntime(init, target, raw_arguments, streams.stderr, diagnostics);
    runtime.kosmoi = KosmosBuilder(target).of(&runtime);
    var hosted: ScriptHosting(target) = .{ .state = .{ .arena = arena, .io = init.io, .config = target.config, .folders = target.folders, .library = ScriptLibrary(target).library(&runtime) } };
    hosted.start();
    defer hosted.stop();
    try checkKnown(target, &runtime, diagnostics.kosmos, diagnostics);
    // A Zig kosmos building on another, or in the folder of a script kosmos, is applied here,
    // where every kosmos can be built; locating fails when a script gives its name too.
    const is_script = try script.locate(KosmosBuilder(target).scriptContext(&runtime, diagnostics), diagnostics.kosmos) != null;
    inline for (comptime kosmos_call.zigKosmoi(target.kosmoi)) |entry| {
        if (!is_script and std.mem.eql(u8, diagnostics.kosmos, entry.name)) {
            try runtime.building.enter(arena, entry.name, diagnostics);
            const folders: Folders = .{ .config = target.config, .kosmos = entry.folder, .named = target.folders };
            return apply(init, @field(entry.Namespace, entry.function), raw_arguments, folders, adapters, diagnostics, streams, .{}, runtime.kosmoi, latest);
        }
    }
    const chain = try resolveScript(target, &runtime, diagnostics.kosmos, diagnostics);
    if (chain.tree) |tree| {
        inline for (comptime treeTypes(target.kosmoi)) |Tree| {
            if (tree.as(Tree)) |built| return applyBuilt(init, built.*, raw_arguments, adapters, diagnostics, streams, chain.scripts, latest);
        }
        return notATree(diagnostics, chain.scripts[0].path, tree);
    }
    const base = chain.base orelse return applyStandalone(init, target, raw_arguments, adapters, diagnostics, streams, chain.scripts, latest);
    const layers = try Layers.of(arena, chain.scripts);
    inline for (comptime kosmos_call.zigKosmoi(target.kosmoi)) |entry| {
        if (std.mem.eql(u8, base, entry.name)) {
            try runtime.building.enter(arena, entry.name, diagnostics);
            const folders: Folders = .{ .config = target.config, .kosmos = entry.folder, .named = target.folders };
            return apply(init, @field(entry.Namespace, entry.function), raw_arguments, folders, adapters, diagnostics, streams, layers, runtime.kosmoi, latest);
        }
    }
    return unknownBase(target, &runtime, chain.scripts, base, diagnostics);
}

/// Builds a kosmos named in a `kosm.Kosmos` field, Zig or script, with every kosmos `target`
/// holds to build on, and keeps its tree for the whole run.
fn KosmosBuilder(comptime target: ScriptTarget) type {
    return struct {
        fn of(runtime: *Runtime) kosmos_call.Builder {
            return .{ .state = runtime, .build = build };
        }

        fn build(state: *anyopaque, name: []const u8, tree: *const anyopaque, tree_name: []const u8, diagnostics: *kosm.Diagnostics) images.Error!*const anyopaque {
            const runtime: *Runtime = @ptrCast(@alignCast(state));
            const depth = runtime.building.depth();
            defer runtime.building.restore(depth);
            const scripts_folder = runtime.scripts_folder;
            defer runtime.scripts_folder = scripts_folder;
            try checkKnown(target, runtime, name, diagnostics);
            // Locating first fails on a script and a Zig kosmos giving the same name.
            const location = try script.locate(scriptContext(runtime, diagnostics), name);
            if (location == null) if (zigKosmos(name)) |index| return buildZig(runtime, index, .{}, tree, tree_name, diagnostics);
            if (location == null) return fail(diagnostics, "there is no such kosmos", .{});
            const chain = try resolveScript(target, runtime, name, diagnostics);
            if (chain.tree) |handle| return buildOnTree(runtime, handle, chain.scripts, tree, tree_name, diagnostics);
            const base = chain.base orelse
                return fail(diagnostics, "{s} builds on no kosmos, so its tree is not a {s}; build it on a kosmos giving one", .{ chain.scripts[0].path, tree_name });
            const index = zigKosmos(base) orelse return unknownBase(target, runtime, chain.scripts, base, diagnostics);
            return buildZig(runtime, index, try Layers.of(runtime.arena, chain.scripts), tree, tree_name, diagnostics);
        }

        const kosmoi = kosmos_call.zigKosmoi(target.kosmoi);

        fn zigKosmos(name: []const u8) ?usize {
            inline for (kosmoi, 0..) |entry, index| {
                if (std.mem.eql(u8, name, entry.name)) return index;
            }
            return null;
        }

        /// Calls Zig kosmos `kosmoi[index]` on `layers`, once its tree is known to be the wanted one.
        fn buildZig(runtime: *Runtime, index: usize, layers: Layers, tree: *const anyopaque, tree_name: []const u8, diagnostics: *kosm.Diagnostics) images.Error!*const anyopaque {
            inline for (kosmoi, 0..) |entry, entry_index| {
                if (entry_index == index) return buildEntry(entry, runtime, layers, tree, tree_name, diagnostics);
            }
            unreachable; // `index` comes from `zigKosmos`.
        }

        /// `buildZig` for one kosmos. Never inlined, so its tree takes stack only while it is
        /// built, not once for every kosmos in the config.
        noinline fn buildEntry(comptime entry: kosmos_call.ZigKosmos, runtime: *Runtime, layers: Layers, tree: *const anyopaque, tree_name: []const u8, diagnostics: *kosm.Diagnostics) images.Error!*const anyopaque {
            const kosmos = @field(entry.Namespace, entry.function);
            const Tree = discovery.Payload(@typeInfo(@TypeOf(kosmos)).@"fn".return_type.?);
            if (kosm.Frontend.Handle.id(Tree) != tree)
                return fail(diagnostics, "'{s}' gives a {s}, not a {s}", .{ entry.name, @typeName(Tree), tree_name });
            try runtime.building.enter(runtime.arena, entry.name, diagnostics);
            var stack: lifetime.Stack = undefined;
            var built = try kosmos_call.callKosmos(kosmos, .{ .arguments = &.{}, .layers = layers.params, .kosmoi = runtime.kosmoi }, diagnostics, &stack, runtime.loading(entry.folder, diagnostics));
            try kosmos_call.refuseDeadLists(runtime.arena, built, &.{ .below(@intFromPtr(&built)), stack }, diagnostics);
            try assignOverrides(runtime.arena, &built, layers.overrides, diagnostics);
            return keep(runtime, Tree, built);
        }

        /// The tree the lowest of `scripts` built by calling Zig code, with the overrides of the
        /// scripts above it.
        fn buildOnTree(runtime: *Runtime, handle: kosm.Frontend.Handle, scripts: []const script.Loaded, tree: *const anyopaque, tree_name: []const u8, diagnostics: *kosm.Diagnostics) images.Error!*const anyopaque {
            if (handle.type.id != tree)
                return fail(diagnostics, "{s} returns a {s}, not a {s}", .{ scripts[0].path, handle.type.name, tree_name });
            for (scripts[1..]) |loaded| {
                if (loaded.script.params != null)
                    return fail(diagnostics, "{s}: it sets parameters, but {s} builds its own tree and takes none", .{ loaded.path, scripts[0].path });
            }
            const layers = try Layers.of(runtime.arena, scripts[1..]);
            inline for (comptime treeTypes(target.kosmoi)) |Tree| {
                if (handle.as(Tree)) |built| return keepWithOverrides(runtime, Tree, built, layers, diagnostics);
            }
            return notATree(diagnostics, scripts[0].path, handle);
        }

        /// A copy of `built` with `layers`' overrides. Never inlined, so its copy takes stack
        /// only for the one tree type it is called with.
        noinline fn keepWithOverrides(runtime: *Runtime, comptime Tree: type, built: *const Tree, layers: Layers, diagnostics: *kosm.Diagnostics) images.Error!*const anyopaque {
            var copy = built.*;
            try assignOverrides(runtime.arena, &copy, layers.overrides, diagnostics);
            return keep(runtime, Tree, copy);
        }

        fn keep(runtime: *Runtime, comptime Tree: type, built: Tree) std.mem.Allocator.Error!*const anyopaque {
            const kept = try runtime.arena.create(Tree);
            kept.* = built;
            return kept;
        }

        /// What finding and reading scripts needs, the scripts' calls running with `runtime`.
        fn scriptContext(runtime: *Runtime, diagnostics: *kosm.Diagnostics) script.Context {
            return .{
                .arena = runtime.arena,
                .io = runtime.io,
                .config = target.config,
                .frontends = comptime discovery.frontends(target.adapter_sources),
                .modules = comptime moduleNames(target.kosmoi),
                .kosmoi = comptime kosmosNames(target.kosmoi),
                .packages = comptime packageKosmoi(target.kosmoi),
                .exporting = comptime exportingScripts(target.kosmoi),
                .library = ScriptLibrary(target).library(runtime),
                .calls_folder = &runtime.scripts_folder,
                .diagnostics = diagnostics,
            };
        }
    };
}

fn notATree(diagnostics: *kosm.Diagnostics, path: []const u8, tree: kosm.Frontend.Handle) Reported {
    return fail(diagnostics, "{s} returns a {s}, which is not the tree of a kosmos; return the tree a Zig kosmos gives, or a struct of apps a package or kosmos declares at its top (a base)", .{ path, tree.type.name });
}

/// Applies `tree`, which the lowest of `scripts` built by calling Zig code, with the overrides
/// of the scripts above it and the command line's `--set`s.
fn applyBuilt(init: std.process.Init, tree: anytype, raw_arguments: []const []const u8, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams, scripts: []const script.Loaded, latest: ?Latest) !void {
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
    try assignOverrides(arena, &built, layers.overrides, diagnostics);
    const home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{});
    try finish(init, &built, arguments, home, adapters, diagnostics, streams, latest);
}

/// Builds the tree of a kosmos with no Zig kosmos below it from its scripts alone, then
/// plans and delivers it.
fn applyStandalone(init: std.process.Init, comptime target: ScriptTarget, raw_arguments: []const []const u8, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams, scripts: []const script.Loaded, latest: ?Latest) !void {
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
    try finish(init, &tree, arguments, home, adapters, diagnostics, streams, latest);
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

/// Assigns the `--set`s inside `tree`, a pointer to the built tree, then plans and delivers it,
/// unless an apply newer than `latest` started.
fn finish(init: std.process.Init, tree: anytype, arguments: Arguments, home: []const u8, adapters: discovery.Adapters, diagnostics: *kosm.Diagnostics, streams: Streams, latest: ?Latest) !void {
    const arena = init.arena.allocator();
    for (arguments.assignments) |assignment| set.assign(arena, tree, assignment, diagnostics) catch |err| switch (err) {
        error.InvalidAssignment => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (init.environ_map.get(interface.colors_variable) != null) return showColors(tree.*, diagnostics, streams);

    const lock = if (arguments.diff) null else try lockApply(init, diagnostics, streams.stderr);
    defer if (lock) |file| file.close(init.io);
    if (latest) |mark| if (!mark.isNewest(init.io)) return report.superseded(streams.stderr);
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
        .reload_all = arguments.reload,
        .recording = try recording(arena, init.environ_map, diagnostics.kosmos, arguments),
        .latest = latest,
        .diagnostics = diagnostics,
        .streams = streams,
    });
}

/// Waits for any other apply to finish and holds the lock until the returned file is closed,
/// so the files this one plans are not changed by it meanwhile. Null when there is no state
/// directory to keep the lock in.
fn lockApply(init: std.process.Init, diagnostics: *kosm.Diagnostics, stderr: *std.Io.Writer) !?std.Io.File {
    const path = try Record.statePath(init.arena.allocator(), init.environ_map, apply_lock.file_name) orelse return null;
    return apply_lock.acquire(init.io, path, stderr) catch |err| switch (err) {
        error.WriteFailed => return error.WriteFailed,
        else => return fail(diagnostics, "cannot lock {s} against another apply: {s}", .{ path, @errorName(err) }),
    };
}

/// Prints every theme in `tree`, for `kosm colors`, or fails when it holds none.
fn showColors(tree: anytype, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const shown = try colors.writeThemes(streams.stdout, tree, streams.stdout_mode == .escape_codes);
    if (shown == 0) return fail(diagnostics, "it holds no kosm.Theme, so there are no colors to show; a base keeps the theme its apps were built from in its `theme` field", .{});
}

/// The name of every kosmos in `sources`.
fn zigKosmosNameList(comptime sources: []const ScriptTarget.KosmosSource) []const []const u8 {
    comptime var found: []const []const u8 = &.{};
    inline for (comptime kosmos_call.zigKosmoi(sources)) |entry| found = found ++ .{entry.name};
    const final = found[0..found.len].*;
    return &final;
}

/// The name and origin of every kosmos in `sources`.
fn kosmosNames(comptime sources: []const ScriptTarget.KosmosSource) []const script.KosmosName {
    comptime var names: []const script.KosmosName = &.{};
    inline for (comptime kosmos_call.zigKosmoi(sources)) |entry| names = names ++ .{script.KosmosName{ .name = entry.name, .origin = entry.origin }};
    const final = names[0..names.len].*;
    return &final;
}

/// Every module of `sources` that is the generated module of a package whose root script gives
/// its kosmos. A kosmos script in the config's `kosmoi/` has such a module too, but is found
/// where it is.
fn packageKosmoi(comptime sources: []const ScriptTarget.KosmosSource) []const script.PackageKosmos {
    comptime var found: []const script.PackageKosmos = &.{};
    inline for (sources) |source| {
        if (comptime hosting.isScriptKosmos(source.module) and !isConfigScript(source.module)) {
            const path = source.module.script.path;
            found = found ++ .{script.PackageKosmos{ .name = source.name, .path = path, .file = source.folder ++ "/" ++ comptime std.Io.Dir.path.basename(path) }};
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

/// The import name of every module in `sources` but those of the config's kosmos scripts that
/// give a kosmos, which is the script itself.
fn moduleNames(comptime sources: []const ScriptTarget.KosmosSource) []const []const u8 {
    comptime var names: []const []const u8 = &.{};
    inline for (sources) |source| {
        if (comptime !(hosting.isScriptKosmos(source.module) and isConfigScript(source.module))) names = names ++ .{source.name};
    }
    const final = names[0..names.len].*;
    return &final;
}

/// The path of every kosmos script in the config's `kosmoi/` that exports values for building
/// on: its module gives them, and its kosmos and variants are Zig kosmoi, so it is no script
/// kosmos.
fn exportingScripts(comptime sources: []const ScriptTarget.KosmosSource) []const []const u8 {
    comptime var paths: []const []const u8 = &.{};
    inline for (sources) |source| {
        if (comptime hosting.isScriptExports(source.module) and isConfigScript(source.module)) paths = paths ++ .{source.module.script.path};
    }
    const final = paths[0..paths.len].*;
    return &final;
}

/// Whether generated module `Module` comes from a script of the config rather than a
/// package's root script, which is named through its package's folder (`~~kosm_frost/`).
fn isConfigScript(comptime Module: type) bool {
    return !std.mem.startsWith(u8, Module.script.path, "~~");
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
    /// Reload every app, not only those whose files changed.
    reload_all: bool = false,
    /// Saved after a successful commit; null records nothing.
    recording: ?Recording,
    /// Tells whether a newer apply started, which makes this one write nothing; null never does.
    latest: ?Latest = null,
    diagnostics: *kosm.Diagnostics,
    streams: Streams,
};

/// Prints the plan as a diff, or commits it, records the apply and then reloads the apps in
/// `tree` whose files changed (every app with `reload_all`). A failed commit records and
/// reloads nothing.
fn deliver(tree: anytype, plan: *kosm.Plan, delivery: Delivery) !void {
    const stdout = delivery.streams.stdout;
    if (delivery.diff) {
        if (!plan.hasChanges()) return report.nothingToChange(stdout);
        return kosm.diff.writePlan(delivery.gpa, .{ .writer = stdout, .mode = delivery.streams.stdout_mode }, plan);
    }
    if (delivery.latest) |latest| if (!latest.isNewest(delivery.io)) return report.superseded(delivery.streams.stderr);
    if (plan.hasChanges()) {
        var failure: kosm.commit.Failure = .{};
        kosm.commit.writePlan(delivery.gpa, delivery.io, plan, &failure) catch |err| {
            const app = try delivery.arena.dupe(u8, ownerOf(plan, failure.path));
            const file = try delivery.arena.dupe(u8, failure.path);
            if (err == error.ChangedSinceRead)
                delivery.diagnostics.set(app, file, "it changed since kosm read it, so nothing was written; apply again", .{})
            else if (failure.not_restored != 0)
                delivery.diagnostics.set(app, file, "cannot write it: {s}; {d} of the files written before it could not be put back as they were", .{ @errorName(err), failure.not_restored })
            else
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
    const reloads: walk.Reloads = if (delivery.reload_all) .all else .{ .changed = plan };
    try walk.reloadTree(tree, reloads, delivery.io, delivery.home, delivery.diagnostics.kosmos, delivery.streams.stderr);
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
fn TreeOf(comptime kosmos: anytype) type {
    return discovery.Payload(@typeInfo(@TypeOf(kosmos)).@"fn".return_type.?);
}

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
    std.testing.refAllDecls(apply_lock);
    std.testing.refAllDecls(@import("app_modules.zig"));
    std.testing.refAllDecls(@import("adapter_modules.zig"));
    std.testing.refAllDecls(@import("frontend_modules.zig"));
    std.testing.refAllDecls(@import("color_modules.zig"));
    std.testing.refAllDecls(@import("export_modules.zig"));
    std.testing.refAllDecls(hosting);
    std.testing.refAllDecls(set);
    std.testing.refAllDecls(discovery);
    std.testing.refAllDecls(@import("inspect.zig"));
    std.testing.refAllDecls(list_module);
    std.testing.refAllDecls(colors);
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

/// `planAndDeliver` committing, then reloading every app as `--reload` asks.
fn planAndReloadAll(arena: *std.heap.ArenaAllocator, tree: anytype, home: []const u8, diagnostics: *kosm.Diagnostics, output: *std.Io.Writer.Allocating) !void {
    return planAndDeliverWith(arena, tree, home, false, true, null, diagnostics, output);
}

/// `planAndDeliver`, saving `recorded` after a commit.
fn planAndRecord(arena: *std.heap.ArenaAllocator, tree: anytype, home: []const u8, diff: bool, recorded: ?Recording, diagnostics: *kosm.Diagnostics, output: *std.Io.Writer.Allocating) !void {
    return planAndDeliverWith(arena, tree, home, diff, false, recorded, diagnostics, output);
}

fn planAndDeliverWith(arena: *std.heap.ArenaAllocator, tree: anytype, home: []const u8, diff: bool, reload_all: bool, recorded: ?Recording, diagnostics: *kosm.Diagnostics, output: *std.Io.Writer.Allocating) !void {
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
        .reload_all = reload_all,
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

test "a commit reloads an app only when its files changed, or every app with --reload" {
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
    try testing.expectEqual(1, reloads);
    try testing.expectEqualStrings("nothing to change\n", second.written());

    var forced: std.Io.Writer.Allocating = .init(testing.allocator);
    defer forced.deinit();
    try planAndReloadAll(&arena, tree, home, &diagnostics, &forced);
    try testing.expectEqual(2, reloads);
}

test "an apply that a newer one started after writes and reloads nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var reloads: usize = 0;
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "nord" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const tree = .{ .kitty = ReloadingApp{ .file = "~/a.lines", .reloads = &reloads } };
    const latest_path = try std.Io.Dir.path.join(arena.allocator(), &.{ home, "state", Latest.file_name });
    const nord = try Latest.announce(testing.io, latest_path);
    _ = try Latest.announce(testing.io, latest_path);

    var plan: kosm.Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    var stderr_buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdout: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stdout.deinit();
    var gathered: kosm.Warnings = .init(arena.allocator());
    try planWarning(tree, .{ .allocator = arena.allocator(), .home = home, .adapters = &.{lines_adapter}, .plan = &plan, .diagnostics = &diagnostics, .warnings = &gathered }, &stderr);
    try deliver(tree, &plan, .{
        .gpa = testing.allocator,
        .arena = arena.allocator(),
        .io = testing.io,
        .home = home,
        .diff = false,
        .recording = null,
        .latest = nord,
        .diagnostics = &diagnostics,
        .streams = .{ .stdout = &stdout.writer, .stderr = &stderr, .stdout_mode = .no_color },
    });
    try testing.expectEqualStrings("a newer kosm apply started, so this one wrote nothing\n", stderr.buffered());
    try testing.expectEqualStrings("", stdout.written());
    try testing.expectEqual(0, reloads);
    try testing.expectError(error.FileNotFound, tmp.dir.statFile(testing.io, "a.lines", .{}));
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

test "a file a frontend writes stays inside its folder" {
    try std.testing.expect(staysInside("types/all.lua"));
    try std.testing.expect(staysInside(".luarc.json"));
    try std.testing.expect(!staysInside("../../.bashrc"));
    try std.testing.expect(!staysInside("types/../../x"));
    try std.testing.expect(!staysInside("/etc/passwd"));
    try std.testing.expect(!staysInside(""));
}
