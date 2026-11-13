//! What an installed package provides: its apps, adapters, kosmoi and bases, found by
//! reflection. `kosm add` and `kosm update` refuse a package that provides none of them.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const interface = @import("kosm_interface");

/// Prints what each package provides to stdout and returns 0, or prints why one is not a kosm
/// package to stderr and returns 1 after reporting every other. `packages` is a tuple of
/// `.{ name, @import(name) }` pairs.
pub fn inspect(init: std.process.Init, comptime packages: anytype) !u8 {
    var stderr_buffer: [512]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    if (!try interface.check(init.environ_map, &stderr.interface)) {
        try stderr.interface.flush();
        return 1;
    }
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var all_provide = true;
    inline for (packages) |package| {
        const name: []const u8 = package[0];
        const report = comptime provided(name, package[1]);
        if (report.isEmpty()) {
            try stderr.interface.print("error: package '{s}' provides no app, adapter, kosmos or base, so it is not a kosm package\n", .{name});
            all_provide = false;
        } else try report.write(name, &stdout.interface);
    }
    try stdout.interface.flush();
    try stderr.interface.flush();
    return if (all_provide) 0 else 1;
}

/// A package's apps, adapters, kosmoi and bases, each as the user spells them.
pub const Provided = struct {
    /// Public app types, as `@import` paths: "kosm_kitty.App".
    apps: []const []const u8,
    /// Adapter names: "kitty".
    adapters: []const []const u8,
    /// Kosmoi as `kosm apply` spells them: "nord", "nord.iced".
    kosmoi: []const []const u8,
    /// Functions a kosmos builds on, returning a struct of apps: "kosm_base.from".
    bases: []const []const u8,

    fn isEmpty(self: Provided) bool {
        return self.apps.len == 0 and self.adapters.len == 0 and self.kosmoi.len == 0 and self.bases.len == 0;
    }

    /// One line per kind: `name provides:` then `  app kosm_kitty.App` and so on.
    pub fn write(self: Provided, name: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} provides:\n", .{name});
        try self.writeItems("  ", writer);
    }

    /// One line per app, adapter, kosmos and base, each after `indent`: `  app      kosm_kitty.App`.
    pub fn writeItems(self: Provided, indent: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.apps) |app| try writer.print("{s}app      {s}\n", .{ indent, app });
        for (self.adapters) |adapter| try writer.print("{s}adapter  {s}\n", .{ indent, adapter });
        for (self.kosmoi) |kosmos| try writer.print("{s}kosmos   {s}\n", .{ indent, kosmos });
        for (self.bases) |base| try writer.print("{s}base     {s}\n", .{ indent, base });
    }
};

/// Every public app type, adapter constant and base function at the top of `Package`, and its
/// kosmoi, groups included.
pub fn provided(comptime name: []const u8, comptime Package: type) Provided {
    @setEvalBranchQuota(discovery.branch_quota);
    comptime var apps: []const []const u8 = &.{};
    comptime var kosmoi: []const []const u8 = &.{};
    comptime var bases: []const []const u8 = &.{};
    inline for (@typeInfo(Package).@"struct".decl_names) |decl| {
        const Declaration = @TypeOf(@field(Package, decl));
        if (Declaration == type and discovery.isApp(@field(Package, decl))) apps = apps ++ .{name ++ "." ++ decl};
        if (comptime discovery.notKosmosReason(Package, decl) != null and !discovery.isGroup(Package, decl) and isBase(Package, decl))
            bases = bases ++ .{name ++ "." ++ decl};
    }
    inline for (comptime discovery.declaredKosmoi(Package)) |declared| {
        kosmoi = kosmoi ++ .{if (declared.name.len == 0) name else name ++ "." ++ declared.name};
    }
    comptime var adapters: []const []const u8 = &.{};
    inline for (comptime discovery.declaredAdapters(Package)) |adapter| adapters = adapters ++ .{adapter.name};
    const final_apps = apps[0..apps.len].*;
    const final_adapters = adapters[0..adapters.len].*;
    const final_kosmoi = kosmoi[0..kosmoi.len].*;
    const final_bases = bases[0..bases.len].*;
    return .{ .apps = &final_apps, .adapters = &final_adapters, .kosmoi = &final_kosmoi, .bases = &final_bases };
}

/// Whether `Package.name` is a base: a function, not a kosmos, whose result is a struct holding
/// apps but no app itself, like `kosm_base.from(look, apps)`.
fn isBase(comptime Package: type, comptime name: []const u8) bool {
    const function = switch (@typeInfo(@TypeOf(@field(Package, name)))) {
        .@"fn" => |function| function,
        else => return false,
    };
    // A comptime parameter makes the function generic, but its result type is still known.
    const Result = discovery.Payload(function.return_type orelse return false);
    return @typeInfo(Result) == .@"struct" and !discovery.isApp(Result) and discovery.containsApp(Result);
}

const testing = std.testing;

const TestPackage = struct {
    pub const App = struct {
        size: u8 = 1,
        pub fn apply(self: App, output: *kosm.Output) !void {
            _ = self;
            _ = output;
        }
    };
    pub const adapter: kosm.Adapter = .{ .name = "probe", .extensions = &.{".probe"} };
    pub const Tree = struct { app: App };
    pub fn kosmos() Tree {
        return .{ .app = .{} };
    }
    pub fn iced() Tree {
        return .{ .app = .{ .size = 2 } };
    }
    pub fn helper(size: u8) u8 {
        return size;
    }
    pub fn from(size: u8) App {
        return .{ .size = size };
    }
    pub const Theme = kosm.Theme;
};

const BasePackage = struct {
    pub const Base = struct { probe: ?TestPackage.App = null };
    pub fn from(comptime size: u8) Base {
        return .{ .probe = .{ .size = size } };
    }
};

const EmptyPackage = struct {
    pub const answer = 42;
    pub fn helper() void {}
};

test "a package reports its apps, adapters and kosmoi as the user spells them" {
    const report = comptime provided("kosm_probe", TestPackage);
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try report.write("kosm_probe", &writer);
    try testing.expectEqualStrings(
        \\kosm_probe provides:
        \\  app      kosm_probe.App
        \\  adapter  probe
        \\  kosmos   kosm_probe
        \\  kosmos   kosm_probe.iced
        \\
    , writer.buffered());
}

test "a function returning a struct of apps that takes inputs is a base, not a kosmos" {
    const report = comptime provided("kosm_probe_base", BasePackage);
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try report.write("kosm_probe_base", &writer);
    try testing.expectEqualStrings(
        \\kosm_probe_base provides:
        \\  base     kosm_probe_base.from
        \\
    , writer.buffered());
}

test "a package of plain declarations provides nothing" {
    try testing.expect(comptime provided("kosm_empty", EmptyPackage).isEmpty());
}
