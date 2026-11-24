//! `kosm list`: every kosmos in a config with its variants and where it comes from, and
//! every installed package with what it provides, all found by reflection at compile time.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const kosmos_call = @import("kosmos_call.zig");
const inspect = @import("inspect.zig");
const hosting = @import("hosting.zig");
const interface = @import("kosm_interface");
const kosmos_names = @import("kosm_names");

/// A module the list looks into, filled in by the main that `addConfigProject` generates.
pub const Source = struct {
    /// The import name: "frost" or "kosm_kitty".
    name: []const u8,
    /// For the listing: "kosmoi/frost.zig" or "package kosm_kitty".
    origin: []const u8,
    kind: Kind,
    module: type,

    /// A local kosmos, app or adapter, or an installed package.
    pub const Kind = enum { local, package };
};

/// A script kosmos in the config's `kosmoi/`, filled in by the generated main. What its tree
/// holds is known only once its frontend reads it.
pub const Script = struct {
    /// As `kosm apply` spells it: "minimal".
    name: []const u8,
    /// Its file: "kosmoi/minimal.lua".
    origin: []const u8,
};

/// Prints the listing for the process arguments (`[kosmos] [--config dir] [--script-kosmos name
/// file]...`) and returns the exit status: 0, or 1 after printing what went wrong.
pub fn list(init: std.process.Init, comptime sources: []const Source, comptime scripts: []const Script) !u8 {
    const declared = comptime collect(sources, scripts);
    const arena = init.arena.allocator();
    const arguments = try init.minimal.args.toSlice(arena);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
    if (!try interface.check(init.environ_map, &stderr.interface)) {
        try stderr.interface.flush();
        return 1;
    }

    const parsed = parseArguments(arena, arguments[1..]) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnexpectedArgument => {
            try stderr.interface.writeAll("error: kosm list takes at most one kosmos, e.g. kosm list frost, or the kinds to list: --kosmoi, --apps, --adapters, --frontends, --packages\n");
            try stderr.interface.flush();
            return 1;
        },
    };
    const table: Table = .{
        .kosmoi = try withScriptKosmoi(arena, declared.kosmoi, parsed.script_kosmoi),
        .packages = declared.packages,
        .locals = declared.locals,
        .frontends = try frontendsOf(arena, parsed.frontends, sources),
    };

    if (init.environ_map.get(interface.runner_variable) != null) {
        try table.writeBuildingOnKosmoi(&stdout.interface);
        try stdout.interface.flush();
        return 0;
    }
    if (init.environ_map.get(interface.completions_variable) != null) {
        try table.writeCompletions(&stdout.interface);
        try stdout.interface.flush();
        return 0;
    }

    const status: u8 = status: {
        if (parsed.filter) |name| {
            table.writeKosmos(name, &stdout.interface) catch |err| switch (err) {
                error.UnknownKosmos => {
                    try stderr.interface.writeAll("error: ");
                    try kosmos_names.writeUnknown(&stderr.interface, name, try table.nameList(arena));
                    try stderr.interface.writeAll("\n");
                    break :status 1;
                },
                error.WriteFailed => return error.WriteFailed,
            };
        } else if (parsed.kinds.count() > 0) {
            try table.writeKinds(arena, parsed.kinds, &stdout.interface);
        } else try table.writeAll(&stdout.interface);
        break :status 0;
    };
    try stdout.interface.flush();
    try stderr.interface.flush();
    return status;
}

/// What the lister's arguments ask for.
const Parsed = struct {
    /// The one kosmos to list, or null for everything.
    filter: ?[]const u8 = null,
    /// The script kosmoi and variants the command line got from the runner of scripts.
    script_kosmoi: []const Kosmos = &.{},
    /// The kinds to list alone; none lists everything.
    kinds: Kinds = .{},
    /// The frontends the command line got from the runner of scripts, by the module giving each.
    frontends: []const Row = &.{},
};

/// The kinds `kosm list` lists alone, each asked for by its flag (`--apps`).
pub const Kinds = struct {
    kosmoi: bool = false,
    apps: bool = false,
    adapters: bool = false,
    frontends: bool = false,
    packages: bool = false,

    /// How many kinds are asked for.
    pub fn count(kinds: Kinds) usize {
        var total: usize = 0;
        inline for (@typeInfo(Kinds).@"struct".field_names) |name| total += @intFromBool(@field(kinds, name));
        return total;
    }

    /// Asks for the kind `flag` names (`--apps`); false when it names none.
    fn set(kinds: *Kinds, flag: []const u8) bool {
        inline for (@typeInfo(Kinds).@"struct".field_names) |name| {
            if (std.mem.eql(u8, flag, "--" ++ name)) {
                @field(kinds, name) = true;
                return true;
            }
        }
        return false;
    }
};

/// One line of a listing of one kind: a name and where it comes from, empty for a package.
pub const Row = struct { name: []const u8, origin: []const u8 };

/// Reads `[kosmos | --kosmoi | --apps | --adapters | --frontends | --packages ...] [--config dir]
/// [--script-kosmos name file]... [--frontend name module]...`; `--config dir` is the command
/// line's.
fn parseArguments(arena: std.mem.Allocator, arguments: []const []const u8) (error{UnexpectedArgument} || std.mem.Allocator.Error)!Parsed {
    var parsed: Parsed = .{};
    var script_kosmoi: std.ArrayList(Kosmos) = .empty;
    var frontends: std.ArrayList(Row) = .empty;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        if (std.mem.eql(u8, arguments[index], "--config")) {
            index += 1;
        } else if (std.mem.eql(u8, arguments[index], interface.script_kosmos_flag)) {
            if (index + 2 >= arguments.len) return error.UnexpectedArgument;
            const name = arguments[index + 1];
            try script_kosmoi.append(arena, .{ .name = name, .file = name[0 .. std.mem.findScalar(u8, name, '.') orelse name.len], .origin = arguments[index + 2], .apps = &.{} });
            index += 2;
        } else if (std.mem.eql(u8, arguments[index], interface.frontend_flag)) {
            if (index + 2 >= arguments.len) return error.UnexpectedArgument;
            try frontends.append(arena, .{ .name = arguments[index + 1], .origin = arguments[index + 2] });
            index += 2;
        } else if (parsed.kinds.set(arguments[index])) {
            if (parsed.filter != null) return error.UnexpectedArgument;
        } else if (parsed.filter != null or parsed.kinds.count() > 0 or std.mem.startsWith(u8, arguments[index], "-")) {
            return error.UnexpectedArgument;
        } else parsed.filter = arguments[index];
    }
    parsed.script_kosmoi = script_kosmoi.items;
    parsed.frontends = frontends.items;
    return parsed;
}

/// `kosmoi` with each of `script_kosmoi` it lacks after the last kosmos of the same file, or
/// at the end when none is.
fn withScriptKosmoi(arena: std.mem.Allocator, kosmoi: []const Kosmos, script_kosmoi: []const Kosmos) std.mem.Allocator.Error![]const Kosmos {
    var merged: std.ArrayList(Kosmos) = try .initCapacity(arena, kosmoi.len + script_kosmoi.len);
    merged.appendSliceAssumeCapacity(kosmoi);
    next: for (script_kosmoi) |added| {
        var position = merged.items.len;
        for (merged.items, 0..) |kosmos, index| {
            if (std.mem.eql(u8, kosmos.name, added.name)) continue :next;
            if (std.mem.eql(u8, kosmos.origin, added.origin)) position = index + 1;
        }
        merged.insertAssumeCapacity(position, added);
    }
    return merged.items;
}

/// One kosmos function.
pub const Kosmos = struct {
    /// As `kosm apply` spells it: "frost", "frost.iced" or "frost.cold.deep".
    name: []const u8,
    /// The file or package it is declared in: "frost".
    file: []const u8,
    origin: []const u8,
    apps: []const App,
    /// Whether its `Params` name a kosmos to build on, so the runner of scripts applies it.
    builds_on_kosmoi: bool = false,
};

/// An app in a kosmos tree.
pub const App = struct {
    /// Field path in the tree: "terminal.kitty"; empty when the tree is itself an app.
    path: []const u8,
    /// "kosm_kitty.App", or "?kosm_kitty.App" for an optional one.
    type_name: []const u8,
};

/// A package or local module and what it provides.
pub const Package = struct {
    name: []const u8,
    /// "package kosm_kitty" or "apps/my_bar/".
    origin: []const u8,
    provided: inspect.Provided,
};

/// `frontends` with the module giving each replaced by its origin ("package kosm_lua",
/// "frontends/lines.lua"), or kept when no source is that module.
fn frontendsOf(arena: std.mem.Allocator, frontends: []const Row, comptime sources: []const Source) std.mem.Allocator.Error![]const Row {
    const found = try arena.alloc(Row, frontends.len);
    for (frontends, found) |frontend, *row| {
        row.* = frontend;
        inline for (sources) |source| {
            if (std.mem.eql(u8, source.name, frontend.origin)) row.origin = source.origin;
        }
    }
    return found;
}

/// Everything the listing prints.
pub const Table = struct {
    kosmoi: []const Kosmos,
    packages: []const Package,
    /// The local kosmoi, apps and adapters, for the apps and adapters they declare.
    locals: []const Package = &.{},
    frontends: []const Row = &.{},

    /// Every kosmos with its origin, then every package with what it provides.
    pub fn writeAll(table: Table, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (table.kosmoi.len == 0) try writer.writeAll("kosmoi: none\n") else {
            try writer.writeAll("kosmoi:\n");
            const width = nameWidth(table.kosmoi, null);
            for (table.kosmoi) |kosmos| {
                try writer.writeAll("  ");
                try writeRow(writer, kosmos, width);
            }
        }
        if (table.packages.len == 0) return writer.writeAll("packages: none\n");
        try writer.writeAll("packages:\n");
        for (table.packages) |package| {
            try writer.print("  {s}\n", .{package.name});
            try package.provided.writeItems("    ", writer);
        }
    }

    /// Only the `kinds` asked for, one `name  origin` line each (only the name for a package).
    /// Several kinds each get a heading (`apps:`) with their lines indented below it; a kind
    /// with nothing in it says `none`.
    pub fn writeKinds(table: Table, arena: std.mem.Allocator, kinds: Kinds, writer: *std.Io.Writer) (std.mem.Allocator.Error || std.Io.Writer.Error)!void {
        const several = kinds.count() > 1;
        inline for (@typeInfo(Kinds).@"struct".field_names) |kind| {
            if (@field(kinds, kind)) {
                const rows = try table.rowsOf(arena, @field(RowKind, kind));
                if (rows.len == 0) {
                    try writer.writeAll(kind ++ ": none\n");
                } else {
                    if (several) try writer.writeAll(kind ++ ":\n");
                    try writeRows(writer, rows, if (several) "  " else "");
                }
            }
        }
    }

    const RowKind = enum { kosmoi, apps, adapters, frontends, packages };

    fn rowsOf(table: Table, arena: std.mem.Allocator, kind: RowKind) std.mem.Allocator.Error![]const Row {
        var rows: std.ArrayList(Row) = .empty;
        switch (kind) {
            .kosmoi => for (table.kosmoi) |kosmos| try rows.append(arena, .{ .name = kosmos.name, .origin = kosmos.origin }),
            .packages => for (table.packages) |package| try rows.append(arena, .{ .name = package.name, .origin = "" }),
            .frontends => try rows.appendSlice(arena, table.frontends),
            .apps => for ([_][]const Package{ table.packages, table.locals }) |owners| {
                for (owners) |owner| {
                    for (owner.provided.apps) |name| try rows.append(arena, .{ .name = name, .origin = owner.origin });
                }
            },
            .adapters => for ([_][]const Package{ table.packages, table.locals }) |owners| {
                for (owners) |owner| {
                    for (owner.provided.adapters) |name| try addAdapter(arena, &rows, name, owner);
                }
            },
        }
        return rows.items;
    }

    /// Adds adapter `name` from `owner` once: an app's package exports the adapters it writes
    /// with, so the package named after the adapter (`kosm_xml` for `xml`) wins over them.
    fn addAdapter(arena: std.mem.Allocator, rows: *std.ArrayList(Row), name: []const u8, owner: Package) std.mem.Allocator.Error!void {
        const own = std.mem.startsWith(u8, owner.name, "kosm_") and std.mem.eql(u8, owner.name["kosm_".len..], name);
        for (rows.items) |*row| {
            if (!std.mem.eql(u8, row.name, name)) continue;
            if (own) row.origin = owner.origin;
            return;
        }
        try rows.append(arena, .{ .name = name, .origin = owner.origin });
    }

    /// The kosmoi `name` picks: a file ("frost") or group ("frost.cold") with every kosmos in
    /// it, or one variant ("frost.iced"), each with the apps its tree holds.
    pub fn writeKosmos(table: Table, name: []const u8, writer: *std.Io.Writer) (error{UnknownKosmos} || std.Io.Writer.Error)!void {
        const width = nameWidth(table.kosmoi, name);
        if (width == 0) return error.UnknownKosmos;
        for (table.kosmoi) |kosmos| {
            if (!matches(kosmos, name)) continue;
            try writeRow(writer, kosmos, width);
            for (kosmos.apps) |app| {
                if (app.path.len == 0) try writer.print("  {s}\n", .{app.type_name}) else try writer.print("  {s}: {s}\n", .{ app.path, app.type_name });
            }
        }
    }

    /// One line per kosmos for the shell to offer: `frost.iced<TAB>kosmoi/frost.zig`.
    pub fn writeCompletions(table: Table, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (table.kosmoi) |kosmos| try writer.print("{s}\t{s}\n", .{ kosmos.name, kosmos.origin });
    }

    /// The name of every kosmos building on another, one per line.
    pub fn writeBuildingOnKosmoi(table: Table, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (table.kosmoi) |kosmos| {
            if (kosmos.builds_on_kosmoi) try writer.print("{s}\n", .{kosmos.name});
        }
    }

    /// Every kosmos name, in order.
    pub fn nameList(table: Table, arena: std.mem.Allocator) std.mem.Allocator.Error![]const []const u8 {
        const found = try arena.alloc([]const u8, table.kosmoi.len);
        for (table.kosmoi, found) |kosmos, *name| name.* = kosmos.name;
        return found;
    }
};

/// A name picks the kosmos of that name and every kosmos under it: a file's or a group's
/// variants ("frost" picks "frost.iced", "frost.cold" picks "frost.cold.deep").
pub fn matches(kosmos: Kosmos, name: []const u8) bool {
    return picks(name, kosmos.name);
}

/// Whether `name` is `kosmos_name` or a file or group holding it.
pub fn picks(name: []const u8, kosmos_name: []const u8) bool {
    if (!std.mem.startsWith(u8, kosmos_name, name)) return false;
    return kosmos_name.len == name.len or kosmos_name[name.len] == '.';
}

/// The longest name among the kosmoi `filter` picks (all of them when null); 0 when none.
fn nameWidth(kosmoi: []const Kosmos, filter: ?[]const u8) usize {
    var width: usize = 0;
    for (kosmoi) |kosmos| {
        if (filter) |name| if (!matches(kosmos, name)) continue;
        width = @max(width, kosmos.name.len);
    }
    return width;
}

/// Each row after `indent`, names padded so the origins line up.
fn writeRows(writer: *std.Io.Writer, rows: []const Row, indent: []const u8) std.Io.Writer.Error!void {
    var width: usize = 0;
    for (rows) |row| width = @max(width, row.name.len);
    for (rows) |row| {
        try writer.writeAll(indent);
        if (row.origin.len == 0) {
            try writer.print("{s}\n", .{row.name});
            continue;
        }
        try writer.writeAll(row.name);
        try writer.splatByteAll(' ', width - row.name.len + 2);
        try writer.print("{s}\n", .{row.origin});
    }
}

/// `name  origin`, with names padded to `width` so the origins line up.
fn writeRow(writer: *std.Io.Writer, kosmos: Kosmos, width: usize) std.Io.Writer.Error!void {
    try writer.writeAll(kosmos.name);
    try writer.splatByteAll(' ', width - kosmos.name.len + 2);
    try writer.print("{s}\n", .{kosmos.origin});
}

/// Every kosmos in `sources`, in order, each after the root script of its folder and followed
/// by the other scripts there, then every other script, and what each package provides.
pub fn collect(comptime sources: []const Source, comptime scripts: []const Script) Table {
    @setEvalBranchQuota(discovery.branch_quota);
    comptime var kosmoi: []const Kosmos = &.{};
    comptime var packages: []const Package = &.{};
    comptime var locals: []const Package = &.{};
    inline for (sources) |source| {
        // A root script gives the kosmos of a folder whose Zig module gives only variants; one
        // exporting values gives them through its module, listed below.
        inline for (scripts) |script| {
            if (comptime std.mem.eql(u8, script.name, source.name) and !exportsFrom(source.module, script.origin)) kosmoi = kosmoi ++ .{scriptRow(script)};
        }
        inline for (comptime discovery.declaredKosmoi(source.module)) |declared| {
            const Function = @typeInfo(@TypeOf(@field(declared.Namespace, declared.function))).@"fn";
            const Tree = discovery.Payload(Function.return_type.?);
            kosmoi = kosmoi ++ .{Kosmos{
                .name = if (declared.name.len == 0) source.name else source.name ++ "." ++ declared.name,
                .file = source.name,
                .origin = source.origin,
                .apps = appsIn(sources, Tree, ""),
                .builds_on_kosmoi = Function.param_types.len == 1 and kosmos_call.buildsOnKosmoi(Function.param_types[0].?),
            }};
        }
        // Scripts in the kosmos' folder are its variants, listed with the others.
        inline for (scripts) |script| {
            if (comptime parentOf(script.name)) |parent| {
                if (comptime std.mem.eql(u8, parent, source.name)) kosmoi = kosmoi ++ .{scriptRow(script)};
            }
        }
        const package: Package = .{ .name = source.name, .origin = source.origin, .provided = inspect.provided(source.name, source.module) };
        if (source.kind == .package) packages = packages ++ .{package} else locals = locals ++ .{package};
    }
    inline for (scripts) |script| {
        const folder = comptime parentOf(script.name) orelse script.name;
        const listed = inline for (sources) |source| {
            if (comptime std.mem.eql(u8, folder, source.name)) break true;
        } else false;
        if (!listed) kosmoi = kosmoi ++ .{scriptRow(script)};
    }
    const final_kosmoi = kosmoi[0..kosmoi.len].*;
    const final_packages = packages[0..packages.len].*;
    const final_locals = locals[0..locals.len].*;
    const table: Table = .{ .kosmoi = &final_kosmoi, .packages = &final_packages, .locals = &final_locals };
    return table;
}

/// Whether `Module` is generated from the script `origin`, which exports values for building on.
fn exportsFrom(comptime Module: type, comptime origin: []const u8) bool {
    return hosting.isScriptExports(Module) and std.mem.eql(u8, Module.script.path, origin);
}

/// The kosmos whose folder holds `name`'s script ("personal" of "personal.nord"), or null for
/// a script in `kosmoi/` itself.
fn parentOf(comptime name: []const u8) ?[]const u8 {
    const dot = std.mem.findScalar(u8, name, '.') orelse return null;
    return name[0..dot];
}

fn scriptRow(comptime script: Script) Kosmos {
    return .{ .name = script.name, .file = script.name, .origin = script.origin, .apps = &.{} };
}

/// The apps in a tree of type `T`, looking through structs and optionals like the walk does
///; `path` is where `T` sits.
fn appsIn(comptime sources: []const Source, comptime T: type, comptime path: []const u8) []const App {
    @setEvalBranchQuota(discovery.branch_quota);
    const optional = @typeInfo(T) == .optional;
    const Unwrapped = if (optional) @typeInfo(T).optional.child else T;
    if (discovery.isApp(Unwrapped)) return &.{.{ .path = path, .type_name = (if (optional) "?" else "") ++ appName(sources, Unwrapped) }};
    // Skipping what holds no app keeps large values (a kept `kosm.Theme`) within the branch quota.
    if (@typeInfo(Unwrapped) != .@"struct" or !discovery.containsApp(Unwrapped)) return &.{};
    comptime var found: []const App = &.{};
    const info = @typeInfo(Unwrapped).@"struct";
    inline for (info.field_names, info.field_types) |name, Field| {
        found = found ++ appsIn(sources, Field, if (path.len == 0) name else path ++ "." ++ name);
    }
    return found;
}

/// App type `T` as a user imports it ("kosm_kitty.App"): the first source declaring it at its
/// top, or Zig's own type name when none does.
fn appName(comptime sources: []const Source, comptime T: type) []const u8 {
    inline for (sources) |source| {
        inline for (@typeInfo(source.module).@"struct".decl_names) |decl| {
            if (@TypeOf(@field(source.module, decl)) == type and @field(source.module, decl) == T) return source.name ++ "." ++ decl;
        }
    }
    return @typeName(T);
}

const testing = std.testing;

const TestApp = struct {
    size: u8 = 1,
    pub fn apply(self: TestApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

const Frost = struct {
    pub const Tree = struct { terminal: struct { kitty: ?TestApp }, editor: TestApp, other: u8 = 0 };
    pub fn kosmos() Tree {
        return .{ .terminal = .{ .kitty = null }, .editor = .{} };
    }
    pub fn iced() !Tree {
        return kosmos();
    }
    pub fn helper(size: u8) u8 {
        return size;
    }
    pub const cold = struct {
        pub fn deep() Tree {
            return .{ .terminal = .{ .kitty = null }, .editor = .{} };
        }
    };
};

/// A folder whose root script gives its kosmos, and whose root.zig gives only a variant.
const Snow = struct {
    pub fn iced(params: struct { on: kosm.Kosmos(Frost.Tree) = .{ .name = "snow" } }) !Frost.Tree {
        return params.on.tree();
    }
};

const Base = struct {
    pub fn from(theme: kosm.Theme) struct { editor: TestApp } {
        _ = theme;
        return .{ .editor = .{} };
    }
};

const ProbePackage = struct {
    pub const App = TestApp;
    pub fn kosmos() struct { app: TestApp } {
        return .{ .app = .{} };
    }
};

const test_table = collect(&.{
    .{ .name = "base", .origin = "kosmoi/base.zig", .kind = .local, .module = Base },
    .{ .name = "frost", .origin = "kosmoi/frost.zig", .kind = .local, .module = Frost },
    .{ .name = "kosm_probe", .origin = "package kosm_probe", .kind = .package, .module = ProbePackage },
    .{ .name = "snow", .origin = "kosmoi/snow/", .kind = .local, .module = Snow },
}, &.{
    .{ .name = "frost.nord", .origin = "kosmoi/frost/nord.lua" },
    .{ .name = "minimal", .origin = "kosmoi/minimal.lua" },
    .{ .name = "snow", .origin = "kosmoi/snow/root.lua" },
    .{ .name = "snow.nord", .origin = "kosmoi/snow/nord.lua" },
});

test "list prints every kosmos with its origin, then what each package provides" {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try test_table.writeAll(&writer);
    try testing.expectEqualStrings(
        \\kosmoi:
        \\  frost            kosmoi/frost.zig
        \\  frost.iced       kosmoi/frost.zig
        \\  frost.cold.deep  kosmoi/frost.zig
        \\  frost.nord       kosmoi/frost/nord.lua
        \\  kosm_probe       package kosm_probe
        \\  snow             kosmoi/snow/root.lua
        \\  snow.iced        kosmoi/snow/
        \\  snow.nord        kosmoi/snow/nord.lua
        \\  minimal          kosmoi/minimal.lua
        \\packages:
        \\  kosm_probe
        \\    app      kosm_probe.App
        \\    kosmos   kosm_probe
        \\
    , writer.buffered());
}

test "listing one kosmos file shows its variants and the apps in each tree" {
    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try test_table.writeKosmos("frost", &writer);
    try testing.expectEqualStrings(
        \\frost            kosmoi/frost.zig
        \\  terminal.kitty: ?kosm_probe.App
        \\  editor: kosm_probe.App
        \\frost.iced       kosmoi/frost.zig
        \\  terminal.kitty: ?kosm_probe.App
        \\  editor: kosm_probe.App
        \\frost.cold.deep  kosmoi/frost.zig
        \\  terminal.kitty: ?kosm_probe.App
        \\  editor: kosm_probe.App
        \\frost.nord       kosmoi/frost/nord.lua
        \\
    , writer.buffered());
}

test "the kosmoi building on another are those whose Params name one" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try test_table.writeBuildingOnKosmoi(&writer);
    try testing.expectEqualStrings("snow.iced\n", writer.buffered());
}

test "a group picks every kosmos in it, and a name only matches whole segments" {
    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try test_table.writeKosmos("frost.cold", &writer);
    try testing.expect(std.mem.startsWith(u8, writer.buffered(), "frost.cold.deep  kosmoi/frost.zig\n"));
    try testing.expect(picks("frost", "frost.cold.deep"));
    try testing.expect(!picks("frost.co", "frost.cold.deep"));
    try testing.expect(!picks("fro", "frost"));
    try testing.expect(!picks("frost.cold.deep", "frost.cold"));
}

test "listing a variant shows only it, and an unknown name is an error" {
    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try test_table.writeKosmos("frost.iced", &writer);
    try testing.expect(std.mem.startsWith(u8, writer.buffered(), "frost.iced  kosmoi/frost.zig\n"));
    try testing.expect(std.mem.find(u8, writer.buffered(), "frost  ") == null);
    try testing.expectError(error.UnknownKosmos, test_table.writeKosmos("base", &writer));
    try testing.expectError(error.UnknownKosmos, test_table.writeKosmos("frost.nope", &writer));
}

test "a script kosmos is listed by its name and file" {
    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try test_table.writeKosmos("minimal", &writer);
    try testing.expectEqualStrings("minimal  kosmoi/minimal.lua\n", writer.buffered());
}

test "listing kinds shows each alone, an adapter once under its own package, and none where empty" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const no_kosmoi: []const []const u8 = &.{};
    const table: Table = .{
        .kosmoi = &.{.{ .name = "frost", .file = "frost", .origin = "kosmoi/frost.zig", .apps = &.{} }},
        .packages = &.{
            .{ .name = "kosm_kitty", .origin = "package kosm_kitty", .provided = .{ .apps = &.{"kosm_kitty.App"}, .adapters = &.{ "kitty", "xml" }, .kosmoi = no_kosmoi, .bases = no_kosmoi } },
            .{ .name = "kosm_xml", .origin = "package kosm_xml", .provided = .{ .apps = no_kosmoi, .adapters = &.{"xml"}, .kosmoi = no_kosmoi, .bases = no_kosmoi } },
        },
        .locals = &.{.{ .name = "my_bar", .origin = "apps/my_bar/", .provided = .{ .apps = &.{"my_bar.App"}, .adapters = no_kosmoi, .kosmoi = no_kosmoi, .bases = no_kosmoi } }},
    };
    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try table.writeKinds(arena.allocator(), .{ .apps = true }, &writer);
    try testing.expectEqualStrings("kosm_kitty.App  package kosm_kitty\nmy_bar.App      apps/my_bar/\n", writer.buffered());
    writer = .fixed(&buffer);
    try table.writeKinds(arena.allocator(), .{ .adapters = true, .frontends = true, .packages = true }, &writer);
    try testing.expectEqualStrings(
        \\adapters:
        \\  kitty  package kosm_kitty
        \\  xml    package kosm_xml
        \\frontends: none
        \\packages:
        \\  kosm_kitty
        \\  kosm_xml
        \\
    , writer.buffered());
}

test "an empty config lists nothing, saying so" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try collect(&.{}, &.{}).writeAll(&writer);
    try testing.expectEqualStrings("kosmoi: none\npackages: none\n", writer.buffered());
}

test "list takes one kosmos and skips --config" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("frost", (try parseArguments(arena.allocator(), &.{ "--config", "/c", "frost" })).filter.?);
    try testing.expectEqual(null, (try parseArguments(arena.allocator(), &.{})).filter);
    try testing.expectError(error.UnexpectedArgument, parseArguments(arena.allocator(), &.{ "a", "b" }));
    try testing.expectError(error.UnexpectedArgument, parseArguments(arena.allocator(), &.{"--diff"}));
    try testing.expectError(error.UnexpectedArgument, parseArguments(arena.allocator(), &.{ interface.script_kosmos_flag, "minimal.light" }));
    const kinds = try parseArguments(arena.allocator(), &.{ "--apps", interface.frontend_flag, "lua", "kosm_lua", "--frontends" });
    try testing.expectEqual(2, kinds.kinds.count());
    try testing.expectEqualStrings("kosm_lua", kinds.frontends[0].origin);
    try testing.expectError(error.UnexpectedArgument, parseArguments(arena.allocator(), &.{ "--apps", "frost" }));
    try testing.expectError(error.UnexpectedArgument, parseArguments(arena.allocator(), &.{ "frost", "--apps" }));
}

test "script kosmoi from the command line follow the kosmoi of their file, each listed once" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const parsed = try parseArguments(arena.allocator(), &.{
        interface.script_kosmos_flag, "minimal.light", "kosmoi/minimal.lua",
        interface.script_kosmos_flag, "minimal",       "kosmoi/minimal.lua",
        interface.script_kosmos_flag, "loose.dark",    "kosmoi/loose.lua",
    });
    const kosmoi: []const Kosmos = &.{
        .{ .name = "minimal", .file = "minimal", .origin = "kosmoi/minimal.lua", .apps = &.{} },
        .{ .name = "snow", .file = "snow", .origin = "kosmoi/snow.zig", .apps = &.{} },
    };
    const merged = try withScriptKosmoi(arena.allocator(), kosmoi, parsed.script_kosmoi);
    const table: Table = .{ .kosmoi = merged, .packages = &.{} };
    try testing.expectEqualStrings("minimal, minimal.light, snow, loose.dark", try std.mem.join(arena.allocator(), ", ", try table.nameList(arena.allocator())));
}
