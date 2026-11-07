//! `kosm source [<dir> | --default]` (D98): which kosm sources builds use on this machine. With
//! a directory it records it as the override, with `--default` it removes the override, and with
//! nothing it prints which sources builds use and why.

const std = @import("std");
const Sources = @import("Sources.zig");

/// Runs the command; returns the exit status after printing what it did or why it failed.
pub fn source(init: std.process.Init, argument: ?[]const u8, stderr: *std.Io.Writer) !u8 {
    const arena = init.arena.allocator();
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};
    const path = try Sources.overridePath(arena, init.environ_map) orelse {
        try stderr.writeAll("error: neither XDG_STATE_HOME nor HOME is set, so there is no state directory\n");
        return 1;
    };
    if (argument) |given| {
        if (std.mem.eql(u8, given, "--default")) {
            const removed = Sources.removeOverride(init.io, path) catch |err| {
                try stderr.print("error: cannot remove {s}: {s}\n", .{ path, @errorName(err) });
                return 1;
            };
            if (!removed) try stdout.interface.writeAll("no override was set\n");
        } else if (std.mem.startsWith(u8, given, "-")) {
            try stderr.print("error: unknown option '{s}'; kosm source takes a directory or --default\n", .{given});
            return 1;
        } else if (!try record(init, path, given, stderr)) return 1;
    }
    return printSources(init, path, &stdout.interface, stderr);
}

/// Records `given` as the override once it is known to hold kosm's sources; returns whether it did.
fn record(init: std.process.Init, path: []const u8, given: []const u8, stderr: *std.Io.Writer) !bool {
    const arena = init.arena.allocator();
    const directory = std.Io.Dir.cwd().realPathFileAlloc(init.io, given, arena) catch |err| {
        try stderr.print("error: cannot open {s}: {s}\n", .{ given, @errorName(err) });
        return false;
    };
    if (!try Sources.holdsKosm(init.io, arena, directory)) {
        try stderr.print("error: {s} holds no kosm sources: its build.zig.zon is missing or not named kosm\n", .{directory});
        return false;
    }
    Sources.saveOverride(init.io, path, directory) catch |err| {
        try stderr.print("error: cannot write {s}: {s}\n", .{ path, @errorName(err) });
        return false;
    };
    return true;
}

/// Prints which sources builds use now, and why.
fn printSources(init: std.process.Init, path: []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !u8 {
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const found = Sources.find(init.io, init.arena.allocator(), init.environ_map, &diagnostics) catch |err| {
        switch (err) {
            error.ParseZon => try stderr.print("{f}\n", .{diagnostics.fmt(path)}),
            else => try stderr.print("error: cannot read {s}: {s}\n", .{ path, @errorName(err) }),
        }
        return 1;
    };
    const sources = found orelse {
        try stdout.writeAll("builds use the kosm each config pins in its build.zig.zon\n");
        return 0;
    };
    switch (sources.origin) {
        .override => try stdout.print("builds use {s} (set with kosm source, in {s})\n", .{ sources.directory, path }),
        .installed => try stdout.print("builds use {s} (installed beside this kosm)\n", .{sources.directory}),
    }
    return 0;
}
