//! Finds a script kosmos in the config's `kosmoi/`, reads it through the frontend claiming its
//! extension, and follows what it builds on through other scripts down to a Zig kosmos or to none.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");

/// Where script kosmoi live, in the config's root.
pub const directory = "kosmoi";
/// Zig kosmoi in `directory` are modules, never scripts.
const zig_extension = ".zig";
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
    diagnostics: *kosm.Diagnostics,
};

/// One script read by its frontend.
pub const Loaded = struct {
    /// As `kosm apply` spells it: "minimal".
    name: []const u8,
    /// As messages show it: "kosmoi/minimal.lua".
    path: []const u8,
    script: kosm.Frontend.Script,
};

/// A script kosmos and everything it builds on.
pub const Chain = struct {
    /// The Zig kosmos at the bottom ("personal", "frost.iced"), or null when the bottom script
    /// has no base.
    base: ?[]const u8,
    /// Every script, the one building on the base first and the applied one last.
    scripts: []const Loaded,
};

/// The file name of script kosmos `name` in `directory` ("minimal.lua"), or null when there is
/// none. Two scripts of that name fail.
pub fn find(context: Context, name: []const u8) Error!?[]const u8 {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, directory });
    var dir = std.Io.Dir.cwd().openDir(context.io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return fail(context, "cannot read {s}/: {s}", .{ directory, @errorName(err) }),
    };
    defer dir.close(context.io);
    var found: ?[]const u8 = null;
    var iterator = dir.iterate();
    while (iterator.next(context.io) catch |err| return fail(context, "cannot read {s}/: {s}", .{ directory, @errorName(err) })) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!isScriptOf(entry.name, name)) continue;
        if (found) |first| return fail(context, "'{s}' names both {s}/{s} and {s}/{s}; rename one", .{ name, directory, first, directory, entry.name });
        found = try context.arena.dupe(u8, entry.name);
    }
    return found;
}

/// Whether `file_name` is a script kosmos named `name`: `name`, a dot, and any extension but Zig's.
fn isScriptOf(file_name: []const u8, name: []const u8) bool {
    if (name.len == 0 or std.mem.startsWith(u8, file_name, ".")) return false;
    if (!std.mem.startsWith(u8, file_name, name) or file_name.len <= name.len + 1) return false;
    if (file_name[name.len] != '.') return false;
    return !std.mem.eql(u8, file_name[name.len..], zig_extension);
}

/// Reads the script kosmos `name` and every script below it.
pub fn resolve(context: Context, name: []const u8) Error!Chain {
    var visited: std.ArrayList([]const u8) = .empty;
    var loaded: std.ArrayList(Loaded) = .empty;
    var current = name;
    const base: ?[]const u8 = while (true) {
        for (visited.items) |earlier| {
            if (std.mem.eql(u8, earlier, current)) {
                try visited.append(context.arena, current);
                return fail(context, "the kosmoi build on each other in a circle: {s}", .{try std.mem.join(context.arena, " -> ", visited.items)});
            }
        }
        try visited.append(context.arena, current);
        const dot = std.mem.findScalar(u8, current, '.');
        const file_part = current[0 .. dot orelse current.len];
        const file_name = try find(context, file_part) orelse {
            if (loaded.items.len == 0) return fail(context, "there is no script kosmos '{s}' in {s}/", .{ current, directory });
            break current;
        };
        if (dot != null) return fail(context, "'{s}': {s}/{s} is a script, and script kosmoi have no variants", .{ current, directory, file_name });
        for (context.modules) |module| {
            if (std.mem.eql(u8, module, file_part)) return fail(context, "'{s}' names both {s}/{s} and the Zig module '{s}'; rename one", .{ file_part, directory, file_name, module });
        }
        const script = try load(context, file_part, file_name);
        try loaded.append(context.arena, script);
        current = script.script.base orelse break null;
    };
    std.mem.reverse(Loaded, loaded.items);
    return .{ .base = base, .scripts = loaded.items };
}

/// Reads `file_name` in `directory` through the frontend claiming its extension.
fn load(context: Context, name: []const u8, file_name: []const u8) Error!Loaded {
    const shown = try context.arena.print("{s}/{s}", .{ directory, file_name });
    const extension = file_name[name.len..];
    const frontend = try frontendFor(context, shown, extension);
    const full_path = try std.Io.Dir.path.join(context.arena, &.{ context.config, shown });
    const source = std.Io.Dir.cwd().readFileAlloc(context.io, full_path, context.arena, .limited(size_limit)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.StreamTooLong => return fail(context, "{s}: the file is larger than {d} MiB", .{ shown, size_limit / (1024 * 1024) }),
        else => return fail(context, "{s}: cannot read the file: {s}", .{ shown, @errorName(err) }),
    };
    var frontend_context: kosm.Frontend.Context = .{ .arena = context.arena, .path = shown };
    const script = frontend.load(&frontend_context, source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidScript => {
            const message = frontend_context.message orelse "the script cannot be read, and its frontend did not say why";
            if (std.mem.startsWith(u8, message, shown)) return fail(context, "{s}", .{message});
            return fail(context, "{s}: {s}", .{ shown, message });
        },
    };
    if (script.base == null and script.params != null)
        return fail(context, "{s}: it sets parameters but builds on no kosmos, so nothing takes them", .{shown});
    if (script.base != null and script.theme != null)
        return fail(context, "{s}: it sets a theme input but builds on '{s}', which builds its own theme; set the base's parameters or its theme's values instead", .{ shown, script.base.? });
    return .{ .name = name, .path = shown, .script = script };
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
                    @field(tree, name) = Module.from(theme.?);
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

fn fail(context: Context, comptime format: []const u8, arguments: anytype) Error {
    context.diagnostics.set("", "", format, arguments);
    return error.Reported;
}

const testing = std.testing;

/// A frontend for tests reading one setting per line: `base frost`, `param blur=false`,
/// `theme mode=dark` or `set kitty.size=3`, values read like `--set`'s; `fail` fails at its line.
const test_frontend: kosm.Frontend = .{ .name = "lines", .extensions = &.{".kosmos"}, .load = loadLines };

fn loadLines(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.Script {
    var result: kosm.Frontend.Script = .{};
    var params_entries: std.ArrayList(kosm.Loose.Entry) = .empty;
    var theme_entries: std.ArrayList(kosm.Loose.Entry) = .empty;
    var override_entries: std.ArrayList(kosm.Loose.Entry) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 0;
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
        if (std.mem.eql(u8, keyword, "fail")) return context.fail("{s}: {s}", .{ try context.at(line_number), rest });
        const entries = if (std.mem.eql(u8, keyword, "param")) &params_entries else if (std.mem.eql(u8, keyword, "theme")) &theme_entries else if (std.mem.eql(u8, keyword, "set")) &override_entries else return context.fail("{s}: unknown keyword '{s}'", .{ try context.at(line_number), keyword });
        const equals = std.mem.findScalar(u8, rest, '=') orelse return context.fail("unreadable line {d}", .{line_number});
        try entries.append(context.arena, try nestedEntry(context.arena, rest[0..equals], .{ .value = .{ .text = rest[equals + 1 ..] }, .origin = try context.at(line_number) }));
    }
    if (params_entries.items.len != 0) result.params = .{ .value = .{ .table = params_entries.items } };
    if (theme_entries.items.len != 0) result.theme = .{ .value = .{ .table = theme_entries.items } };
    if (override_entries.items.len != 0) result.overrides = .{ .value = .{ .table = override_entries.items } };
    return result;
}

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
        for (files) |file| try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = try fixture.arena.allocator().print("{s}/{s}", .{ directory, file[0] }), .data = file[1] });
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
            .modules = &.{ "frost", "kosm_kitty" },
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
    try testing.expectEqual(null, try find(fixture.context(), "frost"));
    try testing.expectEqual(null, try find(fixture.context(), "hidden"));
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
    try fixture.expectFailure("variant.deep", "'variant.deep': kosmoi/variant.kosmos is a script, and script kosmoi have no variants");
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
