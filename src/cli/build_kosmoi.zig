//! `kosm build`: compiles the runners of the kosmoi the command line or `kosm.zon` picks (every
//! kosmos in `kosmoi/` by default) in one `zig build`, so the next `kosm apply` of any of them
//! compiles nothing until a file changes.

const std = @import("std");
const Context = @import("Context.zig");
const Settings = @import("Settings.zig");
const interface = @import("kosm_interface");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dlist`.
const lister_path = "zig-out/bin/list";
/// Where `addConfigProject` marks each kosmos `-Dprebuild=` compiled, with an empty file.
const markers_path = "zig-out/prebuilt";
/// Where the kosmoi `Selection.all` means are declared, as the lister spells origins.
const kosmoi_directory = "kosmoi/";

/// Lists the config's kosmoi, compiles those `selection` picks (`kosm.zon`'s choice when null),
/// and names each one that does not compile after the others are built.
pub fn build(context: Context, selection: ?Settings.Selection) Error!void {
    const listed = try listKosmoi(context);
    const chosen = selection orelse try loadSelection(context);
    const names = switch (try select(context.arena, listed, chosen)) {
        .names => |names| names,
        .unknown => |name| return context.fail("{s} names '{s}', but there is no such kosmos; kosmoi: {s}", .{
            if (selection == null) try std.Io.Dir.path.join(context.arena, &.{ context.config, Settings.file_name }) else "kosm build",
            name,
            try joinNames(context.arena, listed),
        }),
    };
    if (names.len == 0) return context.stdout.writeAll("no kosmoi to build\n");
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
    if (failed.items.len == 0) return;
    try context.stdout.flush();
    return context.fail("{s} {s} {s} not build{s}", .{
        if (failed.items.len == 1) "kosmos" else "kosmoi",
        try std.mem.join(context.arena, ", ", failed.items),
        if (failed.items.len == 1) "does" else "do",
        if (failed.items.len == names.len) "" else "; the others are built",
    });
}

/// One kosmos or variant the lister reports.
const Listed = struct {
    /// As `kosm apply` spells it: "frost" or "frost.iced".
    name: []const u8,
    /// Where it is declared: "kosmoi/frost.zig", "apps/my_bar/" or "package kosm_probe".
    origin: []const u8,
};

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
        for (listed) |kosmos| {
            if (matches(name, kosmos.name)) break;
        } else return .{ .unknown = name };
    }
    var names: std.ArrayList([]const u8) = .empty;
    for (listed) |kosmos| {
        const named = for (given) |name| {
            if (matches(name, kosmos.name)) break true;
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

/// Whether `name` picks kosmos `kosmos_name`: a file ("frost") or group ("frost.cold") picks
/// it and every kosmos in it, a variant ("frost.iced") only itself, as `kosm list` matches.
fn matches(name: []const u8, kosmos_name: []const u8) bool {
    if (!std.mem.startsWith(u8, kosmos_name, name)) return false;
    return kosmos_name.len == name.len or kosmos_name[name.len] == '.';
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

/// Every kosmos and variant in the config, from the config's listing program.
fn listKosmoi(context: Context) Error![]const Listed {
    if (!try context.runBuild(&.{ "build", "-Dlist" }))
        return context.fail("the config project {s} does not build, so its kosmoi cannot be listed", .{context.config});
    var environ: std.process.Environ.Map = if (context.environ_map) |map| try map.clone(context.arena) else .init(context.arena);
    try environ.put(interface.completions_variable, "1");
    var listing = context;
    listing.environ_map = &environ;
    const result = try listing.run(&.{try std.Io.Dir.path.join(context.arena, &.{ context.config, lister_path })});
    if (!result.term.success()) {
        try context.stderr.writeAll(result.stderr);
        return context.fail("cannot list the kosmoi of {s}", .{context.config});
    }
    return parseListing(context.arena, result.stdout);
}

/// The lister's completion lines, `name<TAB>origin` each.
fn parseListing(arena: std.mem.Allocator, listing: []const u8) std.mem.Allocator.Error![]const Listed {
    var listed: std.ArrayList(Listed) = .empty;
    var lines = std.mem.tokenizeScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        try listed.append(arena, .{ .name = fields.first(), .origin = fields.rest() });
    }
    return listed.items;
}

/// The names of `listed`, comma-separated, or "none".
fn joinNames(arena: std.mem.Allocator, listed: []const Listed) std.mem.Allocator.Error![]const u8 {
    if (listed.len == 0) return "none";
    var names: std.ArrayList([]const u8) = .empty;
    for (listed) |kosmos| try names.append(arena, kosmos.name);
    return std.mem.join(arena, ", ", names.items);
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
    try testing.expect(std.mem.endsWith(u8, stderr.written(), "kosm.zon names 'frost.nope', but there is no such kosmos; kosmoi: broken, frost, frost.iced\n"));

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
