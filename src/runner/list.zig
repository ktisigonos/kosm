//! `kosm list`: every kosmos in a config with its variants and where it comes from, and
//! every installed package with what it provides, all found by reflection at compile time.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const inspect = @import("inspect.zig");
const interface = @import("kosm_interface");

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

/// Prints the listing for the process arguments (`[kosmos] [--config dir]`) and returns the exit
/// status: 0, or 1 after printing what went wrong.
pub fn list(init: std.process.Init, comptime sources: []const Source) !u8 {
    const table = comptime collect(sources);
    const arena = init.arena.allocator();
    const arguments = try init.minimal.args.toSlice(arena);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    if (!try interface.check(init.environ_map, &stderr.interface)) {
        try stderr.interface.flush();
        return 1;
    }

    const status: u8 = if (filterArgument(arguments[1..])) |filter| status: {
        if (filter) |name| {
            table.writeKosmos(name, &stdout.interface) catch |err| switch (err) {
                error.UnknownKosmos => {
                    try stderr.interface.print("error: there is no kosmos '{s}'; kosmoi: ", .{name});
                    try table.writeNames(&stderr.interface);
                    try stderr.interface.writeAll("\n");
                    break :status 1;
                },
                error.WriteFailed => return error.WriteFailed,
            };
        } else try table.writeAll(&stdout.interface);
        break :status 0;
    } else |_| status: {
        try stderr.interface.writeAll("error: kosm list takes at most one kosmos, e.g. kosm list frost\n");
        break :status 1;
    };
    try stdout.interface.flush();
    try stderr.interface.flush();
    return status;
}

/// The one kosmos to list, or null for everything; `--config dir` is the command line's.
fn filterArgument(arguments: []const []const u8) error{UnexpectedArgument}!?[]const u8 {
    var filter: ?[]const u8 = null;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        if (std.mem.eql(u8, arguments[index], "--config")) {
            index += 1;
        } else if (filter != null or std.mem.startsWith(u8, arguments[index], "-")) {
            return error.UnexpectedArgument;
        } else filter = arguments[index];
    }
    return filter;
}

/// One kosmos function.
pub const Kosmos = struct {
    /// As `kosm apply` spells it: "frost" or "frost.iced".
    name: []const u8,
    /// The file or package it is declared in: "frost".
    file: []const u8,
    origin: []const u8,
    apps: []const App,
};

/// An app in a kosmos tree.
pub const App = struct {
    /// Field path in the tree: "terminal.kitty"; empty when the tree is itself an app.
    path: []const u8,
    /// "kosm_kitty.App", or "?kosm_kitty.App" for an optional one.
    type_name: []const u8,
};

/// A package and what it provides.
pub const Package = struct {
    name: []const u8,
    provided: inspect.Provided,
};

/// Everything the listing prints.
pub const Table = struct {
    kosmoi: []const Kosmos,
    packages: []const Package,

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

    /// The kosmoi of file `name` ("frost"), or the one variant `name` names ("frost.iced"),
    /// each with the apps its tree holds.
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

    /// Every kosmos name, comma-separated, or "none".
    pub fn writeNames(table: Table, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (table.kosmoi.len == 0) return writer.writeAll("none");
        for (table.kosmoi, 0..) |kosmos, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(kosmos.name);
        }
    }
};

/// A name without a dot picks every kosmos of that file; one with a dot picks that variant.
fn matches(kosmos: Kosmos, name: []const u8) bool {
    if (std.mem.findScalar(u8, name, '.') == null) return std.mem.eql(u8, kosmos.file, name);
    return std.mem.eql(u8, kosmos.name, name);
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

/// `name  origin`, with names padded to `width` so the origins line up.
fn writeRow(writer: *std.Io.Writer, kosmos: Kosmos, width: usize) std.Io.Writer.Error!void {
    try writer.writeAll(kosmos.name);
    try writer.splatByteAll(' ', width - kosmos.name.len + 2);
    try writer.print("{s}\n", .{kosmos.origin});
}

/// Every kosmos in `sources`, in order, and what each package provides.
pub fn collect(comptime sources: []const Source) Table {
    @setEvalBranchQuota(discovery.branch_quota);
    comptime var kosmoi: []const Kosmos = &.{};
    comptime var packages: []const Package = &.{};
    inline for (sources) |source| {
        inline for (@typeInfo(source.module).@"struct".decl_names) |decl| {
            if (comptime discovery.notKosmosReason(source.module, decl) == null) {
                const Function = @typeInfo(@TypeOf(@field(source.module, decl))).@"fn";
                const Tree = discovery.Payload(Function.return_type.?);
                kosmoi = kosmoi ++ .{Kosmos{
                    .name = if (comptime std.mem.eql(u8, decl, "kosmos")) source.name else source.name ++ "." ++ decl,
                    .file = source.name,
                    .origin = source.origin,
                    .apps = appsIn(sources, Tree, ""),
                }};
            }
        }
        if (source.kind == .package) packages = packages ++ .{Package{ .name = source.name, .provided = inspect.provided(source.name, source.module) }};
    }
    const final_kosmoi = kosmoi[0..kosmoi.len].*;
    const final_packages = packages[0..packages.len].*;
    const table: Table = .{ .kosmoi = &final_kosmoi, .packages = &final_packages };
    return table;
}

/// The apps in a tree of type `T`, looking through structs and optionals like the walk does
///; `path` is where `T` sits.
fn appsIn(comptime sources: []const Source, comptime T: type, comptime path: []const u8) []const App {
    @setEvalBranchQuota(discovery.branch_quota);
    const optional = @typeInfo(T) == .optional;
    const Unwrapped = if (optional) @typeInfo(T).optional.child else T;
    if (discovery.isApp(Unwrapped)) return &.{.{ .path = path, .type_name = (if (optional) "?" else "") ++ appName(sources, Unwrapped) }};
    if (@typeInfo(Unwrapped) != .@"struct") return &.{};
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
});

test "list prints every kosmos with its origin, then what each package provides" {
    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try test_table.writeAll(&writer);
    try testing.expectEqualStrings(
        \\kosmoi:
        \\  frost       kosmoi/frost.zig
        \\  frost.iced  kosmoi/frost.zig
        \\  kosm_probe  package kosm_probe
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
        \\frost       kosmoi/frost.zig
        \\  terminal.kitty: ?kosm_probe.App
        \\  editor: kosm_probe.App
        \\frost.iced  kosmoi/frost.zig
        \\  terminal.kitty: ?kosm_probe.App
        \\  editor: kosm_probe.App
        \\
    , writer.buffered());
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

test "an empty config lists nothing, saying so" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try collect(&.{}).writeAll(&writer);
    try testing.expectEqualStrings("kosmoi: none\npackages: none\n", writer.buffered());
}

test "list takes one kosmos and skips --config" {
    try testing.expectEqualStrings("frost", (try filterArgument(&.{ "--config", "/c", "frost" })).?);
    try testing.expectEqual(null, try filterArgument(&.{}));
    try testing.expectError(error.UnexpectedArgument, filterArgument(&.{ "a", "b" }));
    try testing.expectError(error.UnexpectedArgument, filterArgument(&.{"--diff"}));
}
