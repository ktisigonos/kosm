//! Script kosmoi for `kosm apply` and `kosm build`: a file `kosmoi/<name>.<extension>` that a
//! frontend reads, run by the one runner every script shares. The runner is rebuilt only when Zig
//! code it is built from (the config's, its local packages' or kosm's own) changed since it was
//! last built, never on a script edit.

const std = @import("std");
const Context = @import("Context.zig");
const interface = @import("kosm_interface");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dscripts`.
pub const runner_path = "zig-out/bin/scripts";
/// Where the build of the runner puts each frontend's editor file, which kosm copies into the
/// config's root where it is missing.
const editor_directory = "zig-out/editor";
/// Written when a build of the runner starts and kept once it succeeded; Zig code newer than
/// it means the runner is stale.
const stamp_path = "zig-out/scripts.built";
/// Where script kosmoi live, in the config's root.
const kosmoi_directory = "kosmoi";
/// The config's own files and folders the runner is built from.
const config_files = [_][]const u8{ "build.zig", "build.zig.zon" };
const config_folders = [_][]const u8{ "kosmoi", "apps", "adapters" };
/// Kosm's own files and folders in its sources.
const source_files = [_][]const u8{ "build.zig", "build.zig.zon" };
const source_folders = [_][]const u8{ "src", "build" };
/// Folders a walk never enters: build output, fetched packages, caches.
const skipped_folders = [_][]const u8{ "zig-out", "zig-pkg", ".zig-cache" };

/// Whether kosmos `name` is run by the runner of scripts: "minimal" (or "minimal.x", which the
/// runner refuses) when `kosmoi/` holds a file named after its part before the first dot,
/// "personal.nord" also when the kosmos folder `kosmoi/personal/` holds one named `nord`, and
/// every name starting with "frost" when `kosmoi/frost/` holds a `root` script, whose folder may
/// hold Zig variants too, which that runner tells apart. Scripts have any extension but Zig's
/// and its manifests'.
pub fn isScript(context: Context, name: []const u8) Error!bool {
    var segments = std.mem.splitScalar(u8, name, '.');
    const first = segments.first();
    if (try holdsScript(context, kosmoi_directory, first)) return true;
    const folder = try std.Io.Dir.path.join(context.arena, &.{ kosmoi_directory, first });
    if (try holdsScript(context, folder, script_root)) return true;
    const variant = segments.next() orelse return false;
    return holdsScript(context, folder, variant);
}

/// The file name a script giving its folder's kosmos has before its extension.
const script_root = "root";

/// Whether the config's folder `folder` holds a script named `name`, or any script when `name`
/// is empty.
fn holdsScript(context: Context, folder: []const u8, name: []const u8) Error!bool {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, folder });
    var dir = std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch return false;
    defer dir.close(context.io);
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) })) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (std.mem.startsWith(u8, entry.name, ".") or isZig(entry.name)) continue;
        const dot = std.mem.findScalar(u8, entry.name, '.') orelse continue;
        if (name.len == 0 or std.mem.eql(u8, entry.name[0..dot], name)) return true;
    }
    return false;
}

/// Whether `file_name` is Zig source or a Zig manifest, never a script.
fn isZig(file_name: []const u8) bool {
    return std.mem.endsWith(u8, file_name, ".zig") or std.mem.endsWith(u8, file_name, ".zon");
}

/// What the built runner reports for completing script `name`'s arguments: `kind<TAB>...`
/// lines, a `base` line first when it builds on a Zig kosmos. Null when the script cannot be
/// read; applying it then says why.
pub fn report(context: Context, name: []const u8) Error!?[]const u8 {
    var environ: std.process.Environ.Map = if (context.environ_map) |map| try map.clone(context.arena) else .init(context.arena);
    try environ.put(interface.completions_variable, "1");
    var asking = context;
    asking.environ_map = &environ;
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    // `--diff` goes along so that a runner too old to report still writes nothing.
    const result = try asking.run(&.{ runner, name, "--diff" });
    return if (result.term.success()) result.stdout else null;
}

/// Whether the Zig kosmos whose built runner is `kosmos_runner` builds on another kosmos, which
/// only the runner of scripts can build, as that runner says. A runner that cannot answer is
/// left to report why when it applies.
pub fn buildsOnKosmoi(context: Context, kosmos_runner: []const u8) Error!bool {
    var environ: std.process.Environ.Map = if (context.environ_map) |map| try map.clone(context.arena) else .init(context.arena);
    try environ.put(interface.runner_variable, "1");
    var asking = context;
    asking.environ_map = &environ;
    // `--diff` goes along so that a runner too old to answer still writes nothing.
    const result = try asking.run(&.{ kosmos_runner, "--diff" });
    if (!result.term.success()) return false;
    return std.mem.eql(u8, std.mem.trim(u8, result.stdout, "\n"), interface.script_runner);
}

/// The Zig kosmos script `name` builds on, through any scripts below it, as its built runner
/// reports it; null when it builds on none or cannot be read.
pub fn baseOf(context: Context, name: []const u8) Error!?[]const u8 {
    const reported = try report(context, name) orelse return null;
    var lines = std.mem.splitScalar(u8, reported, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        if (std.mem.eql(u8, fields.first(), "base")) return fields.rest();
    }
    return null;
}

/// Whether `kosmoi/` or a kosmos folder in it holds any script kosmos.
pub fn any(context: Context) Error!bool {
    if (try holdsScript(context, kosmoi_directory, "")) return true;
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, kosmoi_directory });
    var dir = std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch return false;
    defer dir.close(context.io);
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) })) |entry| {
        if (entry.kind != .directory or std.mem.startsWith(u8, entry.name, ".")) continue;
        if (try holdsScript(context, try std.Io.Dir.path.join(context.arena, &.{ kosmoi_directory, entry.name }), "")) return true;
    }
    return false;
}

/// Builds the runner when it is missing or stale; returns whether it is ready.
pub fn prepare(context: Context) Error!bool {
    if (!try isStale(context)) return true;
    return build(context);
}

/// Builds the runner, whatever its state; returns whether it succeeded.
pub fn build(context: Context) Error!bool {
    const stamp = try std.Io.Dir.path.join(context.arena, &.{ context.config, stamp_path });
    // Stamped before building, so a file edited during the build is newer than the stamp.
    std.Io.Dir.cwd().createDirPath(context.io, std.Io.Dir.path.dirname(stamp).?) catch |err|
        return context.fail("cannot create {s}: {s}", .{ std.Io.Dir.path.dirname(stamp).?, @errorName(err) });
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = stamp, .data = "" }) catch |err|
        return context.fail("cannot write {s}: {s}", .{ stamp, @errorName(err) });
    if (try context.runBuild(&.{ "build", "-Dscripts" })) {
        _ = try createEditorFiles(context);
        return true;
    }
    std.Io.Dir.cwd().deleteFile(context.io, stamp) catch {};
    return false;
}

/// Builds the runner when `kosmoi/` holds a script, so its completion files are current; returns
/// false only when that build failed.
pub fn buildIfAny(context: Context) Error!bool {
    if (!try any(context)) return true;
    try context.stdout.writeAll("building the script runner\n");
    return build(context);
}

/// Copies each editor file the last build of the runner gave (`.luarc.json`) into the config's
/// root where the config has none, printing each one created; returns whether it created any.
/// Files the config has already are never touched, so a user's edits stay.
pub fn createEditorFiles(context: Context) Error!bool {
    const source = try std.Io.Dir.path.join(context.arena, &.{ context.config, editor_directory });
    var dir = std.Io.Dir.cwd().openDir(context.io, source, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return context.fail("cannot read {s}: {s}", .{ source, @errorName(err) }),
    };
    defer dir.close(context.io);
    var created = false;
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ source, @errorName(err) })) |entry| {
        if (entry.kind != .file) continue;
        const contents = dir.readFileAlloc(context.io, entry.name, context.arena, .limited(editor_file_limit)) catch |err|
            return context.fail("cannot read {s}/{s}: {s}", .{ source, entry.name, @errorName(err) });
        const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, entry.name });
        std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = path, .data = contents, .flags = .{ .exclusive = true } }) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            else => return context.fail("cannot create {s}: {s}", .{ path, @errorName(err) }),
        };
        try context.stdout.print("created {s}\n", .{entry.name});
        created = true;
    }
    return created;
}

/// Far beyond any editor file; a guard against copying something huge.
const editor_file_limit = 1024 * 1024;

/// Whether the runner is missing, or any Zig file it is built from is newer than its stamp. What
/// cannot be read counts as changed: a needless build is safe, a stale runner is not.
fn isStale(context: Context) Error!bool {
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    std.Io.Dir.cwd().access(context.io, runner, .{}) catch return true;
    const stamp_file = try std.Io.Dir.path.join(context.arena, &.{ context.config, stamp_path });
    const stamp = std.Io.Dir.cwd().statFile(context.io, stamp_file, .{}) catch return true;
    if (try anyNewer(context, context.config, &config_files, &config_folders, stamp.mtime)) return true;
    const sources = context.sources orelse return false;
    return anyNewer(context, sources.directory, &source_files, &source_folders, stamp.mtime);
}

/// Whether one of `files` in `root`, or a Zig file or manifest anywhere in its `folders`, was
/// changed after `since`.
fn anyNewer(context: Context, root: []const u8, files: []const []const u8, folders: []const []const u8, since: std.Io.Timestamp) Error!bool {
    var dir = std.Io.Dir.cwd().openDir(context.io, root, .{}) catch return true;
    defer dir.close(context.io);
    for (files) |file| {
        const stat = dir.statFile(context.io, file, .{}) catch continue;
        if (stat.mtime.compare(.gt, since)) return true;
    }
    for (folders) |folder| {
        var tree = dir.openDir(context.io, folder, .{ .iterate = true }) catch continue;
        defer tree.close(context.io);
        var walker = tree.walkSelectively(context.arena) catch return true;
        defer walker.deinit();
        while (walker.next(context.io) catch return true) |entry| {
            if (std.mem.startsWith(u8, entry.basename, ".")) continue;
            switch (entry.kind) {
                .directory => if (!isSkipped(entry.basename)) walker.enter(context.io, entry) catch return true,
                .file, .sym_link => if (std.mem.endsWith(u8, entry.basename, ".zig") or std.mem.endsWith(u8, entry.basename, ".zon")) {
                    const stat = entry.dir.statFile(context.io, entry.basename, .{}) catch return true;
                    if (stat.mtime.compare(.gt, since)) return true;
                },
                else => {},
            }
        }
    }
    return false;
}

fn isSkipped(folder: []const u8) bool {
    for (skipped_folders) |skipped| {
        if (std.mem.eql(u8, folder, skipped)) return true;
    }
    return false;
}

const testing = std.testing;

/// A frontend reading one setting per line: `base frost`, `param size=12`,
/// `theme palette.black=#000000` or `set kitty.fonts.font_size=9`.
const test_frontend =
    \\const std = @import("std");
    \\const kosm = @import("kosm");
    \\
    \\pub const frontend: kosm.Frontend = .{
    \\    .name = "lines",
    \\    .extensions = &.{".kosmos"},
    \\    .load = load,
    \\    .complete = complete,
    \\    .editor_file = .{ .path = ".lines.json", .contents = "{}\n" },
    \\};
    \\
    \\fn complete(arena: std.mem.Allocator, completion: kosm.Frontend.Completion) std.mem.Allocator.Error![]const kosm.Frontend.Completion.File {
    \\    var text: std.Io.Writer.Allocating = .init(arena);
    \\    for (completion.kosmoi) |kosmos| text.writer.print("kosmos {s} {s}\n", .{ kosmos.name, kosmos.tree }) catch return error.OutOfMemory;
    \\    const theme = completion.find(completion.theme).?;
    \\    text.writer.print("theme {s}: {s}\n", .{ theme.name, theme.fields[0].doc.? }) catch return error.OutOfMemory;
    \\    return arena.dupe(kosm.Frontend.Completion.File, &.{.{ .path = "types/all.txt", .contents = text.written() }});
    \\}
    \\
    \\fn load(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.Script {
    \\    var script: kosm.Frontend.Script = .{};
    \\    var params: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    var theme: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    var overrides: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    var number: usize = 0;
    \\    while (lines.next()) |line| {
    \\        number += 1;
    \\        if (line.len == 0) continue;
    \\        const space = std.mem.findScalar(u8, line, ' ') orelse return context.fail("{s}: expected a keyword and a value", .{try context.at(number)});
    \\        const rest = line[space + 1 ..];
    \\        if (std.mem.eql(u8, line[0..space], "base")) {
    \\            script.base = rest;
    \\            continue;
    \\        }
    \\        const list = if (std.mem.eql(u8, line[0..space], "param")) &params else if (std.mem.eql(u8, line[0..space], "theme")) &theme else &overrides;
    \\        const equals = std.mem.findScalar(u8, rest, '=') orelse return context.fail("{s}: expected path=value", .{try context.at(number)});
    \\        try list.append(context.arena, try nested(context.arena, rest[0..equals], .{ .value = .{ .text = rest[equals + 1 ..] }, .origin = try context.at(number) }));
    \\    }
    \\    if (params.items.len != 0) script.params = .{ .value = .{ .table = params.items } };
    \\    if (theme.items.len != 0) script.theme = .{ .value = .{ .table = theme.items } };
    \\    if (overrides.items.len != 0) script.overrides = .{ .value = .{ .table = overrides.items } };
    \\    return script;
    \\}
    \\
    \\fn nested(arena: std.mem.Allocator, path: []const u8, leaf: kosm.Loose) !kosm.Loose.Entry {
    \\    const dot = std.mem.findScalar(u8, path, '.') orelse return .{ .key = path, .value = leaf };
    \\    const inner = try arena.dupe(kosm.Loose.Entry, &.{try nested(arena, path[dot + 1 ..], leaf)});
    \\    return .{ .key = path[0..dot], .value = .{ .value = .{ .table = inner } } };
    \\}
    \\
;

/// A Zig kosmos wearing the stub kitty, its font size a parameter.
const test_frost =
    \\const kosm = @import("kosm");
    \\const kitty = @import("kosm_kitty");
    \\
    \\pub fn kosmos(params: struct { size: u32 = 10 }) struct { kitty: kitty.App } {
    \\    return .{ .kitty = .{ .fonts = .{ .font_size = params.size } } };
    \\}
    \\
;

/// A kosmos folder holding a Zig kosmos, its variant `iced`, `melted` building on the script
/// variant `snow.nord`, and `circle` building on a script building on it.
const test_snow =
    \\const kosm = @import("kosm");
    \\const kitty = @import("kosm_kitty");
    \\
    \\pub const Tree = struct { kitty: kitty.App };
    \\
    \\pub fn kosmos() Tree {
    \\    return .{ .kitty = .{ .fonts = .{ .font_size = 20 } } };
    \\}
    \\
    \\pub fn iced() Tree {
    \\    return kosmos();
    \\}
    \\
    \\pub fn melted(params: struct { on: kosm.Kosmos(Tree) = .{ .name = "snow.nord" } }) !Tree {
    \\    var tree = try params.on.tree();
    \\    tree.kitty.fonts.font_size = tree.kitty.fonts.font_size.? * 2;
    \\    return tree;
    \\}
    \\
    \\pub fn circle(params: struct { on: kosm.Kosmos(Tree) = .{ .name = "snow.thaw" } }) !Tree {
    \\    return params.on.tree();
    \\}
    \\
;

/// The Zig variant `iced` of the script kosmos `hail`, building on it.
const test_hail =
    \\const kosm = @import("kosm");
    \\const snow = @import("snow");
    \\
    \\pub fn iced(params: struct { on: kosm.Kosmos(snow.Tree) = .{ .name = "hail" } }) !snow.Tree {
    \\    var tree = try params.on.tree();
    \\    tree.kitty.fonts.font_size = tree.kitty.fonts.font_size.? + 1;
    \\    return tree;
    \\}
    \\
;

/// Runs script kosmos `name` with `--diff`; returns stdout, or stderr when it failed.
fn testDiff(context: Context, name: []const u8) ![]const u8 {
    return testDiffWith(context, name, &.{});
}

/// `testDiff` with `arguments` before `--diff`.
fn testDiffWith(context: Context, name: []const u8, arguments: []const []const u8) ![]const u8 {
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    const applied = try context.run(try std.mem.concat(context.arena, []const u8, &.{ &.{ runner, name }, arguments, &.{ "--diff", "--config", context.config } }));
    return if (applied.term.success()) applied.stdout else applied.stderr;
}

test "script kosmoi apply on a Zig kosmos, on each other and on none, and a script edit builds nothing" {
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
    // The starting kosmos needs the real official packages, and the runner holds every kosmos.
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.zig", .data = test_frost });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/lines.zig", .data = test_frontend });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/on.kosmos", .data = "base frost\nparam size=12\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/over.kosmos", .data = "base on\nset kitty.fonts.font_size=14\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/alone.kosmos", .data = "theme palette.black=#000000\ntheme palette.white=#ffffff\ntheme mode=dark\nset kitty.fonts.font_size=9\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/bad.kosmos", .data = "base frost\nset kitty.fonts.font_size=big\n" });
    try tmp.dir.createDirPath(testing.io, "project/kosmoi/snow");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/snow/root.zig", .data = test_snow });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/snow/nord.kosmos", .data = "base snow\nset kitty.fonts.font_size=21\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/snow/iced.kosmos", .data = "base snow\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/snow/thaw.kosmos", .data = "base snow.circle\n" });
    try tmp.dir.createDirPath(testing.io, "project/kosmoi/hail");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/hail/root.kosmos", .data = "base snow\nset kitty.fonts.font_size=30\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/hail/root.zig", .data = test_hail });
    try tmp.dir.createDirPath(testing.io, "project/kosmoi/bare");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/bare/root.kosmos", .data = "base frost\n" });

    try testing.expect(try isScript(context, "on"));
    try testing.expect(!try isScript(context, "frost"));
    try testing.expect(try isScript(context, "snow.nord"));
    try testing.expect(!try isScript(context, "snow"));
    try testing.expect(!try isScript(context, "snow.root"));
    try testing.expect(try isScript(context, "hail"));
    try testing.expect(try isScript(context, "hail.iced"));
    stdout.clearRetainingCapacity();
    try testing.expect(try prepare(context));
    // The build gave the frontend's completion files and its editor file, created only once.
    try testing.expectEqualStrings("created .lines.json\n", stdout.written());
    const types = try tmp.dir.readFileAlloc(testing.io, "project/zig-out/completions/lines/types/all.txt", arena, .limited(1024 * 1024));
    try testing.expect(std.mem.find(u8, types, "kosmos frost frost.kosmos.Tree\n") != null);
    try testing.expect(std.mem.find(u8, types, "theme kosm.Theme.Input: Black, white and any of the wheel's hues; missing hues are mixed from their neighbours.\n") != null);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/.lines.json", .data = "{ \"mine\": 1 }\n" });
    try testing.expect(!try createEditorFiles(context));
    try testing.expect(std.mem.find(u8, try testDiff(context, "on"), "+font_size 12\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "over"), "+font_size 14\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "alone"), "+font_size 9\n") != null);
    try testing.expectEqualStrings("error: kosmos 'bad': kosmoi/bad.kosmos:2: kitty.fonts.font_size: expected an integer that fits u32, got 'big'\n", try testDiff(context, "bad"));
    // A script in a kosmos' folder is its variant, and may not share a Zig variant's name.
    try testing.expect(std.mem.find(u8, try testDiff(context, "snow.nord"), "+font_size 21\n") != null);
    try testing.expectEqualStrings("error: kosmos 'snow.iced': 'snow.iced' names both kosmoi/snow/iced.kosmos and a kosmos of kosmoi/snow/; rename one\n", try testDiff(context, "snow.iced"));
    // A folder's root script gives its kosmos, with Zig variants building on it beside it, and
    // a folder holding only scripts needs no root.zig.
    try testing.expect(std.mem.find(u8, try testDiff(context, "hail"), "+font_size 30\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "hail.iced"), "+font_size 31\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "bare"), "+font_size 10\n") != null);

    // A Zig kosmos builds on a script's tree, its own values on top; kosmoi building on each
    // other in a circle, on a tree of another type or on nothing fail naming them.
    try testing.expect(std.mem.find(u8, try testDiff(context, "snow.melted"), "+font_size 42\n") != null);
    try testing.expectEqualStrings("error: kosmos 'snow.circle': Params.on: kosmos 'snow.thaw': the kosmoi build on each other in a circle: snow.circle -> snow.thaw -> snow.circle\n", try testDiff(context, "snow.circle"));
    try testing.expect(std.mem.startsWith(u8, try testDiffWith(context, "snow.melted", &.{ "--on", "frost" }), "error: kosmos 'snow.melted': Params.on: kosmos 'frost': 'frost' gives a "));
    try testing.expectEqualStrings("error: kosmos 'snow.melted': Params.on: kosmos 'alone': kosmoi/alone.kosmos builds on no kosmos, so its tree is not a root.Tree; build it on a kosmos giving one\n", try testDiffWith(context, "snow.melted", &.{ "--on", "alone" }));
    try testing.expect(std.mem.startsWith(u8, try testDiffWith(context, "snow.melted", &.{ "--on", "missing" }), "error: kosmos 'snow.melted': Params.on: kosmos 'missing': there is no such kosmos; Zig kosmoi: "));
    // Its own runner sends it to the runner of scripts.
    try testing.expect(try context.runBuild(&.{ "build", "-Dkosmos=snow.melted" }));
    const kosmos_runner = try std.Io.Dir.path.join(arena, &.{ context.config, "zig-out/bin/kosmos" });
    try testing.expect(try buildsOnKosmoi(context, kosmos_runner));
    try testing.expect(try context.runBuild(&.{ "build", "-Dkosmos=snow" }));
    try testing.expect(!try buildsOnKosmoi(context, kosmos_runner));

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/on.kosmos", .data = "base frost\nparam size=13\n" });
    try testing.expect(!try isStale(context));
    try testing.expect(std.mem.find(u8, try testDiff(context, "on"), "+font_size 13\n") != null);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.zig", .data = test_frost });
    try testing.expect(try isStale(context));

    // The runner reports what a script builds on and what completes its arguments.
    try testing.expectEqualStrings("frost", (try baseOf(context, "over")).?);
    try testing.expectEqual(null, try baseOf(context, "alone"));
    try testing.expect(std.mem.find(u8, (try report(context, "on")).?, "param\t--size\t") != null);
    try testing.expect(std.mem.find(u8, (try report(context, "alone")).?, "set\tkitty.fonts.font_size\t") != null);
    try testing.expectEqual(null, try report(context, "missing"));

    // `kosm list` shows scripts, and `kosm build` takes a script's name.
    stdout.clearRetainingCapacity();
    try @import("list.zig").list(context, null);
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/on.kosmos\n") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), "  snow.nord ") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/snow/nord.kosmos\n") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), "  hail ") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/hail/root.kosmos\n  hail.iced ") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/bare/root.kosmos\n") != null);
    stdout.clearRetainingCapacity();
    try @import("build_kosmoi.zig").build(context, .{ .only = &.{"on"} });
    try testing.expectEqualStrings("building the script runner\nbuilt the script runner\n", stdout.written());
    // A Zig kosmos building on another is applied by the runner of scripts, built along.
    stdout.clearRetainingCapacity();
    try @import("build_kosmoi.zig").build(context, .{ .only = &.{"snow.melted"} });
    try testing.expectEqualStrings("building the script runner\nbuilt the script runner\nbuilding 1 kosmos: snow.melted\nbuilt snow.melted\n", stdout.written());

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.kosmos", .data = "" });
    stderr.clearRetainingCapacity();
    try testing.expect(!try build(context));
    try testing.expect(std.mem.find(u8, stderr.written(), "'frost' names both the script kosmoi/frost.kosmos and kosmoi/frost.zig") != null);
}
