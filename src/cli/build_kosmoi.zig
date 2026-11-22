//! `kosm build`: compiles the runners of the kosmoi the command line or `kosm.zon` picks (every
//! kosmos in `kosmoi/` by default) in one `zig build`, so the next `kosm apply` of any of them
//! compiles nothing until a file changes. When a script kosmos, or a Zig kosmos building on
//! another, is picked, it also builds the runner every script kosmos shares.

const std = @import("std");
const Context = @import("Context.zig");
const Settings = @import("Settings.zig");
const interface = @import("kosm_interface");
const scripts = @import("scripts.zig");
const known_kosmoi = @import("known_kosmoi.zig");
const kosmos_names = @import("kosm_names");

pub const Error = Context.RunError;

/// Where `addConfigProject` marks each kosmos `-Dprebuild=` compiled, with an empty file.
const markers_path = "zig-out/prebuilt";
/// Where the kosmoi `Selection.all` means are declared, as the lister spells origins.
const kosmoi_directory = "kosmoi/";

/// Lists the config's kosmoi, compiles those `selection` picks (`kosm.zon`'s choice when null),
/// and names each one that does not compile after the others are built.
pub fn build(context: Context, selection: ?Settings.Selection) Error!void {
    const chosen = selection orelse try loadSelection(context);
    const subject = if (selection == null) try std.Io.Dir.path.join(context.arena, &.{ context.config, Settings.file_name }) else "";
    // Listing them builds the config's lister, which takes a while.
    try context.stdout.writeAll("finding the kosmoi\n");
    const picked_names = try pick(context, chosen, subject);
    const picked = try splitScripts(context, picked_names);
    const names = picked.zig;
    // A Zig kosmos building on another is applied by the runner of scripts, so it is built too.
    const with_scripts = picked.scripts != 0 or try anyBuildsOnKosmoi(context, names);
    if (names.len == 0 and !with_scripts) return context.stdout.writeAll("no kosmoi to build\n");
    const scripts_built = !with_scripts or try buildScripts(context);
    if (names.len == 0) return if (scripts_built) {} else error.Failed;
    try context.stdout.print("building {d} kosmo{s}: {s}\n", .{ names.len, if (names.len == 1) "s" else "i", try std.mem.join(context.arena, ", ", names) });
    try context.stdout.flush();

    const markers = try std.Io.Dir.path.join(context.arena, &.{ context.config, markers_path });
    try deleteMarkers(context, markers);
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.append(context.arena, "build");
    for (names) |name| try arguments.append(context.arena, try context.arena.print("-Dprebuild={s}", .{name}));
    // Which kosmoi failed is read from the markers, so the build's own result adds nothing.
    _ = try context.runBuild(arguments.items);

    var failed: std.ArrayList([]const u8) = .empty;
    for (names) |name| {
        const marker = try std.Io.Dir.path.join(context.arena, &.{ markers, name });
        if (std.Io.Dir.cwd().access(context.io, marker, .{})) |_| {
            try context.stdout.print("built {s}\n", .{name});
        } else |err| switch (err) {
            error.FileNotFound => try failed.append(context.arena, name),
            else => return context.fail("cannot check {s}: {s}", .{ marker, @errorName(err) }),
        }
    }
    try deleteMarkers(context, markers);
    if (failed.items.len == 0) return if (scripts_built) {} else error.Failed;
    try context.stdout.flush();
    return context.fail("{s} {s} {s} not build{s}", .{
        if (failed.items.len == 1) "kosmos" else "kosmoi",
        try std.mem.join(context.arena, ", ", failed.items),
        if (failed.items.len == 1) "does" else "do",
        if (failed.items.len == names.len) "" else "; the others are built",
    });
}

/// The picked names split into Zig kosmoi, each compiled into a runner of its own, and how many
/// are scripts, which share one runner.
const Picked = struct { zig: []const []const u8, scripts: usize };

fn splitScripts(context: Context, names: []const []const u8) Error!Picked {
    var zig: std.ArrayList([]const u8) = .empty;
    var script_count: usize = 0;
    for (names) |name| {
        if (try scripts.isScript(context, name)) script_count += 1 else try zig.append(context.arena, name);
    }
    return .{ .zig = zig.items, .scripts = script_count };
}

/// Builds the runner every script kosmos shares, naming it in the report; returns whether it built.
fn buildScripts(context: Context) Error!bool {
    if (try scripts.buildReporting(context)) return true;
    try context.stderr.writeAll("error: the script runner does not build, so no script kosmos can be applied\n");
    return false;
}

const Listed = known_kosmoi.Listed;

/// The kosmoi `selection` picks, in listing order. Script variants are listed only when a name
/// is none of the other kosmoi; a name that is none at all fails naming the closest, after
/// `subject` when it is not empty.
fn pick(context: Context, selection: Settings.Selection, subject: []const u8) Error![]const []const u8 {
    var listed = try known_kosmoi.list(context, .without_script_variants);
    var selected = try select(context.arena, listed, selection);
    if (selected == .unknown and try scripts.any(context)) {
        listed = try known_kosmoi.list(context, .with_script_variants);
        selected = try select(context.arena, listed, selection);
    }
    return switch (selected) {
        .names => |names| names,
        .unknown => |name| context.fail("{s}{s}{s}", .{ subject, if (subject.len == 0) "" else ": ", try kosmos_names.unknownMessage(context.arena, name, try known_kosmoi.nameList(context.arena, listed)) }),
    };
}

/// What a selection picks: the kosmoi to build, in listing order, or the first name it gives
/// that matches no kosmos.
const Selected = union(enum) {
    names: []const []const u8,
    unknown: []const u8,
};

/// The kosmoi in `listed` that `selection` picks.
fn select(arena: std.mem.Allocator, listed: []const Listed, selection: Settings.Selection) std.mem.Allocator.Error!Selected {
    const given: []const []const u8 = switch (selection) {
        .all => &.{},
        .only, .except => |given| given,
    };
    for (given) |name| {
        if (!known_kosmoi.matches(name, listed, .or_holder)) return .{ .unknown = name };
    }
    var names: std.ArrayList([]const u8) = .empty;
    for (listed) |kosmos| {
        const named = for (given) |name| {
            if (kosmos_names.picks(name, kosmos.name)) break true;
        } else false;
        const picked = switch (selection) {
            .all => isInKosmoiDirectory(kosmos),
            .only => named,
            .except => isInKosmoiDirectory(kosmos) and !named,
        };
        if (picked) try names.append(arena, kosmos.name);
    }
    return .{ .names = names.items };
}

fn isInKosmoiDirectory(kosmos: Listed) bool {
    return std.mem.startsWith(u8, kosmos.origin, kosmoi_directory);
}

/// `kosm.zon`'s `build`, or `.all` when the file is missing.
fn loadSelection(context: Context) Error!Settings.Selection {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, Settings.file_name });
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const settings = Settings.load(context.arena, context.io, path, &diagnostics) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseZon => {
            try context.stderr.print("{f}\n", .{diagnostics.fmt(path)});
            return context.fail("cannot read {s}", .{path});
        },
        else => return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) }),
    };
    return settings.build;
}

/// Whether any of the Zig kosmoi `names` builds on another kosmos, as the lister built by
/// `known_kosmoi.list` reports.
fn anyBuildsOnKosmoi(context: Context, names: []const []const u8) Error!bool {
    var environ: std.process.Environ.Map = if (context.environ_map) |map| try map.clone(context.arena) else .init(context.arena);
    try environ.put(interface.runner_variable, "1");
    var asking = context;
    asking.environ_map = &environ;
    const result = try asking.run(&.{try std.Io.Dir.path.join(context.arena, &.{ context.config, known_kosmoi.lister_path })});
    if (!result.term.success()) {
        try context.stderr.writeAll(result.stderr);
        return context.fail("cannot ask the lister of {s} which kosmoi build on others", .{context.config});
    }
    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        for (names) |name| {
            if (std.mem.eql(u8, line, name)) return true;
        }
    }
    return false;
}

/// Deletes the markers, so none is left from an earlier build.
fn deleteMarkers(context: Context, markers: []const u8) Error!void {
    std.Io.Dir.cwd().deleteTree(context.io, markers) catch |err|
        return context.fail("cannot delete {s}: {s}", .{ markers, @errorName(err) });
}

const testing = std.testing;

/// A kosmos with a variant, holding an app that writes nothing.
const test_frost =
    \\const kosm = @import("kosm");
    \\
    \\pub const Quiet = struct {
    \\    pub fn apply(self: Quiet, output: *kosm.Output) !void {
    \\        _ = self;
    \\        _ = output;
    \\    }
    \\};
    \\
    \\pub fn kosmos() struct { quiet: Quiet } {
    \\    return .{ .quiet = .{} };
    \\}
    \\
    \\pub fn iced() struct { quiet: Quiet } {
    \\    return .{ .quiet = .{} };
    \\}
    \\
;
/// A kosmos that lists, since its signature is fine, but does not compile.
const test_broken =
    \\pub fn kosmos() struct { quiet: @import("frost").Quiet } {
    \\    const size: u8 = "large";
    \\    _ = size;
    \\    return .{ .quiet = .{} };
    \\}
    \\
;

test "build compiles every kosmos and variant for apply, and names the one that does not compile" {
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
    try environ.put(interface.environment_variable, try arena.print("{d}", .{interface.version}));
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
    try @import("init.zig").init(context, try test_kosm.stub(arena, testing.io, tmp.dir, root));
    // The starting kosmos needs the real official packages, so it can't be built here.
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.zig", .data = test_frost });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/broken.zig", .data = test_broken });
    stdout.clearRetainingCapacity();

    try testing.expectError(error.Failed, build(context, null));
    try testing.expect(std.mem.find(u8, stdout.written(), "built frost\n") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), "built frost.iced\n") != null);
    try testing.expect(std.mem.find(u8, stderr.written(), "broken.zig:2:22: error: expected type 'u8'") != null);
    try testing.expect(std.mem.endsWith(u8, stderr.written(), "error: kosmos broken does not build; the others are built\n"));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "project/" ++ markers_path, .{}));

    for ([_][]const u8{ "-Dkosmos=frost", "-Dkosmos=frost.iced" }) |option| {
        const applied = try context.runZig(&.{ "build", option, "--summary", "all" });
        try testing.expect(applied.term.success());
        try testing.expect(std.mem.find(u8, applied.stderr, "compile exe kosmos debug native cached") != null);
    }

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosm.zon", .data = ".{ .build = .{ .only = .{\"frost.nope\"} } }\n" });
    stdout.clearRetainingCapacity();
    stderr.clearRetainingCapacity();
    try testing.expectError(error.Failed, build(context, null));
    try testing.expect(std.mem.find(u8, stdout.written(), "building") == null);
    try testing.expect(std.mem.endsWith(u8, stderr.written(), "kosm.zon: there is no kosmos 'frost.nope'; kosmoi of frost: frost, frost.iced\n"));

    // A misspelled name on the command line fails naming the closest, building nothing.
    stdout.clearRetainingCapacity();
    stderr.clearRetainingCapacity();
    try testing.expectError(error.Failed, build(context, .{ .only = &.{"frost.icde"} }));
    try testing.expect(std.mem.find(u8, stdout.written(), "building") == null);
    try testing.expectEqualStrings("error: there is no kosmos 'frost.icde'; did you mean 'frost.iced'?\n", stderr.written());

    // The command line replaces kosm.zon's choice, so its unknown name goes unread.
    stdout.clearRetainingCapacity();
    try build(context, .{ .except = &.{"broken"} });
    try testing.expect(std.mem.find(u8, stdout.written(), "built frost\nbuilt frost.iced\n") != null);

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosm.zon", .data = ".{ .build = .{ .only = .{\"frost.iced\"} } }\n" });
    stdout.clearRetainingCapacity();
    try build(context, null);
    try testing.expect(std.mem.endsWith(u8, stdout.written(), "building 1 kosmos: frost.iced\nbuilt frost.iced\n"));
}

const test_listed = [_]Listed{
    .{ .name = "frost", .origin = "kosmoi/frost.zig" },
    .{ .name = "frost.iced", .origin = "kosmoi/frost.zig" },
    .{ .name = "nord", .origin = "kosmoi/nord/" },
    .{ .name = "my_bar", .origin = "apps/my_bar/" },
    .{ .name = "kosm_probe", .origin = "package kosm_probe" },
};

fn testSelect(arena: std.mem.Allocator, selection: Settings.Selection) ![]const u8 {
    return switch (try select(arena, &test_listed, selection)) {
        .names => |names| std.mem.join(arena, " ", names),
        .unknown => |name| arena.print("unknown {s}", .{name}),
    };
}

test "all picks every kosmos in kosmoi/ with its variants, and none an app or package declares" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("frost frost.iced nord", try testSelect(arena.allocator(), .all));
}

test "only picks the named kosmoi wherever they are declared, a file name with its variants" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("frost frost.iced kosm_probe", try testSelect(arena.allocator(), .{ .only = &.{ "kosm_probe", "frost" } }));
    try testing.expectEqualStrings("frost.iced my_bar", try testSelect(arena.allocator(), .{ .only = &.{ "frost.iced", "my_bar", "frost.iced" } }));
}

test "except leaves out a file with its variants, or one variant alone" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("nord", try testSelect(arena.allocator(), .{ .except = &.{"frost"} }));
    try testing.expectEqualStrings("frost nord", try testSelect(arena.allocator(), .{ .except = &.{"frost.iced"} }));
}

test "a name that matches no kosmos is reported, even a variant of a known file" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("unknown catppuccin", try testSelect(arena.allocator(), .{ .only = &.{ "frost", "catppuccin" } }));
    try testing.expectEqualStrings("unknown frost.nope", try testSelect(arena.allocator(), .{ .except = &.{"frost.nope"} }));
    try testing.expectEqualStrings("unknown fro", try testSelect(arena.allocator(), .{ .only = &.{"fro"} }));
}
