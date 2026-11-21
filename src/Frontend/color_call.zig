//! Running the `apply` of a modifier or palette style written through a frontend: hands the
//! script its fields and colors, and reads the color it returns.

const std = @import("std");
const Loose = @import("../Loose.zig");
const Color = @import("../Color.zig");
const Diagnostics = @import("../Diagnostics.zig");
const assignment = @import("../assignment.zig");
const failure = @import("../failure.zig");
const Host = @import("Host.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The most colors an `apply` takes after its fields.
const max_colors = 2;

/// The color the script's `apply(self, colors...)` gives. It cannot fail: a failure is
/// recorded like `kosm.fail`'s message, which kosm reports before anything is written, and
/// `colors[0]` is given unchanged. `noun` names what the script gives, for messages: "a modifier".
pub fn apply(comptime Self: type, script: ScriptFile, noun: []const u8, self: Self, colors: []const Color) Color {
    return run(Self, script, noun, self, colors) catch |err| {
        switch (err) {
            error.OutOfMemory => failure.record("{s}: out of memory", .{script.path}),
            // `run` recorded why.
            error.KosmosFailed => {},
        }
        return colors[0];
    };
}

fn run(comptime Self: type, script: ScriptFile, noun: []const u8, self: Self, colors: []const Color) (std.mem.Allocator.Error || failure.Error)!Color {
    std.debug.assert(colors.len >= 1 and colors.len <= max_colors);
    const host = Host.current() orelse return failure.fail("{s}: {s} written through a frontend runs only in the runner of scripts, and this runner is none", .{ script.path, noun });
    var arguments: [1 + max_colors]Loose = undefined;
    const kept_self = try host.arena.create(Self);
    kept_self.* = self;
    const self_handle = host.handleOf(Self, kept_self) orelse return failure.fail("{s}: its fields cannot be handed to its script", .{script.path});
    arguments[0] = .{ .value = .{ .handle = self_handle } };
    for (colors, arguments[1 .. 1 + colors.len]) |color, *argument| {
        const kept = try host.arena.create(Color);
        kept.* = color;
        const handle = host.handleOf(Color, kept) orelse return failure.fail("{s}: a kosm.Color cannot be handed to a script here", .{script.path});
        argument.* = .{ .value = .{ .handle = handle } };
    }
    var call = host.call();
    const given = host.run(host.state, &call, script, "apply", arguments[0 .. 1 + colors.len]) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CallFailed => return failure.fail("{s}", .{call.message orelse "apply failed and did not say why"}),
    };
    var result = colors[0];
    var diagnostics: Diagnostics = .{};
    var named = given;
    if (named.origin == null) named.origin = try host.arena.print("{s}: apply", .{script.path});
    assignment.assignNamed(Color, host.arena, &result, named, &diagnostics, "the color") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidAssignment => return failure.fail("{s}", .{diagnostics.message()}),
    };
    return result;
}
