//! What an installed package provides: its apps, adapters and kosmoi, found by reflection.
//! `kosm add` and `kosm update` refuse a package that provides none of them (D46).

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const interface = @import("kosm_interface");

/// Prints what `Package` (imported as `name`) provides to stdout and returns 0, or prints why
/// it is not a kosm package to stderr and returns 1.
pub fn inspect(init: std.process.Init, comptime name: []const u8, comptime Package: type) !u8 {
    const report = comptime provided(name, Package);
    var stderr_buffer: [512]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    if (!try interface.check(init.environ_map, &stderr.interface)) {
        try stderr.interface.flush();
        return 1;
    }
    if (report.isEmpty()) {
        try stderr.interface.print("error: package '{s}' provides no app, adapter or kosmos, so it is not a kosm package (D46)\n", .{name});
        try stderr.interface.flush();
        return 1;
    }
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try report.write(name, &stdout.interface);
    try stdout.interface.flush();
    return 0;
}

/// A package's apps, adapters and kosmoi, each as the user spells them.
pub const Provided = struct {
    /// Public app types, as `@import` paths: "kosm_kitty.App".
    apps: []const []const u8,
    /// Adapter names: "kitty".
    adapters: []const []const u8,
    /// Kosmoi as `kosm apply` spells them: "nord", "nord.iced".
    kosmoi: []const []const u8,

    fn isEmpty(self: Provided) bool {
        return self.apps.len == 0 and self.adapters.len == 0 and self.kosmoi.len == 0;
    }

    /// One line per kind: `name provides:` then `  app kosm_kitty.App` and so on.
    pub fn write(self: Provided, name: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} provides:\n", .{name});
        try self.writeItems("  ", writer);
    }

    /// One line per app, adapter and kosmos, each after `indent`: `  app      kosm_kitty.App`.
    pub fn writeItems(self: Provided, indent: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.apps) |app| try writer.print("{s}app      {s}\n", .{ indent, app });
        for (self.adapters) |adapter| try writer.print("{s}adapter  {s}\n", .{ indent, adapter });
        for (self.kosmoi) |kosmos| try writer.print("{s}kosmos   {s}\n", .{ indent, kosmos });
    }
};

/// Every public app type, adapter constant and kosmos function at the top of `Package`.
pub fn provided(comptime name: []const u8, comptime Package: type) Provided {
    @setEvalBranchQuota(discovery.branch_quota);
    comptime var apps: []const []const u8 = &.{};
    comptime var kosmoi: []const []const u8 = &.{};
    inline for (@typeInfo(Package).@"struct".decl_names) |decl| {
        const Declaration = @TypeOf(@field(Package, decl));
        if (Declaration == type and discovery.isApp(@field(Package, decl))) apps = apps ++ .{name ++ "." ++ decl};
        if (comptime discovery.notKosmosReason(Package, decl) == null) {
            kosmoi = kosmoi ++ .{if (comptime std.mem.eql(u8, decl, "kosmos")) name else name ++ "." ++ decl};
        }
    }
    comptime var adapters: []const []const u8 = &.{};
    inline for (comptime discovery.adapters(&.{Package})) |adapter| adapters = adapters ++ .{adapter.name};
    const final_apps = apps[0..apps.len].*;
    const final_adapters = adapters[0..adapters.len].*;
    const final_kosmoi = kosmoi[0..kosmoi.len].*;
    return .{ .apps = &final_apps, .adapters = &final_adapters, .kosmoi = &final_kosmoi };
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
    pub const Theme = kosm.Theme;
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

test "a package of plain declarations provides nothing" {
    try testing.expect(comptime provided("kosm_empty", EmptyPackage).isEmpty());
}
