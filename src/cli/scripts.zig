//! Script kosmoi for `kosm apply` and `kosm build`: a file `kosmoi/<name>.<extension>` that a
//! frontend reads, run by the one runner every script shares. The runner is rebuilt only when Zig
//! code it is built from (the config's, its local packages' or kosm's own) changed since it was
//! last built, never on a script edit.

const std = @import("std");
const Context = @import("Context.zig");
const interface = @import("kosm_interface");
const manifest = @import("manifest.zig");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dscripts`.
pub const runner_path = "zig-out/bin/scripts";
/// Where the build of the runner puts each frontend's editor file, which kosm copies into the
/// config's root where it is missing.
const editor_directory = "zig-out/editor";
/// Written when a build of the runner starts and kept once it succeeded; Zig code (or an app's
/// or a kosmos' root script) newer than it means the runner is stale.
const stamp_path = "zig-out/scripts.built";
/// Where script kosmoi live, in the config's root.
const kosmoi_directory = "kosmoi";
/// The config's own files and folders the runner is built from.
const config_files = [_][]const u8{ "build.zig", "build.zig.zon" };
const config_folders = [_][]const u8{ "kosmoi", "apps", "adapters", "frontends", "colors" };
/// The config's folders whose every file counts: an app's, adapter's, frontend's or modifier's
/// script may change what it declares, which only a build sees. A build finding the declaration
/// unchanged compiles nothing.
const script_app_folders = [_][]const u8{ "apps", "adapters", "frontends", "colors" };
/// Kosm's own files and folders in its sources.
const source_files = [_][]const u8{ "build.zig", "build.zig.zon" };
const source_folders = [_][]const u8{ "src", "build" };
/// Folders a walk never enters: build output, fetched packages, caches.
const skipped_folders = [_][]const u8{ "zig-out", "zig-pkg", ".zig-cache" };

/// Whether kosmos `name` is run by the runner of scripts: "minimal" (or "minimal.x", which the
/// runner refuses) when `kosmoi/` holds a file named after its part before the first dot,
/// "personal.nord" also when the kosmos folder `kosmoi/personal/` holds one named `nord`, and
/// every name starting with "frost" when `kosmoi/frost/` holds a `root` script, whose folder may
/// hold Zig variants too, which that runner tells apart, and every name starting with "kosm_frost"
/// when that package of the config has a root script, which may give a kosmos. Scripts have any
/// extension but Zig's and its manifests'.
pub fn isScript(context: Context, name: []const u8) Error!bool {
    var segments = std.mem.splitScalar(u8, name, '.');
    const first = segments.first();
    if (try holdsScript(context, kosmoi_directory, first)) return true;
    for (try scriptPackages(context)) |package| {
        if (std.mem.eql(u8, package, first)) return true;
    }
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

/// The packages in the config's `build.zig.zon` whose fetched folder (or `.path`) holds a root
/// script and no `root.zig`. Whether a script gives a kosmos, an app or anything else only its
/// frontend tells, so the runner of scripts sorts them out. A package not fetched yet is not
/// listed.
fn scriptPackages(context: Context) Error![]const []const u8 {
    const manifest_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, "build.zig.zon" });
    const source = std.Io.Dir.cwd().readFileAllocOptions(context.io, manifest_path, context.arena, .limited(manifest_limit), .of(u8), 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // Building the config says what is wrong with a folder that is no config project.
        error.FileNotFound => return &.{},
        else => return context.fail("cannot read {s}: {s}", .{ manifest_path, @errorName(err) }),
    };
    const dependencies = manifest.dependencies(context.arena, source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidManifest => return context.fail("{s} is not a valid manifest; zig build says why", .{manifest_path}),
    };
    var found: std.ArrayList([]const u8) = .empty;
    for (dependencies) |dependency| {
        const folder = if (dependency.path) |path|
            try std.Io.Dir.path.resolveAlloc(context.arena, &.{ context.config, path })
        else if (dependency.hash) |hash|
            try std.Io.Dir.path.join(context.arena, &.{ context.config, "zig-pkg", hash })
        else
            continue;
        if (try isScriptRoot(context, folder)) try found.append(context.arena, dependency.name);
    }
    return found.items;
}

/// A manifest is a few hundred bytes; this only guards against reading something huge.
const manifest_limit = 1024 * 1024;

/// Whether `folder` holds a root script and no `root.zig`; a missing folder holds none.
fn isScriptRoot(context: Context, folder: []const u8) Error!bool {
    var dir = std.Io.Dir.cwd().openDir(context.io, folder, .{ .iterate = true }) catch return false;
    defer dir.close(context.io);
    if (dir.access(context.io, "root.zig", .{})) |_| return false else |_| {}
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return context.fail("cannot read {s}: {s}", .{ folder, @errorName(err) })) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (isZig(entry.name) or !std.mem.startsWith(u8, entry.name, script_root ++ ".")) continue;
        return true;
    }
    return false;
}

/// Whether `file_name` is a script: not hidden, with an extension other than Zig's and its
/// manifests'.
fn isScriptName(file_name: []const u8) bool {
    return !std.mem.startsWith(u8, file_name, ".") and !isZig(file_name) and std.mem.findScalar(u8, file_name, '.') != null;
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

/// Whether `kosmoi/` or a kosmos folder in it holds any script kosmos, or a package of the
/// config has a root script, which may give one.
pub fn any(context: Context) Error!bool {
    if (try holdsScript(context, kosmoi_directory, "")) return true;
    if ((try scriptPackages(context)).len != 0) return true;
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
pub fn isStale(context: Context) Error!bool {
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, runner_path });
    std.Io.Dir.cwd().access(context.io, runner, .{}) catch return true;
    const stamp_file = try std.Io.Dir.path.join(context.arena, &.{ context.config, stamp_path });
    const stamp = std.Io.Dir.cwd().statFile(context.io, stamp_file, .{}) catch return true;
    if (try anyNewer(context, context.config, &config_files, &config_folders, &script_app_folders, stamp.mtime)) return true;
    if (try anyKosmosRootNewer(context, stamp.mtime)) return true;
    const sources = context.sources orelse return false;
    return anyNewer(context, sources.directory, &source_files, &source_folders, &.{}, stamp.mtime);
}

/// Whether one of `files` in `root`, a Zig file or manifest anywhere in its `folders`, or any
/// file in its `every_file_folders`, was changed after `since`.
fn anyNewer(context: Context, root: []const u8, files: []const []const u8, folders: []const []const u8, every_file_folders: []const []const u8, since: std.Io.Timestamp) Error!bool {
    var dir = std.Io.Dir.cwd().openDir(context.io, root, .{}) catch return true;
    defer dir.close(context.io);
    for (files) |file| {
        const stat = dir.statFile(context.io, file, .{}) catch continue;
        if (stat.mtime.compare(.gt, since)) return true;
    }
    for (folders) |folder| {
        const every_file = for (every_file_folders) |counted| {
            if (std.mem.eql(u8, counted, folder)) break true;
        } else false;
        var tree = dir.openDir(context.io, folder, .{ .iterate = true }) catch continue;
        defer tree.close(context.io);
        var walker = tree.walkSelectively(context.arena) catch return true;
        defer walker.deinit();
        while (walker.next(context.io) catch return true) |entry| {
            if (std.mem.startsWith(u8, entry.basename, ".")) continue;
            switch (entry.kind) {
                .directory => if (!isSkipped(entry.basename)) walker.enter(context.io, entry) catch return true,
                .file, .sym_link => if (every_file or std.mem.endsWith(u8, entry.basename, ".zig") or std.mem.endsWith(u8, entry.basename, ".zon")) {
                    const stat = entry.dir.statFile(context.io, entry.basename, .{}) catch return true;
                    if (stat.mtime.compare(.gt, since)) return true;
                },
                else => {},
            }
        }
    }
    return false;
}

/// Whether a script in `kosmoi/` or a kosmos folder's root script was changed after `since`: it
/// may change the values it exports, which only a build sees. Other scripts in a kosmos folder
/// are variants, read only when kosm runs.
fn anyKosmosRootNewer(context: Context, since: std.Io.Timestamp) Error!bool {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, kosmoi_directory });
    var dir = std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return true,
    };
    defer dir.close(context.io);
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch return true) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        switch (entry.kind) {
            .file, .sym_link => if (isScriptName(entry.name)) {
                const stat = dir.statFile(context.io, entry.name, .{}) catch return true;
                if (stat.mtime.compare(.gt, since)) return true;
            },
            .directory => {
                var folder = dir.openDir(context.io, entry.name, .{ .iterate = true }) catch return true;
                defer folder.close(context.io);
                var files = folder.iterate();
                while (files.next(context.io) catch return true) |file| {
                    if (file.kind != .file and file.kind != .sym_link) continue;
                    if (!isScriptName(file.name) or !std.mem.startsWith(u8, file.name, script_root ++ ".")) continue;
                    const stat = folder.statFile(context.io, file.name, .{}) catch return true;
                    if (stat.mtime.compare(.gt, since)) return true;
                }
            },
            else => {},
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
    \\    .variants = variants,
    \\    .complete = complete,
    \\    .editor_file = .{ .path = ".lines.json", .contents = "{}\n" },
    \\    .declare = declare,
    \\    .declare_adapter = declareAdapter,
    \\    .declare_frontend = declareFrontend,
    \\    .call = call,
    \\    .counts_from = 1,
    \\};
    \\
    \\const integer_type: kosm.Frontend.Declaration.Type = .integer;
    \\
    \\/// `doc <text>` documents the next field or, before the first, the app; `field <name>
    \\/// integer [default]` or `field <name> optional-integer` declares one; `from` gives that
    \\/// function, and `apply <file>` or `edit <files> <path> <text>` gives `apply`.
    \\fn declare(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.Declaration {
    \\    var fields: std.ArrayList(kosm.Frontend.Declaration.Field) = .empty;
    \\    var functions: std.ArrayList([]const u8) = .empty;
    \\    var app_doc: ?[]const u8 = null;
    \\    var doc: ?[]const u8 = null;
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    var number: usize = 0;
    \\    while (lines.next()) |line| {
    \\        number += 1;
    \\        if (std.mem.startsWith(u8, line, "doc ")) {
    \\            if (fields.items.len == 0 and app_doc == null) app_doc = line[4..] else doc = line[4..];
    \\        } else if (std.mem.startsWith(u8, line, "field ")) {
    \\            var words = std.mem.splitScalar(u8, line["field ".len..], ' ');
    \\            const name = words.first();
    \\            const kind = words.next() orelse return context.fail("{s}: a field needs a type", .{try context.at(number)});
    \\            const field_type: kosm.Frontend.Declaration.Type = if (std.mem.eql(u8, kind, "integer")) .integer else .{ .optional = &integer_type };
    \\            const default: ?kosm.Loose = if (words.next()) |text| .{ .value = .{ .integer = std.fmt.parseInt(i64, text, 10) catch return context.fail("{s}: bad default", .{try context.at(number)}) } } else null;
    \\            try fields.append(context.arena, .{ .name = name, .doc = doc, .type = field_type, .default = default, .line = number });
    \\            doc = null;
    \\        } else if (std.mem.eql(u8, line, "from") or std.mem.startsWith(u8, line, "from ")) {
    \\            try functions.append(context.arena, "from");
    \\        } else if (std.mem.startsWith(u8, line, "apply ") or std.mem.startsWith(u8, line, "edit ")) {
    \\            try functions.append(context.arena, "apply");
    \\        }
    \\    }
    \\    return .{ .fields = fields.items, .functions = functions.items, .doc = app_doc };
    \\}
    \\
    \\/// `name <name>`, `extension <.ext>`, `comment <start>` and `boolean <spelling>` give the
    \\/// adapter's data; `gives <capability>` each capability.
    \\fn declareAdapter(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.AdapterDeclaration {
    \\    var declaration: kosm.Frontend.AdapterDeclaration = .{ .name = "" };
    \\    var extensions: std.ArrayList([]const u8) = .empty;
    \\    var functions: std.ArrayList([]const u8) = .empty;
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    var number: usize = 0;
    \\    while (lines.next()) |line| {
    \\        number += 1;
    \\        const space = std.mem.findScalar(u8, line, ' ') orelse continue;
    \\        const word = line[0..space];
    \\        const rest = line[space + 1 ..];
    \\        if (std.mem.eql(u8, word, "name")) declaration.name = rest;
    \\        if (std.mem.eql(u8, word, "extension")) try extensions.append(context.arena, rest);
    \\        if (std.mem.eql(u8, word, "comment")) declaration.comment = .{ .line = rest };
    \\        if (std.mem.eql(u8, word, "gives")) try functions.append(context.arena, rest);
    \\        if (std.mem.eql(u8, word, "boolean")) declaration.default_format = .{ .value = .{ .table = try context.arena.dupe(kosm.Loose.Entry, &.{.{ .key = "boolean", .value = .{ .value = .{ .string = rest }, .origin = try context.at(number) } }}) } };
    \\    }
    \\    declaration.extensions = extensions.items;
    \\    declaration.functions = functions.items;
    \\    return declaration;
    \\}
    \\
    \\/// `name <name>`, `extension <.ext>`, `editor <file>` and `gives <function>` give the
    \\/// frontend's data and functions.
    \\fn declareFrontend(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.FrontendDeclaration {
    \\    var declaration: kosm.Frontend.FrontendDeclaration = .{ .name = "" };
    \\    var extensions: std.ArrayList([]const u8) = .empty;
    \\    var functions: std.ArrayList([]const u8) = .empty;
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    while (lines.next()) |line| {
    \\        const space = std.mem.findScalar(u8, line, ' ') orelse continue;
    \\        const word = line[0..space];
    \\        const rest = line[space + 1 ..];
    \\        if (std.mem.eql(u8, word, "name")) declaration.name = rest;
    \\        if (std.mem.eql(u8, word, "extension")) try extensions.append(context.arena, rest);
    \\        if (std.mem.eql(u8, word, "editor")) declaration.editor_file = .{ .path = rest, .contents = "{}\n" };
    \\        if (std.mem.eql(u8, word, "gives")) try functions.append(context.arena, rest);
    \\    }
    \\    declaration.extensions = extensions.items;
    \\    declaration.functions = functions.items;
    \\    return declaration;
    \\}
    \\
    \\/// A frontend for this frontend's own lines, each starting with the script's `prefix <word>`:
    \\/// `load` and `variants` read the lines without it, `complete` writes `words.txt`.
    \\fn callFrontend(context: *kosm.Frontend.Context, source: []const u8, function: []const u8, arguments: []const kosm.Loose) kosm.Frontend.Error!kosm.Loose {
    \\    const arena = context.arena;
    \\    const prefix = lineAt(source, lineOf(source, "prefix ").?)["prefix ".len..];
    \\    if (std.mem.eql(u8, function, "complete")) {
    \\        const standalone = field(arguments[0], "standalone").?.value.string;
    \\        const file = try table(arena, &.{ .{ .key = "path", .value = .{ .value = .{ .string = "words.txt" } } }, .{ .key = "contents", .value = .{ .value = .{ .string = try arena.print("{s} {s}\n", .{ prefix, standalone }) } } } });
    \\        return .{ .value = .{ .list = try arena.dupe(kosm.Loose, &.{file}) } };
    \\    }
    \\    const path = arguments[1].value.string;
    \\    var stripped: std.Io.Writer.Allocating = .init(arena);
    \\    var lines = std.mem.splitScalar(u8, arguments[0].value.string, '\n');
    \\    var number: usize = 0;
    \\    while (lines.next()) |line| {
    \\        number += 1;
    \\        if (line.len == 0) continue;
    \\        if (!std.mem.startsWith(u8, line, prefix) or line.len == prefix.len or line[prefix.len] != ' ')
    \\            return context.fail("{s}:{d}: the line does not start with '{s}'", .{ path, number, prefix });
    \\        stripped.writer.print("{s}\n", .{line[prefix.len + 1 ..]}) catch return error.OutOfMemory;
    \\    }
    \\    var inner: kosm.Frontend.Context = .{ .arena = arena, .path = path };
    \\    if (std.mem.eql(u8, function, "variants")) {
    \\        const names = try variants(&inner, stripped.written());
    \\        const items = try arena.alloc(kosm.Loose, names.len);
    \\        for (names, items) |name, *item| item.* = .{ .value = .{ .string = name } };
    \\        return .{ .value = .{ .list = items } };
    \\    }
    \\    const script = load(&inner, stripped.written()) catch |err| switch (err) {
    \\        error.OutOfMemory => return error.OutOfMemory,
    \\        error.InvalidScript => return context.fail("{s}", .{inner.message.?}),
    \\    };
    \\    var entries: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    if (script.base) |base| try entries.append(arena, .{ .key = "base", .value = .{ .value = .{ .string = base } } });
    \\    if (script.params) |given| try entries.append(arena, .{ .key = "params", .value = given });
    \\    if (script.theme) |given| try entries.append(arena, .{ .key = "theme", .value = given });
    \\    if (script.overrides) |given| try entries.append(arena, .{ .key = "overrides", .value = given });
    \\    return .{ .value = .{ .table = entries.items } };
    \\}
    \\
    \\/// An adapter's capabilities for `key = value` lines, positions counting from 1: `format`
    \\/// quotes strings with the script's `quote <character>`, and `parser` fails on `fails parser`.
    \\fn callAdapter(context: *kosm.Frontend.Context, source: []const u8, function: []const u8, arguments: []const kosm.Loose) kosm.Frontend.Error!kosm.Loose {
    \\    const arena = context.arena;
    \\    if (std.mem.eql(u8, function, "format")) return .{ .value = .{ .string = try formatTagged(context, source, arguments[0]) } };
    \\    if (std.mem.eql(u8, function, "serialize")) {
    \\        var text: std.Io.Writer.Allocating = .init(arena);
    \\        for (field(arguments[0], "value").?.value.list) |entry| {
    \\            text.writer.print("{s} = {s}\n", .{ field(entry, "key").?.value.string, try formatTagged(context, source, field(entry, "value").?) }) catch return error.OutOfMemory;
    \\        }
    \\        return .{ .value = .{ .string = text.written() } };
    \\    }
    \\    if (std.mem.eql(u8, function, "parser")) {
    \\        if (lineOf(source, "fails parser")) |line| return context.fail("{s}: the file is not read on purpose", .{try context.at(line)});
    \\        const file = arguments[0].value.string;
    \\        var children: std.ArrayList(kosm.Loose) = .empty;
    \\        var start: usize = 0;
    \\        while (start < file.len) {
    \\            const end = std.mem.findScalarPos(u8, file, start, '\n') orelse file.len;
    \\            const line = file[start..end];
    \\            if (line.len != 0 and line[0] != '#') if (std.mem.find(u8, line, " = ")) |equals| {
    \\                const first: i64 = @intCast(start + equals + 3 + 1);
    \\                try children.append(arena, try table(arena, &.{
    \\                    .{ .key = "key", .value = .{ .value = .{ .string = line[0..equals] } } },
    \\                    .{ .key = "kind", .value = .{ .value = .{ .string = "scalar" } } },
    \\                    .{ .key = "position", .value = .{ .value = .{ .integer = @intCast(start + 1) } } },
    \\                    .{ .key = "value", .value = .{ .value = .{ .list = try arena.dupe(kosm.Loose, &.{ .{ .value = .{ .integer = first } }, .{ .value = .{ .integer = @intCast(end) } } }) } } },
    \\                }));
    \\            };
    \\            start = end + 1;
    \\        }
    \\        return table(arena, &.{
    \\            .{ .key = "kind", .value = .{ .value = .{ .string = "table" } } },
    \\            .{ .key = "position", .value = .{ .value = .{ .integer = 1 } } },
    \\            .{ .key = "value", .value = .{ .value = .{ .list = try arena.dupe(kosm.Loose, &.{ .{ .value = .{ .integer = 1 } }, .{ .value = .{ .integer = @intCast(file.len) } } }) } } },
    \\            .{ .key = "children", .value = .{ .value = .{ .list = children.items } } },
    \\        });
    \\    }
    \\    // insert: a new line at the end of the file.
    \\    const length: i64 = @intCast(arguments[0].value.string.len);
    \\    const content = try arena.print("{s} = {s}\n", .{ arguments[2].value.string, arguments[3].value.string });
    \\    const insertion = try table(arena, &.{
    \\        .{ .key = "range", .value = .{ .value = .{ .list = try arena.dupe(kosm.Loose, &.{ .{ .value = .{ .integer = length + 1 } }, .{ .value = .{ .integer = length } } }) } } },
    \\        .{ .key = "content", .value = .{ .value = .{ .string = content } } },
    \\    });
    \\    return .{ .value = .{ .list = try arena.dupe(kosm.Loose, &.{insertion}) } };
    \\}
    \\
    \\fn formatTagged(context: *kosm.Frontend.Context, source: []const u8, value: kosm.Loose) kosm.Frontend.Error![]const u8 {
    \\    if (field(value, "text")) |text| return text.value.string;
    \\    const kind = field(value, "kind").?.value.string;
    \\    const held = field(value, "value").?;
    \\    if (std.mem.eql(u8, kind, "integer")) return context.arena.print("{d}", .{held.value.integer});
    \\    const quote: []const u8 = if (lineOf(source, "quote ")) |line| lineAt(source, line)["quote ".len..] else "\"";
    \\    if (std.mem.eql(u8, kind, "string")) return context.arena.print("{s}{s}{s}", .{ quote, held.value.string, quote });
    \\    return context.fail("cannot write a {s}", .{kind});
    \\}
    \\
    \\fn field(value: kosm.Loose, name: []const u8) ?kosm.Loose {
    \\    for (value.value.table) |entry| {
    \\        if (std.mem.eql(u8, entry.key, name)) return entry.value;
    \\    }
    \\    return null;
    \\}
    \\
    \\fn table(arena: std.mem.Allocator, entries: []const kosm.Loose.Entry) !kosm.Loose {
    \\    return .{ .value = .{ .table = try arena.dupe(kosm.Loose.Entry, entries) } };
    \\}
    \\
    \\fn lineAt(source: []const u8, number: usize) []const u8 {
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    for (1..number) |_| _ = lines.next();
    \\    return lines.next().?;
    \\}
    \\
    \\/// `from` sets `peak` from the theme's mode (1 dark, 2 light), or fails on `from fails`;
    \\/// `apply` writes `size` and `peak` to its file through the kitty adapter.
    \\fn call(context: *kosm.Frontend.Context, source: []const u8, function: []const u8, arguments: []const kosm.Loose) kosm.Frontend.Error!kosm.Loose {
    \\    if (std.mem.startsWith(u8, context.path, "adapters/")) return callAdapter(context, source, function, arguments);
    \\    if (std.mem.startsWith(u8, context.path, "frontends/")) return callFrontend(context, source, function, arguments);
    \\    var frontend_call = context.library.call(context.arena);
    \\    if (std.mem.eql(u8, function, "from")) {
    \\        if (lineOf(source, "from fails")) |line| return context.fail("{s}: from fails on purpose", .{try context.at(line)});
    \\        const theme = arguments[0].value.handle;
    \\        const mode = theme.type.get(&frontend_call, theme.pointer, .{ .field = "mode" }) catch return context.fail("cannot read the mode", .{});
    \\        const peak: i64 = if (std.mem.eql(u8, mode.value.string, "light")) 2 else 1;
    \\        return .{ .value = .{ .table = try context.arena.dupe(kosm.Loose.Entry, &.{.{ .key = "peak", .value = .{ .value = .{ .integer = peak } } }}) } };
    \\    }
    \\    if (lineOf(source, "edit ")) |line| return editFile(context, &frontend_call, lineAt(source, line)["edit ".len..], line, arguments[1]);
    \\    const line = lineOf(source, "apply ").?;
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    for (1..line) |_| _ = lines.next();
    \\    const file = lines.next().?["apply ".len..];
    \\    const self = arguments[0].value.handle;
    \\    var values: std.ArrayList(kosm.Loose.Entry) = .empty;
    \\    for ([_][]const u8{ "size", "peak" }) |name| {
    \\        const value = self.type.get(&frontend_call, self.pointer, .{ .field = name }) catch return context.fail("cannot read {s}", .{name});
    \\        if (value.value != .null) try values.append(context.arena, .{ .key = name, .value = value });
    \\    }
    \\    const generate = arguments[1].value.handle.type.method("generateValue") orelse return context.fail("kosm.Output has no generateValue", .{});
    \\    const options: kosm.Loose = .{ .value = .{ .table = try context.arena.dupe(kosm.Loose.Entry, &.{ .{ .key = "file", .value = .{ .value = .{ .string = file } } }, .{ .key = "lang", .value = .{ .value = .{ .string = "kitty" } } } }) } };
    \\    _ = generate.call(&frontend_call, &.{ arguments[1], options, .{ .value = .{ .table = values.items } } }) catch
    \\        return context.fail("{s}: {s}", .{ try context.at(line), frontend_call.message orelse "it failed" });
    \\    return .{ .value = .null };
    \\}
    \\
    \\/// `edit <files> <path> <text>`: sets the value at `path` to `text` through `output:edit`.
    \\fn editFile(context: *kosm.Frontend.Context, frontend_call: *kosm.Frontend.Call, words: []const u8, line: usize, output: kosm.Loose) kosm.Frontend.Error!kosm.Loose {
    \\    var parts = std.mem.splitScalar(u8, words, ' ');
    \\    const files = parts.first();
    \\    const path = parts.next().?;
    \\    const text = parts.rest();
    \\    const edit = output.value.handle.type.method("edit") orelse return context.fail("kosm.Output has no edit", .{});
    \\    const options = try table(context.arena, &.{.{ .key = "files", .value = .{ .value = .{ .string = files } } }});
    \\    const selection = edit.call(frontend_call, &.{ output, options }) catch return context.fail("{s}: {s}", .{ try context.at(line), frontend_call.message orelse "it failed" });
    \\    const set = selection.value.handle.type.method("setValue") orelse return context.fail("kosm.Output.Selection has no setValue", .{});
    \\    _ = set.call(frontend_call, &.{ selection, .{ .value = .{ .string = path } }, .{ .value = .{ .string = text } } }) catch return context.fail("{s}: {s}", .{ try context.at(line), frontend_call.message orelse "it failed" });
    \\    return .{ .value = .null };
    \\}
    \\
    \\fn lineOf(source: []const u8, start: []const u8) ?usize {
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    var number: usize = 0;
    \\    while (lines.next()) |line| {
    \\        number += 1;
    \\        if (std.mem.startsWith(u8, line, start)) return number;
    \\    }
    \\    return null;
    \\}
    \\
    \\fn complete(context: *kosm.Frontend.Context, completion: kosm.Frontend.Completion) kosm.Frontend.Error![]const kosm.Frontend.Completion.File {
    \\    const arena = context.arena;
    \\    var text: std.Io.Writer.Allocating = .init(arena);
    \\    for (completion.kosmoi) |kosmos| text.writer.print("kosmos {s} {s}\n", .{ kosmos.name, kosmos.tree }) catch return error.OutOfMemory;
    \\    const theme = completion.find(completion.theme).?;
    \\    text.writer.print("theme {s}: {s}\n", .{ theme.name, theme.fields[0].doc.? }) catch return error.OutOfMemory;
    \\    return arena.dupe(kosm.Frontend.Completion.File, &.{.{ .path = "types/all.txt", .contents = text.written() }});
    \\}
    \\
    \\fn variants(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error![]const []const u8 {
    \\    var given: std.ArrayList([]const u8) = .empty;
    \\    var lines = std.mem.splitScalar(u8, source, '\n');
    \\    while (lines.next()) |line| {
    \\        if (std.mem.startsWith(u8, line, "gives ")) try given.append(context.arena, line["gives ".len..]);
    \\    }
    \\    return given.items;
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
    \\        if (std.mem.eql(u8, line[0..space], "gives")) continue;
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

/// A config project in `dir`'s `project/` on the stub kitty package, its home in `home/`,
/// writing to `stdout` and `stderr`.
fn testProject(arena: std.mem.Allocator, dir: std.Io.Dir, stdout: *std.Io.Writer.Allocating, stderr: *std.Io.Writer.Allocating) !Context {
    const root = try dir.realPathFileAlloc(testing.io, ".", arena);
    // Assumes the tests run from the repository root, as `zig build test` does.
    const repository_root = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", arena);
    const environ = try arena.create(std.process.Environ.Map);
    environ.* = try testing.environ.createMap(arena);
    _ = environ.swapRemove("ZIG_PROGRESS");
    // Shared with the other config tests, so the compiled std stays warm.
    try environ.put("ZIG_GLOBAL_CACHE_DIR", try std.Io.Dir.path.join(arena, &.{ repository_root, ".zig-cache/kosm-test-global-cache" }));
    try environ.put("HOME", try std.Io.Dir.path.join(arena, &.{ root, "home" }));
    try environ.put(interface.environment_variable, try arena.print("{d}", .{interface.version}));
    try dir.createDirPath(testing.io, "home");
    try dir.createDirPath(testing.io, "project");
    const test_kosm = @import("test_kosm.zig");
    const context: Context = .{
        .io = testing.io,
        .arena = arena,
        .config = try std.Io.Dir.path.join(arena, &.{ root, "project" }),
        .environ_map = environ,
        .sources = try test_kosm.sources(arena, testing.io),
        .stdout = &stdout.writer,
        .stderr = &stderr.writer,
    };
    try @import("init.zig").init(context, try test_kosm.stub(arena, testing.io, dir, root));
    // The tests write apps and adapters by hand, without `kosm new` creating their folders.
    try dir.createDirPath(testing.io, "project/apps");
    try dir.createDirPath(testing.io, "project/adapters");
    return context;
}

test "a package whose root is a script may give a kosmos, a Zig one and one not fetched never" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var output: std.Io.Writer.Allocating = .init(arena);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "build.zig.zon", .data =
        \\.{ .name = .config, .dependencies = .{
        \\    .kosm_glacier = .{ .path = "glacier" },
        \\    .kosm_kitty = .{ .path = "kitty" },
        \\    .kosm_frost = .{ .url = "x", .hash = "frost-hash" },
        \\    .kosm_hail = .{ .url = "x", .hash = "hail-hash" },
        \\} }
        \\
    });
    try tmp.dir.createDirPath(testing.io, "glacier");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "glacier/root.lua", .data = "" });
    try tmp.dir.createDirPath(testing.io, "kitty");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "kitty/root.zig", .data = "" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "kitty/root.lua", .data = "" });
    try tmp.dir.createDirPath(testing.io, "zig-pkg/frost-hash");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "zig-pkg/frost-hash/root.lua", .data = "" });
    const context: Context = .{ .io = testing.io, .arena = arena, .config = try tmp.dir.realPathFileAlloc(testing.io, ".", arena), .stdout = &output.writer, .stderr = &output.writer };

    try testing.expect(try isScript(context, "kosm_glacier"));
    try testing.expect(try isScript(context, "kosm_glacier.light"));
    try testing.expect(try isScript(context, "kosm_frost"));
    try testing.expect(!try isScript(context, "kosm_kitty"));
    try testing.expect(!try isScript(context, "kosm_hail"));
    try testing.expect(try any(context));
}

test "script kosmoi apply on a Zig kosmos, on each other and on none, and a variant's edit builds nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var stdout: std.Io.Writer.Allocating = .init(arena);
    var stderr: std.Io.Writer.Allocating = .init(arena);
    const context = try testProject(arena, tmp.dir, &stdout, &stderr);
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
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/bare/root.kosmos", .data = "base frost\ngives light\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/typo.kosmos", .data = "base frots\n" });

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
    try testing.expectEqualStrings("error: kosmos 'snow.melted': Params.on: there is no kosmos 'alon'; did you mean 'alone'?\n", try testDiffWith(context, "snow.melted", &.{ "--on", "alon" }));
    // A misspelled script, script variant or base fails in one line naming the closest kosmoi.
    try testing.expectEqualStrings("error: there is no kosmos 'hial'; did you mean 'hail'?\n", try testDiff(context, "hial"));
    try testing.expectEqualStrings("error: there is no kosmos 'bare.lihgt'; did you mean 'bare.light'?\n", try testDiff(context, "bare.lihgt"));
    try testing.expect(std.mem.find(u8, try testDiff(context, "bare.light"), "+font_size 10\n") != null);
    try testing.expectEqualStrings("error: kosmos 'typo': kosmoi/typo.kosmos: there is no kosmos 'frots'; did you mean 'frost'?\n", try testDiff(context, "typo"));
    // Its own runner sends it to the runner of scripts.
    try testing.expect(try context.runBuild(&.{ "build", "-Dkosmos=snow.melted" }));
    const kosmos_runner = try std.Io.Dir.path.join(arena, &.{ context.config, "zig-out/bin/kosmos" });
    try testing.expect(try buildsOnKosmoi(context, kosmos_runner));
    try testing.expect(try context.runBuild(&.{ "build", "-Dkosmos=snow" }));
    try testing.expect(!try buildsOnKosmoi(context, kosmos_runner));

    // A variant in a kosmos' folder is read only when kosm runs; a kosmos' own script may change
    // what it exports, which a build sees, compiling nothing when it did not.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/snow/nord.kosmos", .data = "base snow\nset kitty.fonts.font_size=22\n" });
    try testing.expect(!try isStale(context));
    try testing.expect(std.mem.find(u8, try testDiff(context, "snow.nord"), "+font_size 22\n") != null);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/on.kosmos", .data = "base frost\nparam size=13\n" });
    try testing.expect(try isStale(context));
    try testing.expect(try build(context));
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
    // A Zig variant in a script kosmos' folder completes its own parameters and paths.
    const hail_iced = (try report(context, "hail.iced")).?;
    try testing.expect(std.mem.find(u8, hail_iced, "param\t--on\t") != null);
    try testing.expect(std.mem.find(u8, hail_iced, "set\tkitty.fonts.font_size\t") != null);
    try testing.expectEqual(null, try baseOf(context, "hail.iced"));

    // `kosm list` shows scripts, and `kosm build` takes a script's name.
    stdout.clearRetainingCapacity();
    try @import("list.zig").list(context, null, &.{});
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/on.kosmos\n") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), "  snow.nord ") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/snow/nord.kosmos\n") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), "  hail ") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/hail/root.kosmos\n  hail.iced ") != null);
    try testing.expect(std.mem.find(u8, stdout.written(), " kosmoi/bare/root.kosmos\n  bare.light ") != null);
    // Before anything is built for it, a misspelled kosmos fails naming the closest, the
    // variants scripts give included.
    stderr.clearRetainingCapacity();
    try testing.expectError(error.Failed, @import("known_kosmoi.zig").check(context, "snow.melte", .kosmos, ""));
    try testing.expectEqualStrings("error: there is no kosmos 'snow.melte'; did you mean 'snow.melted'?\n", stderr.written());
    try @import("known_kosmoi.zig").check(context, "bare.light", .kosmos, "");
    stderr.clearRetainingCapacity();
    try testing.expectError(error.Failed, @import("known_kosmoi.zig").check(context, "bare.ligth", .kosmos, ""));
    try testing.expectEqualStrings("error: there is no kosmos 'bare.ligth'; did you mean 'bare.light'?\n", stderr.written());
    stderr.clearRetainingCapacity();
    try testing.expectError(error.Failed, @import("list.zig").list(context, "bare.ligth", &.{}));
    try testing.expectEqualStrings("error: there is no kosmos 'bare.ligth'; did you mean 'bare.light'?\n", stderr.written());
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
    const clash = stderr.written();
    try testing.expect(std.mem.find(u8, clash, "'frost' names both ") != null and std.mem.find(u8, clash, "kosmoi/frost.kosmos") != null and std.mem.find(u8, clash, "kosmoi/frost.zig") != null);
}

/// An app written through the test frontend: its size and the peak its `from` gives.
const test_meter =
    \\doc A meter, for tests.
    \\doc How many bars.
    \\field size integer 3
    \\field peak optional-integer
    \\from
    \\apply ~/.config/meter/kosm.conf
    \\
;

/// A Zig kosmos wearing the meter in a light theme, its size set after `from`.
const test_gauge =
    \\const kosm = @import("kosm");
    \\const meter = @import("meter");
    \\
    \\pub fn kosmos() struct { meter: meter.App } {
    \\    var app = meter.from(kosm.Theme.from(.{ .palette = .{ .black = kosm.hex("000000"), .white = kosm.hex("ffffff") }, .mode = .light }));
    \\    app.size = 5;
    \\    return .{ .meter = app };
    \\}
    \\
;

test "an app written through a frontend applies from a Zig kosmos and a script, and a script edit compiles nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var stdout: std.Io.Writer.Allocating = .init(arena);
    var stderr: std.Io.Writer.Allocating = .init(arena);
    const context = try testProject(arena, tmp.dir, &stdout, &stderr);
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/lines.zig", .data = test_frontend });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/apps/meter.kosmos", .data = test_meter });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/gauge.zig", .data = test_gauge });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/alone.kosmos", .data = "theme palette.black=#000000\ntheme palette.white=#ffffff\ntheme mode=dark\nset meter.size=9\n" });

    try testing.expect(try prepare(context));
    // The module kosm wrote from the script, documented, which a Zig kosmos uses like any app.
    const generated = "project/.zig-cache/kosm/modules/meter.zig";
    const module = try tmp.dir.readFileAlloc(testing.io, generated, arena, .limited(1024 * 1024));
    try testing.expect(std.mem.find(u8, module, "/// A meter, for tests.\npub const App = struct {\n    /// How many bars.\n    size: i64 = 3,\n    peak: ?i64 = null,\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "gauge"), "+size 5\n+peak 2\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "alone"), "+size 9\n+peak 1\n") != null);
    // Its own runner sends a Zig kosmos wearing it to the runner of scripts.
    try testing.expect(try context.runBuild(&.{ "build", "-Dkosmos=gauge" }));
    try testing.expect(try buildsOnKosmoi(context, try std.Io.Dir.path.join(arena, &.{ context.config, "zig-out/bin/kosmos" })));

    // An edit leaving the declaration alone rebuilds the runner without touching the module.
    try tmp.dir.setTimestamps(testing.io, generated, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 0 } } });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/apps/meter.kosmos", .data = try std.mem.replaceOwned(u8, arena, test_meter, "kosm.conf", "other.conf") });
    try testing.expect(try isStale(context));
    try testing.expect(try prepare(context));
    try testing.expectEqual(0, (try tmp.dir.statFile(testing.io, generated, .{})).mtime.nanoseconds);
    try testing.expect(std.mem.find(u8, try testDiff(context, "gauge"), "~/.config/meter/other.conf") != null);
    // A failing from fails the kosmos with the script's line once it returns.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/apps/meter.kosmos", .data = try std.mem.concat(arena, u8, &.{ test_meter, "from fails\n" }) });
    try testing.expectEqualStrings("error: kosmos 'gauge': apps/meter.kosmos:7: from fails on purpose\n", try testDiff(context, "gauge"));
    try testing.expectEqualStrings("error: kosmos 'alone': apps/meter.kosmos:7: from fails on purpose\n", try testDiff(context, "alone"));
    // A declaration kosm cannot write fails the build naming the script's line.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/apps/meter.kosmos", .data = "field size\napply ~/a.conf\n" });
    stderr.clearRetainingCapacity();
    try testing.expect(!try prepare(context));
    try testing.expect(std.mem.find(u8, stderr.written(), "apps/meter.kosmos:1: a field needs a type") != null);
}

/// An adapter written through the test frontend, for `key = value` files.
const test_keys =
    \\name keys
    \\extension .keys
    \\comment #
    \\boolean yes_no
    \\gives format
    \\gives parser
    \\gives serialize
    \\gives insert
    \\
;

/// A Zig app writing through the keys adapter: it sets `size` in a file of the user's, adds
/// `include`, and writes a file of its own.
const test_keyed_app =
    \\const kosm = @import("kosm");
    \\
    \\pub const App = struct {
    \\    size: i64 = 3,
    \\
    \\    pub fn apply(self: App, output: *kosm.Output) !void {
    \\        var selection = try output.edit(.{ .files = "~/.config/keyed/main.keys" });
    \\        try selection.set("size", self.size);
    \\        for (try selection.nodes("")) |root| try selection.insert(root, "include", "kosm.keys");
    \\        try output.generate(.{ .file = "~/.config/keyed/kosm.keys" }, .{ .blur = true, .accent = kosm.hex("ff0000"), .name = "kosm", .gaps = 0.25 });
    \\    }
    \\};
    \\
;

const test_keyed =
    \\const keyed = @import("keyed");
    \\const namer = @import("namer");
    \\
    \\pub fn kosmos() struct { keyed: keyed.App, namer: namer.App } {
    \\    return .{ .keyed = .{ .size = 12 }, .namer = .{} };
    \\}
    \\
;

test "an adapter written through a frontend reads and writes files for a Zig app, and a script edit compiles nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var stdout: std.Io.Writer.Allocating = .init(arena);
    var stderr: std.Io.Writer.Allocating = .init(arena);
    const context = try testProject(arena, tmp.dir, &stdout, &stderr);
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/lines.zig", .data = test_frontend });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/keys.kosmos", .data = test_keys });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/apps/keyed.zig", .data = test_keyed_app });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/apps/namer.kosmos", .data = "field size integer 1\nedit ~/.config/keyed/main.keys name kosm\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/keyed_kosmos.zig", .data = test_keyed });
    try tmp.dir.createDirPath(testing.io, "home/.config/keyed");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "home/.config/keyed/main.keys", .data = "# sizes\nsize = 4\nname = \"x\"\n" });

    try testing.expect(try prepare(context));
    const generated = "project/.zig-cache/kosm/modules/keys.zig";
    const module = try tmp.dir.readFileAlloc(testing.io, generated, arena, .limited(1024 * 1024));
    try testing.expect(std.mem.find(u8, module, ".counts_from = 1 };") != null);
    try testing.expect(std.mem.find(u8, module, "    .default_format = .{ .boolean = .yes_no },\n    .comment = .{ .line = \"#\" },\n") != null);
    // Only the value's bytes change, the include is added at the end, and the generated file
    // spells its values in the adapter's format.
    const diff = try testDiff(context, "keyed_kosmos");
    // A script app edits the same file through the script adapter, by a path in text.
    try testing.expect(std.mem.find(u8, diff, "-size = 4\n-name = \"x\"\n+size = 12\n+name = \"kosm\"\n+include = \"kosm.keys\"\n") != null);
    try testing.expect(std.mem.find(u8, diff, "+blur = yes\n+accent = #ff0000\n+name = \"kosm\"\n+gaps = 0.25\n") != null);
    // Its own runner sends the kosmos to the runner of scripts, which alone runs scripts.
    try testing.expect(try context.runBuild(&.{ "build", "-Dkosmos=keyed_kosmos" }));
    try testing.expect(try buildsOnKosmoi(context, try std.Io.Dir.path.join(arena, &.{ context.config, "zig-out/bin/kosmos" })));

    // An edit leaving the declaration alone rebuilds the runner without touching the module.
    try tmp.dir.setTimestamps(testing.io, generated, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 0 } } });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/keys.kosmos", .data = try std.mem.concat(arena, u8, &.{ test_keys, "quote '\n" }) });
    try testing.expect(try isStale(context));
    try testing.expect(try prepare(context));
    try testing.expectEqual(0, (try tmp.dir.statFile(testing.io, generated, .{})).mtime.nanoseconds);
    try testing.expect(std.mem.find(u8, try testDiff(context, "keyed_kosmos"), "+name = 'kosm'\n") != null);
    // A script's failure names the file being read and the script's line.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/keys.kosmos", .data = try std.mem.concat(arena, u8, &.{ test_keys, "fails parser\n" }) });
    const failed = try testDiff(context, "keyed_kosmos");
    try testing.expect(std.mem.find(u8, failed, "~/.config/keyed/main.keys") != null);
    try testing.expect(std.mem.find(u8, failed, "adapters/keys.kosmos:9: the file is not read on purpose") != null);
}

test "a frontend written through a frontend reads kosmoi, completes them, and a script edit compiles nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var stdout: std.Io.Writer.Allocating = .init(arena);
    var stderr: std.Io.Writer.Allocating = .init(arena);
    const context = try testProject(arena, tmp.dir, &stdout, &stderr);
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/kyanos.zig");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/adapters/lines.zig", .data = test_frontend });
    try tmp.dir.createDirPath(testing.io, "project/frontends");
    const words = "name words\nextension .words\neditor .words.json\ngives load\ngives variants\ngives complete\nprefix w\n";
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/frontends/words.kosmos", .data = words });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/frost.zig", .data = test_frost });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/mine.words", .data = "w base frost\nw param size=12\nw gives light\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/bad.words", .data = "w base frost\nw set kitty.fonts.font_size=big\n" });

    stdout.clearRetainingCapacity();
    try testing.expect(try prepare(context));
    const generated = "project/.zig-cache/kosm/modules/words.zig";
    const module = try tmp.dir.readFileAlloc(testing.io, generated, arena, .limited(1024 * 1024));
    try testing.expect(std.mem.find(u8, module, "    .name = \"words\",\n    .extensions = &.{ \".words\" },\n    .load = functions.load,\n    .variants = functions.variants,\n    .complete = functions.complete,\n") != null);
    // Its completion and editor file are written through the script.
    try testing.expect(std.mem.find(u8, stdout.written(), "created .words.json\n") != null);
    try testing.expectEqualStrings("w kosm.Standalone\n", try tmp.dir.readFileAlloc(testing.io, "project/zig-out/completions/words/words.txt", arena, .limited(1024)));
    try testing.expect(std.mem.find(u8, try testDiff(context, "mine"), "+font_size 12\n") != null);
    try testing.expect(std.mem.find(u8, try testDiff(context, "mine.light"), "+font_size 12\n") != null);
    // Frontends, written in Zig or through one, are listed from the runner of scripts.
    stdout.clearRetainingCapacity();
    try @import("list.zig").list(context, null, &.{"--frontends"});
    try testing.expectEqualStrings("lines  adapters/lines.zig\nwords  frontends/words.kosmos\n", stdout.written());
    // A value's error names the kosmos' line, and so does an error the script raises about it.
    try testing.expect(std.mem.find(u8, try testDiff(context, "bad"), "kosmoi/bad.words:2") != null);
    // Every script's variants are listed first, so one the script cannot read fails them all.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/broken.words", .data = "w base frost\nbase frost\n" });
    try testing.expect(std.mem.find(u8, try testDiff(context, "mine"), "kosmoi/broken.words:2: the line does not start with 'w'") != null);
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/broken.words");

    // An edit leaving the declaration alone rebuilds the runner without touching the module.
    try tmp.dir.setTimestamps(testing.io, generated, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 0 } } });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/frontends/words.kosmos", .data = try std.mem.replaceOwned(u8, arena, words, "prefix w", "prefix word") });
    try testing.expect(try isStale(context));
    try testing.expect(try prepare(context));
    try testing.expectEqual(0, (try tmp.dir.statFile(testing.io, generated, .{})).mtime.nanoseconds);
    try tmp.dir.deleteFile(testing.io, "project/kosmoi/bad.words");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "project/kosmoi/mine.words", .data = "word base frost\nword param size=13\n" });
    try testing.expect(std.mem.find(u8, try testDiff(context, "mine"), "+font_size 13\n") != null);
}
