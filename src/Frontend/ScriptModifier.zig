//! A modifier written through a frontend: where its script is, and the call the Zig module kosm
//! generates for it makes to run the script's `apply(self, color)` through `Host.current()`. Its
//! `Modifier` type keeps the shape `kosm.Modifier.Function.of` takes, so it is used like one
//! written in Zig.

const ScriptModifier = @This();

const std = @import("std");
const Loose = @import("../Loose.zig");
const Color = @import("../Color.zig");
const Diagnostics = @import("../Diagnostics.zig");
const assignment = @import("../assignment.zig");
const failure = @import("../failure.zig");
const Host = @import("Host.zig");
const Call = @import("Call.zig");
const Handle = @import("Handle.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, relative to the config: "colors/sepia.lua".
path: []const u8,

/// The script, as the host runs it.
pub fn file(modifier: ScriptModifier) ScriptFile {
    return .{ .frontend = modifier.frontend, .path = modifier.path };
}

/// The color the script's `apply(self, color)` gives. Like any modifier it cannot fail: a
/// failure is recorded like `kosm.fail`'s message, which kosm reports before anything is
/// written, and `color` is given unchanged.
pub fn apply(modifier: ScriptModifier, comptime Modifier: type, self: Modifier, color: Color) Color {
    return modifier.run(Modifier, self, color) catch |err| {
        switch (err) {
            error.OutOfMemory => failure.record("{s}: out of memory", .{modifier.path}),
            // `run` recorded why.
            error.KosmosFailed => {},
        }
        return color;
    };
}

fn run(modifier: ScriptModifier, comptime Modifier: type, self: Modifier, color: Color) (std.mem.Allocator.Error || failure.Error)!Color {
    const host = Host.current() orelse return failure.fail("{s}: a modifier written through a frontend runs only in the runner of scripts, and this runner is none", .{modifier.path});
    const kept_self = try host.arena.create(Modifier);
    kept_self.* = self;
    const kept_color = try host.arena.create(Color);
    kept_color.* = color;
    const self_handle = host.handleOf(Modifier, kept_self) orelse return failure.fail("{s}: the modifier cannot be handed to its script", .{modifier.path});
    const color_handle = host.handleOf(Color, kept_color) orelse return failure.fail("{s}: a kosm.Color cannot be handed to a script here", .{modifier.path});
    var call = host.call();
    const given = host.run(host.state, &call, modifier.file(), "apply", &.{ .{ .value = .{ .handle = self_handle } }, .{ .value = .{ .handle = color_handle } } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CallFailed => return failure.fail("{s}", .{call.message orelse "apply failed and did not say why"}),
    };
    var result = color;
    var diagnostics: Diagnostics = .{};
    var named = given;
    if (named.origin == null) named.origin = try host.arena.print("{s}: apply", .{modifier.path});
    assignment.assignNamed(Color, host.arena, &result, named, &diagnostics, "the color") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidAssignment => return failure.fail("{s}", .{diagnostics.message()}),
    };
    return result;
}

const testing = std.testing;

/// A host whose `apply` returns the color it is given halved in lightness, a hex string for
/// `colors/hex.lua`, text that is no color for `colors/wrong.lua`, and fails for
/// `colors/broken.lua`.
const TestHost = struct {
    fn run(state: *anyopaque, call: *Call, script: ScriptFile, function: []const u8, arguments: []const Loose) Call.Error!Loose {
        _ = state;
        std.debug.assert(std.mem.eql(u8, function, "apply"));
        if (std.mem.eql(u8, script.path, "colors/broken.lua")) return call.fail("colors/broken.lua:4: attempt to call a nil value", .{});
        if (std.mem.eql(u8, script.path, "colors/hex.lua")) return .{ .value = .{ .string = "#ff0000" } };
        if (std.mem.eql(u8, script.path, "colors/wrong.lua")) return .{ .value = .{ .string = "reddish" } };
        const self = arguments[0].value.handle.as(TestModifier).?;
        const color = arguments[1].value.handle.as(Color).?;
        color.lightness *= self.amount;
        return arguments[1];
    }

    fn handle(state: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle {
        _ = state;
        inline for (.{ Color, TestModifier }) |T| {
            if (id == Handle.id(T)) return .{ .pointer = pointer, .type = tableOf(T) };
        }
        return null;
    }

    /// A table good only for telling the handle's type; nothing reads through it.
    fn tableOf(comptime T: type) *const Handle.Type {
        return &struct {
            const table: Handle.Type = .{ .id = Handle.id(T), .name = @typeName(T), .get = undefined, .set = undefined, .length = undefined };
        }.table;
    }
};

const TestModifier = struct {
    amount: f64 = 0.5,
};

const test_color: Color = .{ .lightness = 0.8, .chroma = 0.1, .hue = 250 };

fn withTestHost(arena: std.mem.Allocator) Host {
    return .{ .state = undefined, .arena = arena, .run = TestHost.run, .handle = TestHost.handle };
}

test "apply gives the color the script returns, a Zig color or a hex string" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    failure.clear();
    const halve: ScriptModifier = .{ .frontend = "test", .path = "colors/halve.lua" };
    try testing.expectApproxEqAbs(0.4, halve.apply(TestModifier, .{}, test_color).lightness, 1e-12);
    try testing.expectApproxEqAbs(0.2, halve.apply(TestModifier, .{ .amount = 0.25 }, test_color).lightness, 1e-12);
    const hex: ScriptModifier = .{ .frontend = "test", .path = "colors/hex.lua" };
    try testing.expectEqualStrings("#ff0000ff", hex.apply(TestModifier, .{}, test_color).hex8().slice());
    try testing.expectEqual(null, failure.message());
}

test "a failing apply is recorded for kosm to report and keeps the color" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    defer failure.clear();
    failure.clear();
    const broken: ScriptModifier = .{ .frontend = "test", .path = "colors/broken.lua" };
    try testing.expectEqual(test_color, broken.apply(TestModifier, .{}, test_color));
    try testing.expectEqualStrings("colors/broken.lua:4: attempt to call a nil value", failure.message().?);
    failure.clear();
    const wrong: ScriptModifier = .{ .frontend = "test", .path = "colors/wrong.lua" };
    try testing.expectEqual(test_color, wrong.apply(TestModifier, .{}, test_color));
    try testing.expect(std.mem.startsWith(u8, failure.message().?, "colors/wrong.lua: apply"));
    failure.clear();
    Host.install(null);
    try testing.expectEqual(test_color, broken.apply(TestModifier, .{}, test_color));
    try testing.expectEqualStrings("colors/broken.lua: a modifier written through a frontend runs only in the runner of scripts, and this runner is none", failure.message().?);
}
