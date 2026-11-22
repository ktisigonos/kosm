//! Finds a script kosmos in the config's `kosmoi/` or at a package's root, reads it through the
//! frontend claiming its extension, and follows what it builds on through other scripts down to a
//! Zig kosmos or to none.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const kosmos_call = @import("kosmos_call.zig");

/// Where script kosmoi live, in the config's root.
pub const directory = "kosmoi";
/// Zig sources and manifests in `directory` and kosmos folders are never scripts.
const zig_extensions = [_][]const u8{ ".zig", ".zon" };
/// Far beyond any script; a guard against naming a disk image by mistake.
const size_limit = 16 * 1024 * 1024;

pub const Error = error{Reported} || std.mem.Allocator.Error;

/// What resolving needs from the runner.
pub const Context = struct {
    /// Holds the scripts and what their frontends read, for the whole run.
    arena: std.mem.Allocator,
    io: std.Io,
    /// The config project's absolute path.
    config: []const u8,
    frontends: []const discovery.DeclaredFrontend,
    /// The name of every module that may declare Zig kosmoi, which no script may share.
    modules: []const []const u8,
    /// Every Zig kosmos, which no script in a kosmos' folder may share its name with.
    kosmoi: []const KosmosName = &.{},
    /// Every package whose root script gives its kosmos, named after the package.
    packages: []const PackageKosmos = &.{},
    /// The config's scripts exporting values for building on, as messages show them
    /// ("kosmoi/frost/root.lua"): each gives a module whose kosmoi are Zig kosmoi, so it is no
    /// script kosmos.
    exporting: []const []const u8 = &.{},
    /// What a script may call.
    library: kosm.Frontend.Library = .{},
    /// Set to each script's folder while its frontend reads it, so that relative paths the
    /// script gives to its calls start there.
    calls_folder: ?*[]const u8 = null,
    /// The kosmoi being built, which each script read is added to, so that a script building
    /// on a Zig kosmos naming it fails naming the circle. The caller restores it once the
    /// script's tree is built.
    building: ?*kosmos_call.Building = null,
    diagnostics: *kosm.Diagnostics,
};

/// A Zig kosmos as `kosm apply` spells it ("personal.everforest"), and where it is declared
/// ("kosmoi/personal/"), for messages.
pub const KosmosName = struct {
    name: []const u8,
    origin: []const u8,
};

/// A package whose root script gives its kosmos.
pub const PackageKosmos = struct {
    /// The package's name, which its kosmos is applied as: "kosm_frost".
    name: []const u8,
    /// As messages show it: "~~kosm_frost/root.lua".
    path: []const u8,
    /// The script's absolute path.
    file: []const u8,
};

/// One script read by its frontend.
pub const Loaded = struct {
    /// As `kosm apply` spells it: "minimal", "minimal.light", "personal.nord".
    name: []const u8,
    /// As messages show it: "kosmoi/minimal.lua", "kosmoi/personal/nord.lua".
    path: []const u8,
    /// The absolute folder holding the script, which relative paths it gives start from.
    folder: []const u8,
    script: kosm.Frontend.Script,
};

/// A script kosmos and everything it builds on.
pub const Chain = struct {
    /// The Zig kosmos at the bottom ("personal", "frost.iced"), or null when the bottom script
    /// has no base.
    base: ?[]const u8,
    /// The tree the bottom script built itself by calling Zig code; then `base` is null.
    tree: ?kosm.Frontend.Handle = null,
    /// Every script, the one building on the base first and the applied one last.
    scripts: []const Loaded,
};

/// Where the script a kosmos name names lives.
pub const Location = struct {
    /// In the config: "kosmoi/minimal.lua", "kosmoi/frost/root.lua" for a script giving its
    /// folder's kosmos, or "kosmoi/personal/nord.lua" for a script in a kosmos' folder.
    path: []const u8,
    /// How much of the name the file names: "minimal" of "minimal.light", or "personal.nord".
    name_length: usize,
    /// ".lua".
    extension: []const u8,
    /// Whether the script is its folder's root, giving the kosmos named after the folder, which
    /// may hold Zig variants in a `root.zig` beside it.
    is_root: bool = false,
};

/// The file name a script giving its folder's kosmos has before its extension.
const root_name = "root";

/// The script kosmos `name` (with any variant) names: `kosmoi/<name>.<extension>`,
/// `kosmoi/<name>/root.<extension>` or the root script of package `name`, or for
/// `kosmos.variant` also `kosmoi/<kosmos>/<variant>.<extension>`. Null when there is none, or when `name` is a Zig
/// kosmos, which wins over the variants of a script it shares a folder with. Two scripts, or a
/// script and a Zig kosmos, giving the same name fail naming both.
pub fn locate(context: Context, name: []const u8) Error!?Location {
    var segments = std.mem.splitScalar(u8, name, '.');
    const first = segments.first();
    const folder = try context.arena.print("{s}/{s}", .{ directory, first });
    const top = try locatedIn(context, directory, first, first, first.len);
    var root = try locatedIn(context, folder, root_name, first, first.len);
    if (root) |*found| found.is_root = true;
    if (top != null and root != null) return fail(context, "'{s}' names both {s} and {s}; rename one", .{ first, top.?.path, root.?.path });
    const package = packageKosmos(context, first);
    if (package) |found| if (top orelse root) |local|
        return fail(context, "'{s}' names both {s} and the kosmos of package '{s}' ({s}); rename one", .{ first, local.path, first, found.path });
    const owner = top orelse root orelse package;
    const variant = segments.next() orelse return owner;
    const nested_name = name[0 .. first.len + 1 + variant.len];
    const nested = if (std.mem.eql(u8, variant, root_name)) null else try locatedIn(context, folder, variant, nested_name, nested_name.len);
    if (zigOrigin(context, name)) |origin| {
        if (nested) |file| try checkName(context, nested_name, file);
        if (owner) |script| {
            if (try givenVariant(context, script, name[first.len + 1 ..])) |given|
                return fail(context, "'{s}.{s}' names both a variant of {s} and a kosmos of {s}; rename one", .{ first, given, script.path, origin });
        }
        return null;
    }
    if (nested) |file| {
        if (owner) |script| {
            if (try givenVariant(context, script, variant)) |given|
                return fail(context, "'{s}.{s}' names both a variant of {s} and {s}; rename one", .{ first, given, script.path, file.path });
        }
        return file;
    }
    if (owner) |script| try checkVariant(context, script, name[0..first.len], name[first.len + 1 ..]);
    return owner;
}

/// The script named `name` in the config's folder `folder`, naming `name_length` bytes of the
/// kosmos name; null when there is none. Two scripts of that name fail, naming it `shown`.
fn locatedIn(context: Context, folder: []const u8, name: []const u8, shown: []const u8, name_length: usize) Error!?Location {
    const file_name = try findIn(context, folder, name, shown) orelse return null;
    return .{
        .path = try context.arena.print("{s}/{s}", .{ folder, file_name }),
        .name_length = name_length,
        .extension = file_name[name.len..],
    };
}

/// The root script of package `name` giving its kosmos, or null when there is none.
fn packageKosmos(context: Context, name: []const u8) ?Location {
    for (context.packages) |package| {
        if (!std.mem.eql(u8, package.name, name)) continue;
        return .{ .path = package.path, .name_length = name.len, .extension = std.Io.Dir.path.extension(package.path), .is_root = true };
    }
    return null;
}

/// Where the Zig kosmos `name` is declared, or null when there is none.
fn zigOrigin(context: Context, name: []const u8) ?[]const u8 {
    for (context.kosmoi) |kosmos| {
        if (std.mem.eql(u8, kosmos.name, name)) return kosmos.origin;
    }
    return null;
}

/// Fails when `variant` of script `script`, the kosmos `owner`, shares a name with a Zig kosmos
/// as a group holding it or held by it (`cold` and `cold.deep`).
fn checkVariant(context: Context, script: Location, owner: []const u8, variant: []const u8) Error!void {
    for (context.kosmoi) |kosmos| {
        if (!std.mem.startsWith(u8, kosmos.name, owner) or kosmos.name.len <= owner.len or kosmos.name[owner.len] != '.') continue;
        if (overlaps(kosmos.name[owner.len + 1 ..], variant))
            return fail(context, "'{s}' names both a variant of {s} and a kosmos of {s}; rename one", .{ kosmos.name, script.path, kosmos.origin });
    }
}

/// The variant of `script` that `variant` ("cold" or "cold.deep") names, is in or holds, as the
/// script spells it; null when the script gives none of them.
fn givenVariant(context: Context, script: Location, variant: []const u8) Error!?[]const u8 {
    const frontend = try frontendFor(context, script.path, script.extension);
    const list = frontend.variants orelse return null;
    const source = try readScript(context, script.path);
    var frontend_context: kosm.Frontend.Context = .{ .arena = context.arena, .path = script.path, .library = context.library };
    var listed: kosm.Frontend.Error![]const []const u8 = undefined;
    try runOnKosmosStack(context, script.path, runVariants, .{ list, &frontend_context, source, &listed });
    const given = listed catch |err| return frontendFailure(context, script.path, &frontend_context, err);
    for (given) |name| {
        if (overlaps(name, variant)) return name;
    }
    return null;
}

/// Whether two dotted names are the same or one holds the other: `cold`, `cold.deep`.
fn overlaps(left: []const u8, right: []const u8) bool {
    const shorter, const longer = if (left.len <= right.len) .{ left, right } else .{ right, left };
    if (!std.mem.startsWith(u8, longer, shorter)) return false;
    return longer.len == shorter.len or longer[shorter.len] == '.';
}

/// The file name of script `name` in the config's folder `folder` ("minimal.lua"), or null
/// when there is none or no such folder. Two scripts of that name fail, naming it `shown`.
fn findIn(context: Context, folder: []const u8, name: []const u8, shown: []const u8) Error!?[]const u8 {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, folder });
    var dir = std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return null,
        else => return fail(context, "cannot read {s}/: {s}", .{ folder, @errorName(err) }),
    };
    defer dir.close(context.io);
    var found: ?[]const u8 = null;
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return fail(context, "cannot read {s}/: {s}", .{ folder, @errorName(err) })) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!isScriptOf(entry.name, name)) continue;
        if (isExporting(context, try context.arena.print("{s}/{s}", .{ folder, entry.name }))) continue;
        if (found) |earlier| return fail(context, "'{s}' names both {s}/{s} and {s}/{s}; rename one", .{ shown, folder, earlier, folder, entry.name });
        found = try context.arena.dupe(u8, entry.name);
    }
    return found;
}

/// Whether the config's script `path` ("kosmoi/frost/root.lua") exports values for building on.
fn isExporting(context: Context, path: []const u8) bool {
    for (context.exporting) |exporting| {
        if (std.mem.eql(u8, exporting, path)) return true;
    }
    return false;
}

/// Whether `file_name` is a script kosmos named `name`: `name`, a dot, and any extension but
/// Zig's and its manifests'.
fn isScriptOf(file_name: []const u8, name: []const u8) bool {
    if (name.len == 0 or std.mem.startsWith(u8, file_name, ".")) return false;
    if (!std.mem.startsWith(u8, file_name, name) or file_name.len <= name.len + 1) return false;
    if (file_name[name.len] != '.') return false;
    for (zig_extensions) |extension| {
        if (std.mem.endsWith(u8, file_name, extension)) return false;
    }
    return true;
}

/// Reads the script kosmos `name` (with a variant, `minimal.light`) and every script below it.
pub fn resolve(context: Context, name: []const u8) Error!Chain {
    var visited: std.ArrayList([]const u8) = .empty;
    var loaded: std.ArrayList(Loaded) = .empty;
    var tree: ?kosm.Frontend.Handle = null;
    var current = name;
    const base: ?[]const u8 = while (true) {
        for (visited.items) |earlier| {
            if (std.mem.eql(u8, earlier, current)) {
                try visited.append(context.arena, current);
                return fail(context, "the kosmoi build on each other in a circle: {s}", .{try std.mem.join(context.arena, " -> ", visited.items)});
            }
        }
        try visited.append(context.arena, current);
        const location = try locate(context, current) orelse {
            if (loaded.items.len == 0) return fail(context, "there is no script kosmos '{s}' in {s}/", .{ current, directory });
            break current;
        };
        try checkName(context, current[0..location.name_length], location);
        if (context.building) |building| try building.enter(context.arena, current, context.diagnostics);
        const variant = if (location.name_length < current.len) try splitVariant(context.arena, current[location.name_length + 1 ..]) else &.{};
        const script = try load(context, current, location, variant);
        try loaded.append(context.arena, script);
        if (script.script.tree) |built| {
            tree = built;
            break null;
        }
        current = script.script.base orelse break null;
    };
    std.mem.reverse(Loaded, loaded.items);
    return .{ .base = base, .tree = tree, .scripts = loaded.items };
}

/// Fails when script `name`, at `location`, shares its name with a Zig module, or, in a kosmos'
/// folder, with a variant or group of that kosmos. A folder's root script shares its name with
/// the folder's own module, which may then give variants only.
fn checkName(context: Context, name: []const u8, location: Location) Error!void {
    if (std.mem.findScalar(u8, name, '.') == null) {
        if (location.is_root) {
            if (zigOrigin(context, name)) |origin|
                return fail(context, "'{s}' names both {s} and the kosmos of {s}; only one root of a folder gives its kosmos", .{ name, location.path, origin });
            return;
        }
        for (context.modules) |module| {
            if (std.mem.eql(u8, module, name)) return fail(context, "'{s}' names both {s} and the Zig module '{s}'; rename one", .{ name, location.path, module });
        }
        return;
    }
    for (context.kosmoi) |kosmos| {
        const shared = std.mem.startsWith(u8, kosmos.name, name) and (kosmos.name.len == name.len or kosmos.name[name.len] == '.');
        if (shared) return fail(context, "'{s}' names both {s} and a kosmos of {s}; rename one", .{ name, location.path, kosmos.origin });
    }
}

/// `light.soft` as `&.{ "light", "soft" }`.
fn splitVariant(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var segments: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, text, '.');
    while (parts.next()) |part| try segments.append(arena, part);
    return segments.items;
}

/// Reads the script at `location` through the frontend claiming its extension, building
/// `variant` of it.
fn load(context: Context, name: []const u8, location: Location, variant: []const []const u8) Error!Loaded {
    const shown = location.path;
    const frontend = try frontendFor(context, shown, location.extension);
    const source = try readScript(context, shown);
    var frontend_context: kosm.Frontend.Context = .{ .arena = context.arena, .path = shown, .variant = variant, .library = context.library };
    var loaded: kosm.Frontend.Error!kosm.Frontend.Script = undefined;
    try runOnKosmosStack(context, shown, runLoad, .{ frontend.load, &frontend_context, source, &loaded });
    const script = loaded catch |err| return frontendFailure(context, shown, &frontend_context, err);
    if (script.tree != null and (script.base != null or script.params != null or script.theme != null or script.overrides != null))
        return fail(context, "{s}: it returns a tree it built, so it may set nothing else; set values on the tree instead", .{shown});
    if (script.base == null and script.params != null)
        return fail(context, "{s}: it sets parameters but builds on no kosmos, so nothing takes them", .{shown});
    if (script.base != null and script.theme != null)
        return fail(context, "{s}: it sets a theme input but builds on '{s}', which builds its own theme; set the base's parameters or its theme's values instead", .{ shown, script.base.? });
    return .{ .name = name, .path = shown, .folder = try scriptFolder(context, shown), .script = script };
}

/// The absolute folder holding script `shown`.
fn scriptFolder(context: Context, shown: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.Io.Dir.path.dirname(try fullPath(context, shown)).?;
}

/// The absolute path of script `shown`: a package's root script, or one of the config's.
fn fullPath(context: Context, shown: []const u8) std.mem.Allocator.Error![]const u8 {
    for (context.packages) |package| {
        if (std.mem.eql(u8, package.path, shown)) return package.file;
    }
    return std.Io.Dir.path.join(context.arena, &.{ context.config, shown });
}

/// The text of script `shown`, which lives for the whole run. Relative paths the script gives
/// its calls start from its folder from now on.
fn readScript(context: Context, shown: []const u8) Error![]const u8 {
    const full_path = try fullPath(context, shown);
    if (context.calls_folder) |calls_folder| calls_folder.* = try scriptFolder(context, shown);
    return std.Io.Dir.cwd().readFileAlloc(context.io, full_path, context.arena, .limited(size_limit)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.StreamTooLong => return fail(context, "{s}: the file is larger than {d} MiB", .{ shown, size_limit / (1024 * 1024) }),
        else => return fail(context, "{s}: cannot read the file: {s}", .{ shown, @errorName(err) }),
    };
}

/// Runs `function` with `arguments` for script `shown` and waits for it. A script builds whole
/// kosmos trees by value through its calls, which outgrows a process' usual stack as a kosmos
/// does, so it runs on a stack as large as a kosmos'.
fn runOnKosmosStack(context: Context, shown: []const u8, comptime function: anytype, arguments: anytype) Error!void {
    const thread = std.Thread.spawn(.{ .stack_size = kosmos_call.kosmos_stack_size }, function, arguments) catch |err|
        return fail(context, "{s}: cannot start the thread the script runs on: {s}", .{ shown, @errorName(err) });
    thread.join();
}

/// The failure a frontend returned for script `shown`, with its message.
fn frontendFailure(context: Context, shown: []const u8, frontend_context: *const kosm.Frontend.Context, err: kosm.Frontend.Error) Error {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidScript => {
            const message = frontend_context.message orelse "the script cannot be read, and its frontend did not say why";
            if (std.mem.startsWith(u8, message, shown)) return fail(context, "{s}", .{message});
            return fail(context, "{s}: {s}", .{ shown, message });
        },
    }
}

fn runLoad(load_script: *const fn (*kosm.Frontend.Context, []const u8) kosm.Frontend.Error!kosm.Frontend.Script, context: *kosm.Frontend.Context, source: []const u8, loaded: *kosm.Frontend.Error!kosm.Frontend.Script) void {
    loaded.* = load_script(context, source);
}

fn runVariants(list: *const fn (*kosm.Frontend.Context, []const u8) kosm.Frontend.Error![]const []const u8, context: *kosm.Frontend.Context, source: []const u8, listed: *kosm.Frontend.Error![]const []const u8) void {
    listed.* = list(context, source);
}

/// The one frontend claiming `extension`.
fn frontendFor(context: Context, shown: []const u8, extension: []const u8) Error!kosm.Frontend {
    var found: ?discovery.DeclaredFrontend = null;
    for (context.frontends) |declared| {
        if (!declared.frontend.claims(extension)) continue;
        if (found) |first| return fail(context, "{s}: both package '{s}' ({s}) and package '{s}' ({s}) read '{s}' kosmoi; remove one of them", .{
            shown, first.package, first.frontend.name, declared.package, declared.frontend.name, extension,
        });
        found = declared;
    }
    if (found) |declared| return declared.frontend;
    return fail(context, "{s}: no installed package reads '{s}' kosmoi; frontends: {s}", .{ shown, extension, try frontendList(context) });
}

/// The installed frontends and their extensions, `lua (.lua)`, comma-separated, or "none".
fn frontendList(context: Context) std.mem.Allocator.Error![]const u8 {
    if (context.frontends.len == 0) return "none";
    var list: std.ArrayList(u8) = .empty;
    for (context.frontends, 0..) |declared, index| {
        if (index != 0) try list.appendSlice(context.arena, ", ");
        try list.print(context.arena, "{s} ({s})", .{ declared.frontend.name, try std.mem.join(context.arena, " ", declared.frontend.extensions) });
    }
    return list.items;
}

/// `loose`, naming `path` as where it was written unless its frontend named a place itself.
pub fn withOrigin(loose: kosm.Loose, path: []const u8) kosm.Loose {
    var named = loose;
    if (named.origin == null) named.origin = path;
    return named;
}

/// Whether `loose` is a table setting `key`.
pub fn setsKey(loose: kosm.Loose, key: []const u8) bool {
    const entries = switch (loose.value) {
        .table => |entries| entries,
        else => return false,
    };
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return true;
    }
    return false;
}

/// The tree of a kosmos building on no Zig kosmos, from `scripts` (the lowest first): the theme
/// is built from their theme inputs, each app any of their overrides names is built from it with
/// its module's `from` (`modules` holds one per field of `Tree`), and then the overrides are set.
pub fn standalone(comptime Tree: type, comptime modules: []const type, arena: std.mem.Allocator, scripts: []const Loaded, diagnostics: *kosm.Diagnostics) Error!Tree {
    var input: ?kosm.Theme.Input = null;
    for (scripts) |loaded| {
        const given = loaded.script.theme orelse continue;
        try assigned(kosm.assign(?kosm.Theme.Input, arena, &input, withOrigin(given, loaded.path), diagnostics));
    }
    var theme: ?kosm.Theme = null;
    var tree: Tree = .{};
    const field_names = @typeInfo(Tree).@"struct".field_names;
    for (scripts) |loaded| {
        const overrides = loaded.script.overrides orelse continue;
        // Anything but a table is reported by the assignment below.
        const entries = switch (overrides.value) {
            .table => |entries| entries,
            else => continue,
        };
        for (entries) |entry| {
            inline for (field_names, modules) |name, Module| {
                if (std.mem.eql(u8, entry.key, name) and @field(tree, name) == null) {
                    if (theme == null) {
                        const theme_input = input orelse {
                            diagnostics.set("", "", "{s}: it chooses the app '{s}' but sets no theme to build it from; give it a theme, or build on a kosmos", .{ loaded.path, name });
                            return error.Reported;
                        };
                        theme = kosm.Theme.from(theme_input);
                    }
                    kosm.failure.clear();
                    @field(tree, name) = Module.from(theme.?);
                    // An app's `from` cannot fail, so a script's failure in it is only recorded.
                    if (kosm.failure.message()) |message| {
                        diagnostics.set("", "", "{s}", .{message});
                        return error.Reported;
                    }
                }
            }
        }
    }
    for (scripts) |loaded| {
        const overrides = loaded.script.overrides orelse continue;
        try assigned(kosm.assign(Tree, arena, &tree, withOrigin(overrides, loaded.path), diagnostics));
    }
    return tree;
}

/// The result of an assignment, its failure already in the diagnostics.
fn assigned(result: kosm.assignment.Error!void) Error!void {
    result catch |err| switch (err) {
        error.InvalidAssignment => return error.Reported,
        error.OutOfMemory => return error.OutOfMemory,
    };
}

/// Every script kosmos in the config and at packages' roots, as `kosm apply` spells it, followed
/// by each variant it gives (`minimal`, `minimal.light`), each with its file as origin, in no
/// particular order of files. Listing variants runs no script.
pub fn listAll(context: Context) Error![]const KosmosName {
    var found: std.ArrayList(KosmosName) = .empty;
    for (context.packages) |package| try appendScript(context, &found, package.name, package.path);
    var top = try openKosmoiFolder(context, directory) orelse return found.items;
    defer top.close(context.io);
    var iterator = top.iterate();
    while (iterator.next(context.io) catch |err| return fail(context, "cannot read {s}/: {s}", .{ directory, @errorName(err) })) |entry| {
        if (entry.kind == .directory and !std.mem.startsWith(u8, entry.name, ".")) {
            try listFolder(context, &found, try context.arena.dupe(u8, entry.name));
        } else if (try scriptStem(context, entry)) |stem| {
            const path = try context.arena.print("{s}/{s}", .{ directory, entry.name });
            if (!isExporting(context, path)) try appendScript(context, &found, stem, path);
        }
    }
    return found.items;
}

/// The scripts of kosmos folder `name` into `found`: its root as `name`, the others as variants.
fn listFolder(context: Context, found: *std.ArrayList(KosmosName), name: []const u8) Error!void {
    const folder = try context.arena.print("{s}/{s}", .{ directory, name });
    var dir = try openKosmoiFolder(context, folder) orelse return;
    defer dir.close(context.io);
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return fail(context, "cannot read {s}/: {s}", .{ folder, @errorName(err) })) |entry| {
        const stem = try scriptStem(context, entry) orelse continue;
        const kosmos = if (std.mem.eql(u8, stem, root_name)) name else try context.arena.print("{s}.{s}", .{ name, stem });
        const path = try context.arena.print("{s}/{s}", .{ folder, entry.name });
        if (!isExporting(context, path)) try appendScript(context, found, kosmos, path);
    }
}

/// The config's folder `folder` opened for iterating, or null when it does not exist.
fn openKosmoiFolder(context: Context, folder: []const u8) Error!?std.Io.Dir {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, folder });
    return std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => null,
        else => fail(context, "cannot read {s}/: {s}", .{ folder, @errorName(err) }),
    };
}

/// The name of the script `entry` before its extension, or null when it is no script.
fn scriptStem(context: Context, entry: std.Io.Dir.Entry) std.mem.Allocator.Error!?[]const u8 {
    if (entry.kind != .file and entry.kind != .sym_link) return null;
    const dot = std.mem.findScalar(u8, entry.name, '.') orelse return null;
    if (dot == 0 or !isScriptOf(entry.name, entry.name[0..dot])) return null;
    return try context.arena.dupe(u8, entry.name[0..dot]);
}

/// Appends script kosmos `name` at `path` and the variants its frontend lists.
fn appendScript(context: Context, found: *std.ArrayList(KosmosName), name: []const u8, path: []const u8) Error!void {
    try found.append(context.arena, .{ .name = name, .origin = path });
    const file_name = std.Io.Dir.path.basename(path);
    const frontend = try frontendFor(context, path, file_name[std.mem.findScalar(u8, file_name, '.').?..]);
    const list = frontend.variants orelse return;
    const source = try readScript(context, path);
    var frontend_context: kosm.Frontend.Context = .{ .arena = context.arena, .path = path, .library = context.library };
    var listed: kosm.Frontend.Error![]const []const u8 = undefined;
    try runOnKosmosStack(context, path, runVariants, .{ list, &frontend_context, source, &listed });
    const given = listed catch |err| return frontendFailure(context, path, &frontend_context, err);
    for (given) |variant| try found.append(context.arena, .{ .name = try context.arena.print("{s}.{s}", .{ name, variant }), .origin = path });
}

fn fail(context: Context, comptime format: []const u8, arguments: anytype) Error {
    context.diagnostics.set("", "", format, arguments);
    return error.Reported;
}

const testing = std.testing;

/// A frontend for tests reading one setting per line: `base frost`, `param blur=false`,
/// `theme mode=dark` or `set kitty.size=3`, values read like `--set`'s; `fail` fails at its line,
/// `tree` returns `test_tree`, `variants` builds on the kosmos the variant names, and
/// `gives light` lists `light` among its variants.
const test_frontend: kosm.Frontend = .{ .name = "lines", .extensions = &.{".kosmos"}, .load = loadLines, .variants = listLines };

fn listLines(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "gives ")) try names.append(context.arena, line["gives ".len..]);
    }
    return names.items;
}

fn loadLines(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.Script {
    var result: kosm.Frontend.Script = .{};
    var params_entries: std.ArrayList(kosm.Loose.Entry) = .empty;
    var theme_entries: std.ArrayList(kosm.Loose.Entry) = .empty;
    var override_entries: std.ArrayList(kosm.Loose.Entry) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 0;
    var has_variants = false;
    while (lines.next()) |line| {
        line_number += 1;
        if (line.len == 0) continue;
        const space = std.mem.findScalar(u8, line, ' ') orelse line.len;
        const keyword = line[0..space];
        const rest = if (space == line.len) "" else line[space + 1 ..];
        if (std.mem.eql(u8, keyword, "base")) {
            result.base = rest;
            continue;
        }
        if (std.mem.eql(u8, keyword, "variants")) {
            has_variants = true;
            result.base = try std.mem.join(context.arena, ".", context.variant);
            continue;
        }
        if (std.mem.eql(u8, keyword, "gives")) continue;
        if (std.mem.eql(u8, keyword, "tree")) {
            result.tree = .{ .pointer = &test_tree, .type = &test_tree_type };
            continue;
        }
        if (std.mem.eql(u8, keyword, "fail")) return context.fail("{s}: {s}", .{ try context.at(line_number), rest });
        const entries = if (std.mem.eql(u8, keyword, "param")) &params_entries else if (std.mem.eql(u8, keyword, "theme")) &theme_entries else if (std.mem.eql(u8, keyword, "set")) &override_entries else return context.fail("{s}: unknown keyword '{s}'", .{ try context.at(line_number), keyword });
        const equals = std.mem.findScalar(u8, rest, '=') orelse return context.fail("unreadable line {d}", .{line_number});
        try entries.append(context.arena, try nestedEntry(context.arena, rest[0..equals], .{ .value = .{ .text = rest[equals + 1 ..] }, .origin = try context.at(line_number) }));
    }
    if (context.variant.len != 0 and !has_variants) return context.fail("it has no variants", .{});
    if (params_entries.items.len != 0) result.params = .{ .value = .{ .table = params_entries.items } };
    if (theme_entries.items.len != 0) result.theme = .{ .value = .{ .table = theme_entries.items } };
    if (override_entries.items.len != 0) result.overrides = .{ .value = .{ .table = override_entries.items } };
    return result;
}

var test_tree: u8 = 0;
const test_tree_type: kosm.Frontend.Handle.Type = .{ .id = kosm.Frontend.Handle.id(u8), .name = "u8", .get = undefined, .set = undefined, .length = undefined };

/// `a.b` and `leaf` as the entry `a = { b = leaf }`.
fn nestedEntry(arena: std.mem.Allocator, path: []const u8, leaf: kosm.Loose) std.mem.Allocator.Error!kosm.Loose.Entry {
    const dot = std.mem.findScalar(u8, path, '.') orelse return .{ .key = path, .value = leaf };
    const inner = try arena.dupe(kosm.Loose.Entry, &.{try nestedEntry(arena, path[dot + 1 ..], leaf)});
    return .{ .key = path[0..dot], .value = .{ .value = .{ .table = inner } } };
}

/// A config folder holding `files` in `kosmoi/`, and a context resolving in it.
const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    diagnostics: kosm.Diagnostics = .{ .kosmos = "test" },
    config: []const u8 = "",

    fn init(fixture: *Fixture, files: []const [2][]const u8) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator) };
        try fixture.tmp.dir.createDirPath(testing.io, directory);
        for (files) |file| {
            const sub_path = try fixture.arena.allocator().print("{s}/{s}", .{ directory, file[0] });
            try fixture.tmp.dir.createDirPath(testing.io, std.Io.Dir.path.dirname(sub_path).?);
            try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = sub_path, .data = file[1] });
        }
        fixture.config = try fixture.tmp.dir.realPathFileAlloc(testing.io, ".", fixture.arena.allocator());
    }

    fn deinit(fixture: *Fixture) void {
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn context(fixture: *Fixture) Context {
        return .{
            .arena = fixture.arena.allocator(),
            .io = testing.io,
            .config = fixture.config,
            .frontends = &.{.{ .package = "kosm_lines", .frontend = test_frontend }},
            .modules = &.{ "frost", "kosm_kitty", "snow" },
            .kosmoi = &.{
                .{ .name = "frost", .origin = "kosmoi/frost/" },
                .{ .name = "frost.iced", .origin = "kosmoi/frost/" },
                .{ .name = "frost.cold.deep", .origin = "kosmoi/frost/" },
                .{ .name = "snow.iced", .origin = "kosmoi/snow/" },
                .{ .name = "snow.cold.deep", .origin = "kosmoi/snow/" },
            },
            .diagnostics = &fixture.diagnostics,
        };
    }

    fn expectFailure(fixture: *Fixture, name: []const u8, expected_message: []const u8) !void {
        try testing.expectError(error.Reported, resolve(fixture.context(), name));
        try testing.expectEqualStrings(expected_message, fixture.diagnostics.message());
    }
};

test "a script found by its name is read through the frontend claiming its extension" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "mine.kosmos", "base frost.iced\nparam blur=false\nset kitty.size=3\n" }, .{ "frost.zig", "" }, .{ ".hidden.kosmos", "" } });
    defer fixture.deinit();

    const chain = try resolve(fixture.context(), "mine");
    try testing.expectEqualStrings("frost.iced", chain.base.?);
    try testing.expectEqual(1, chain.scripts.len);
    try testing.expectEqualStrings("kosmoi/mine.kosmos", chain.scripts[0].path);
    try testing.expectEqualStrings("blur", chain.scripts[0].script.params.?.value.table[0].key);
    try testing.expectEqualStrings("kosmoi/mine.kosmos:3", chain.scripts[0].script.overrides.?.value.table[0].value.value.table[0].value.origin.?);
    try testing.expectEqual(null, try locate(fixture.context(), "frost"));
    try testing.expectEqual(null, try locate(fixture.context(), "hidden"));
}

test "a package's root script gives the kosmos named after the package, read from its folder" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ "mine.kosmos", "base kosm_glacier.light\nset kitty.size=4\n" },
        .{ "kosm_ice.kosmos", "" },
    });
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "packages/kosm_glacier");
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "packages/kosm_glacier/root.kosmos", .data = "variants\ngives light\nparam wallpaper=walls/ice.png\n" });
    const folder = try std.Io.Dir.path.join(fixture.arena.allocator(), &.{ fixture.config, "packages/kosm_glacier" });
    var context = fixture.context();
    context.modules = &.{ "frost", "kosm_glacier", "kosm_ice" };
    context.packages = &.{
        .{ .name = "kosm_glacier", .path = "~~kosm_glacier/root.kosmos", .file = try std.Io.Dir.path.join(fixture.arena.allocator(), &.{ folder, "root.kosmos" }) },
    };

    // A script builds on a package's kosmos, here one of its variants, which builds on frost.
    const chain = try resolve(context, "mine");
    try testing.expectEqual(2, chain.scripts.len);
    try testing.expectEqualStrings("kosm_glacier.light", chain.scripts[0].name);
    try testing.expectEqualStrings("~~kosm_glacier/root.kosmos", chain.scripts[0].path);
    try testing.expectEqualStrings(folder, chain.scripts[0].folder);
    try testing.expectEqualStrings("light", chain.base.?);
    const listed = try listAll(context);
    try testing.expectEqualStrings("kosm_glacier", listed[0].name);
    try testing.expectEqualStrings("kosm_glacier.light", listed[1].name);
    try testing.expectEqualStrings("~~kosm_glacier/root.kosmos", listed[1].origin);
    // A script of the config sharing a package kosmos' name fails naming both.
    context.packages = &.{.{ .name = "kosm_ice", .path = "~~kosm_ice/root.kosmos", .file = "/nowhere/root.kosmos" }};
    try testing.expectError(error.Reported, locate(context, "kosm_ice"));
    try testing.expectEqualStrings("'kosm_ice' names both kosmoi/kosm_ice.kosmos and the kosmos of package 'kosm_ice' (~~kosm_ice/root.kosmos); rename one", fixture.diagnostics.message());
}

test "a script in a kosmos' folder is that kosmos' variant, read from its own folder" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ "frost/root.zig", "" },
        .{ "frost/build.zig.zon", "" },
        .{ "frost/nord.kosmos", "base frost\nset kitty.size=3\n" },
        .{ "frost/deep.kosmos", "variants\n" },
        .{ "top.kosmos", "base frost.nord\n" },
    });
    defer fixture.deinit();

    const chain = try resolve(fixture.context(), "top");
    try testing.expectEqualStrings("frost", chain.base.?);
    try testing.expectEqualStrings("frost.nord", chain.scripts[0].name);
    try testing.expectEqualStrings("kosmoi/frost/nord.kosmos", chain.scripts[0].path);
    try testing.expect(std.mem.endsWith(u8, chain.scripts[0].folder, "/kosmoi/frost"));
    try testing.expect(std.mem.endsWith(u8, chain.scripts[1].folder, "/kosmoi"));
    // A function variant of a script in a folder, which here builds on the kosmos it names.
    const variant = try resolve(fixture.context(), "frost.deep.frost.iced");
    try testing.expectEqualStrings("frost.iced", variant.base.?);
    try testing.expectEqualStrings("kosmoi/frost/deep.kosmos", variant.scripts[0].path);
    try testing.expectEqual(null, try locate(fixture.context(), "frost.build"));
    try testing.expectEqual(null, try locate(fixture.context(), "frost.root"));
    try testing.expectEqual(null, try locate(fixture.context(), "missing.nord"));
}

test "a script in a kosmos' folder sharing a name with a Zig variant, a group or a script variant fails naming both" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ "frost/iced.kosmos", "" },
        .{ "frost/cold.kosmos", "" },
        .{ "frost/twice.kosmos", "" },
        .{ "frost/twice.toml", "" },
        .{ "mine.kosmos", "variants\ngives dark\n" },
        .{ "mine/dark.kosmos", "" },
        .{ "other.kosmos", "variants\ngives light\n" },
        .{ "other/dark.kosmos", "base frost\n" },
    });
    defer fixture.deinit();
    try fixture.expectFailure("frost.iced", "'frost.iced' names both kosmoi/frost/iced.kosmos and a kosmos of kosmoi/frost/; rename one");
    try fixture.expectFailure("frost.cold", "'frost.cold' names both kosmoi/frost/cold.kosmos and a kosmos of kosmoi/frost/; rename one");
    try testing.expectError(error.Reported, resolve(fixture.context(), "frost.twice"));
    try testing.expect(std.mem.startsWith(u8, fixture.diagnostics.message(), "'frost.twice' names both kosmoi/frost/twice."));
    try fixture.expectFailure("mine.dark", "'mine.dark' names both a variant of kosmoi/mine.kosmos and kosmoi/mine/dark.kosmos; rename one");
    // A script in the folder of a script without that variant is the variant.
    try testing.expectEqualStrings("kosmoi/other/dark.kosmos", (try resolve(fixture.context(), "other.dark")).scripts[0].path);
}

test "a folder's root script gives its kosmos, and the Zig variants beside it win their names" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ "snow/root.zig", "" },
        .{ "snow/root.kosmos", "base frost\n" },
        .{ "snow/nord.kosmos", "base snow.iced\n" },
        .{ "bare/root.kosmos", "variants\ngives light\n" },
    });
    defer fixture.deinit();

    const own = try resolve(fixture.context(), "snow");
    try testing.expectEqualStrings("frost", own.base.?);
    try testing.expectEqualStrings("kosmoi/snow/root.kosmos", own.scripts[0].path);
    try testing.expect(std.mem.endsWith(u8, own.scripts[0].folder, "/kosmoi/snow"));
    try testing.expectEqual(null, try locate(fixture.context(), "snow.iced"));
    try testing.expectEqualStrings("snow.iced", (try resolve(fixture.context(), "snow.nord")).base.?);
    // A folder without root.zig holds a script kosmos and its variants alone.
    const variant = try resolve(fixture.context(), "bare.frost.iced");
    try testing.expectEqualStrings("frost.iced", variant.base.?);
    try testing.expectEqualStrings("kosmoi/bare/root.kosmos", variant.scripts[0].path);
}

test "a root script sharing a name with its folder's Zig kosmos, a variant or another script fails naming both" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ "frost/root.zig", "" },
        .{ "frost/root.kosmos", "base kosm_kitty\n" },
        .{ "snow/root.zig", "" },
        .{ "snow/root.kosmos", "variants\ngives iced\ngives cold\n" },
        .{ "hail.kosmos", "" },
        .{ "hail/root.kosmos", "" },
    });
    defer fixture.deinit();
    try fixture.expectFailure("frost", "'frost' names both kosmoi/frost/root.kosmos and the kosmos of kosmoi/frost/; only one root of a folder gives its kosmos");
    try fixture.expectFailure("snow.iced", "'snow.iced' names both a variant of kosmoi/snow/root.kosmos and a kosmos of kosmoi/snow/; rename one");
    try fixture.expectFailure("snow.cold", "'snow.cold.deep' names both a variant of kosmoi/snow/root.kosmos and a kosmos of kosmoi/snow/; rename one");
    try fixture.expectFailure("snow.cold.deep", "'snow.cold' names both a variant of kosmoi/snow/root.kosmos and a kosmos of kosmoi/snow/; rename one");
    try fixture.expectFailure("hail", "'hail' names both kosmoi/hail.kosmos and kosmoi/hail/root.kosmos; rename one");
}

test "a script exporting values is no script kosmos: its folder's other scripts are the module's variants" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ "frost/root.kosmos", "variants\ngives light\n" },
        .{ "frost/nord.kosmos", "base frost.light\n" },
        .{ "glow.kosmos", "" },
    });
    defer fixture.deinit();
    var context = fixture.context();
    context.exporting = &.{ "kosmoi/frost/root.kosmos", "kosmoi/glow.kosmos" };
    context.kosmoi = &.{ .{ .name = "frost", .origin = "kosmoi/frost/" }, .{ .name = "frost.light", .origin = "kosmoi/frost/" } };

    try testing.expectEqual(null, try locate(context, "frost"));
    try testing.expectEqual(null, try locate(context, "frost.light"));
    try testing.expectEqual(null, try locate(context, "glow"));
    const variant = try resolve(context, "frost.nord");
    try testing.expectEqualStrings("frost.light", variant.base.?);
    try testing.expectEqualStrings("kosmoi/frost/nord.kosmos", variant.scripts[0].path);
    const listed = try listAll(context);
    try testing.expectEqual(1, listed.len);
    try testing.expectEqualStrings("frost.nord", listed[0].name);
}

test "scripts building on scripts are read down to the Zig kosmos, the lowest first" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "top.kosmos", "base middle\nset kitty.size=3\n" }, .{ "middle.kosmos", "base frost\n" } });
    defer fixture.deinit();

    const chain = try resolve(fixture.context(), "top");
    try testing.expectEqualStrings("frost", chain.base.?);
    try testing.expectEqualStrings("middle", chain.scripts[0].name);
    try testing.expectEqualStrings("top", chain.scripts[1].name);
}

test "a variant of a script is built by its frontend, and a returned tree ends the chain" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "mine.kosmos", "variants\n" }, .{ "built.kosmos", "tree\n" }, .{ "on.kosmos", "base built\nset kitty.size=3\n" }, .{ "both.kosmos", "tree\nset kitty.size=3\n" } });
    defer fixture.deinit();

    const variant = try resolve(fixture.context(), "mine.frost.iced");
    try testing.expectEqualStrings("frost.iced", variant.base.?);
    try testing.expectEqualStrings("mine.frost.iced", variant.scripts[0].name);
    const built = try resolve(fixture.context(), "on");
    try testing.expectEqual(null, built.base);
    try testing.expect(built.tree.?.pointer == @as(*anyopaque, &test_tree));
    try testing.expectEqualStrings("built", built.scripts[0].name);
    try fixture.expectFailure("both", "kosmoi/both.kosmos: it returns a tree it built, so it may set nothing else; set values on the tree instead");
}

test "a script without a base ends the chain on none" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "alone.kosmos", "theme mode=dark\nset kitty.size=3\n" }, .{ "on.kosmos", "base alone\n" } });
    defer fixture.deinit();

    const chain = try resolve(fixture.context(), "on");
    try testing.expectEqual(null, chain.base);
    try testing.expectEqual(2, chain.scripts.len);
}

test "scripts building on each other in a circle fail naming the circle" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "a.kosmos", "base b\n" }, .{ "b.kosmos", "base a\n" } });
    defer fixture.deinit();
    try fixture.expectFailure("a", "the kosmoi build on each other in a circle: a -> b -> a");
}

test "a script sharing its name with a Zig module or another script fails naming both" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "frost.kosmos", "" }, .{ "twice.kosmos", "" }, .{ "twice.toml", "" } });
    defer fixture.deinit();
    try fixture.expectFailure("frost", "'frost' names both kosmoi/frost.kosmos and the Zig module 'frost'; rename one");
    try testing.expectError(error.Reported, resolve(fixture.context(), "twice"));
    try testing.expect(std.mem.startsWith(u8, fixture.diagnostics.message(), "'twice' names both kosmoi/twice."));
}

test "an extension no frontend claims fails listing the frontends" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{.{ "mine.toml", "" }});
    defer fixture.deinit();
    try fixture.expectFailure("mine", "kosmoi/mine.toml: no installed package reads '.toml' kosmoi; frontends: lines (.kosmos)");
}

test "a frontend's failure names the script, and its line when the frontend gives one" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "at.kosmos", "base frost\nfail gaps_in: expected an integer\n" }, .{ "plain.kosmos", "nonsense\n" } });
    defer fixture.deinit();
    try fixture.expectFailure("at", "kosmoi/at.kosmos:2: gaps_in: expected an integer");
    try fixture.expectFailure("plain", "kosmoi/plain.kosmos:1: unknown keyword 'nonsense'");
}

test "a script without a base may not set parameters, one with a base no theme input" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "params.kosmos", "param blur=false\n" }, .{ "theme.kosmos", "base frost\ntheme mode=dark\n" }, .{ "variant.kosmos", "" } });
    defer fixture.deinit();
    try fixture.expectFailure("params", "kosmoi/params.kosmos: it sets parameters but builds on no kosmos, so nothing takes them");
    try fixture.expectFailure("theme", "kosmoi/theme.kosmos: it sets a theme input but builds on 'frost', which builds its own theme; set the base's parameters or its theme's values instead");
    try fixture.expectFailure("variant.deep", "kosmoi/variant.kosmos: it has no variants");
    try fixture.expectFailure("missing", "there is no script kosmos 'missing' in kosmoi/");
}

const TestApp = struct {
    size: u8 = 0,
    background: ?kosm.Color = null,

    pub fn apply(self: TestApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

const test_app_module = struct {
    pub const App = TestApp;
    pub fn from(theme: kosm.Theme) App {
        return .{ .background = theme.roles.background };
    }
};

const TestTree = discovery.Standalone(&.{ .{ .package = "kosm_kitty", .module = test_app_module }, .{ .package = "my_bar", .module = test_app_module } });

test "a kosmos without a base builds the apps it names from its theme, and leaves out the rest" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "alone.kosmos", "theme palette.black=#000000\ntheme palette.white=#ffffff\ntheme mode=light\nset kitty.size=3\n" }, .{ "on.kosmos", "base alone\nset kitty.size=4\n" } });
    defer fixture.deinit();

    const chain = try resolve(fixture.context(), "on");
    const tree = try standalone(TestTree, &.{ test_app_module, test_app_module }, fixture.arena.allocator(), chain.scripts, &fixture.diagnostics);
    try testing.expectEqual(4, tree.kitty.?.size);
    try testing.expectEqualStrings("#ffffff", tree.kitty.?.background.?.hex().slice());
    try testing.expectEqual(null, tree.my_bar);
}

test "a kosmos without a base naming an app but no theme fails naming the app" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{ .{ "alone.kosmos", "set my_bar.size=3\n" }, .{ "unknown.kosmos", "set nope.size=3\n" } });
    defer fixture.deinit();

    const chain = try resolve(fixture.context(), "alone");
    try testing.expectError(error.Reported, standalone(TestTree, &.{ test_app_module, test_app_module }, fixture.arena.allocator(), chain.scripts, &fixture.diagnostics));
    try testing.expectEqualStrings("kosmoi/alone.kosmos: it chooses the app 'my_bar' but sets no theme to build it from; give it a theme, or build on a kosmos", fixture.diagnostics.message());

    const unknown = try resolve(fixture.context(), "unknown");
    try testing.expectError(error.Reported, standalone(TestTree, &.{ test_app_module, test_app_module }, fixture.arena.allocator(), unknown.scripts, &fixture.diagnostics));
    try testing.expectEqualStrings("kosmoi/unknown.kosmos: the kosmos: no field 'nope'; its fields are kitty, my_bar", fixture.diagnostics.message());
}

test "every script and the variants it gives are listed, with their files" {
    var fixture: Fixture = undefined;
    try fixture.init(&.{
        .{ "frost/root.zig", "" },
        .{ "frost/build.zig.zon", "" },
        .{ "frost/nord.kosmos", "base frost\n" },
        .{ "bare/root.kosmos", "variants\ngives light\ngives dark.soft\n" },
        .{ "mine.kosmos", "base frost\n" },
        .{ "frost.zig", "" },
        .{ ".hidden.kosmos", "" },
    });
    defer fixture.deinit();

    const listed = try listAll(fixture.context());
    var lines: std.ArrayList([]const u8) = .empty;
    for (listed) |kosmos| try lines.append(fixture.arena.allocator(), try fixture.arena.allocator().print("{s} {s}", .{ kosmos.name, kosmos.origin }));
    std.mem.sort([]const u8, lines.items, {}, lessThan);
    try testing.expectEqualStrings(
        "bare kosmoi/bare/root.kosmos\nbare.dark.soft kosmoi/bare/root.kosmos\nbare.light kosmoi/bare/root.kosmos\nfrost.nord kosmoi/frost/nord.kosmos\nmine kosmoi/mine.kosmos",
        try std.mem.join(fixture.arena.allocator(), "\n", lines.items),
    );
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
