//! A variation family written through a frontend: where its script is, and the call the Zig
//! module kosm generates for it makes to run the script's `from(mode)` through
//! `Host.current()`. Its `Family` type is a plain struct of modifiers, so a base holds it beside
//! the theme like one written in Zig.

const ScriptFamily = @This();

const std = @import("std");
const Loose = @import("../Loose.zig");
const Theme = @import("../Theme.zig");
const Diagnostics = @import("../Diagnostics.zig");
const assignment = @import("../assignment.zig");
const failure = @import("../failure.zig");
const Host = @import("Host.zig");
const Call = @import("Call.zig");
const Handle = @import("Handle.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, relative to the config: "colors/glow.lua".
path: []const u8,

/// The script, as the host runs it.
pub fn file(family: ScriptFamily) ScriptFile {
    return .{ .frontend = family.frontend, .path = family.path };
}

/// The family the script's `from(mode)` gives: the fields of the table it returns, set on the
/// family's defaults. It cannot fail: a failure is recorded like `kosm.fail`'s message, which
/// kosm reports before anything is written, and the defaults are given.
pub fn from(family: ScriptFamily, comptime Family: type, mode: Theme.Mode) Family {
    var built: Family = .{};
    family.fill(Family, &built, mode) catch |err| switch (err) {
        error.OutOfMemory => failure.record("{s}: out of memory", .{family.path}),
        // `fill` recorded why.
        error.KosmosFailed => {},
    };
    return built;
}

fn fill(family: ScriptFamily, comptime Family: type, built: *Family, mode: Theme.Mode) (std.mem.Allocator.Error || failure.Error)!void {
    const host = Host.current() orelse return failure.fail("{s}: a variation family written through a frontend runs only in the runner of scripts, and this runner is none", .{family.path});
    var call = host.call();
    const given = host.run(host.state, &call, family.file(), "from", &.{.{ .value = .{ .string = @tagName(mode) } }}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CallFailed => return failure.fail("{s}", .{call.message orelse "from failed and did not say why"}),
    };
    var diagnostics: Diagnostics = .{};
    var named = given;
    if (named.origin == null) named.origin = try host.arena.print("{s}: from", .{family.path});
    assignment.assignNamed(Family, host.arena, built, named, &diagnostics, "the family") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidAssignment => return failure.fail("{s}", .{diagnostics.message()}),
    };
}

const testing = std.testing;
const Modifier = @import("../Modifier.zig");

/// A host whose `from` lightens `soft` away from the background for `colors/glow.lua`, and
/// returns a field the family lacks otherwise.
const TestHost = struct {
    fn run(state: *anyopaque, call: *Call, script: ScriptFile, function: []const u8, arguments: []const Loose) Call.Error!Loose {
        _ = state;
        std.debug.assert(std.mem.eql(u8, function, "from"));
        if (!std.mem.eql(u8, script.path, "colors/glow.lua")) return .{ .value = .{ .table = try call.arena.dupe(Loose.Entry, &.{.{ .key = "sotf", .value = .{ .value = .{ .table = &.{} } } }}) } };
        const lightness: f64 = if (std.mem.eql(u8, arguments[0].value.string, "dark")) 0.1 else -0.1;
        const soft = try call.arena.dupe(Loose.Entry, &.{.{ .key = "lightness", .value = .{ .value = .{ .float = lightness } } }});
        return .{ .value = .{ .table = try call.arena.dupe(Loose.Entry, &.{.{ .key = "soft", .value = .{ .value = .{ .table = soft } } }}) } };
    }

    fn handle(state: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle {
        _ = .{ state, id, pointer };
        return null;
    }
};

const TestFamily = struct {
    soft: Modifier = .{},
    strong: Modifier = .{ .lightness = 0.3 },
};

test "from sets the fields the script returns for the mode on the family's defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host: Host = .{ .state = undefined, .arena = arena.allocator(), .run = TestHost.run, .handle = TestHost.handle };
    Host.install(&host);
    defer Host.install(null);
    defer failure.clear();
    failure.clear();
    const glow: ScriptFamily = .{ .frontend = "test", .path = "colors/glow.lua" };
    try testing.expectEqual(0.1, glow.from(TestFamily, .dark).soft.lightness);
    const light = glow.from(TestFamily, .light);
    try testing.expectEqual(-0.1, light.soft.lightness);
    try testing.expectEqual(0.3, light.strong.lightness);
    try testing.expectEqual(null, failure.message());
    const wrong: ScriptFamily = .{ .frontend = "test", .path = "colors/wrong.lua" };
    try testing.expectEqual(0.0, wrong.from(TestFamily, .dark).soft.lightness);
    try testing.expect(std.mem.startsWith(u8, failure.message().?, "colors/wrong.lua: from: "));
}
