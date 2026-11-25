//! A runner's arguments, sorted into kosm's own (`--diff`, `--stat`, `--reload`, `--set`, `--config`) and the kosmos'
//! parameters.

const Arguments = @This();

const std = @import("std");

/// Print the plan as a diff instead of committing it.
diff: bool = false,
/// With `diff`, print per app the files and lines changed instead of the whole diff.
stat: bool = false,
/// Reload every app after the commit, not only those whose files changed.
reload: bool = false,
/// The config project's absolute path, which `kosm apply` passes on for the record.
config: ?[]const u8 = null,
/// The `path=value` text of every `--set`, in order.
assignments: []const []const u8 = &.{},
/// Everything else, in order, for the kosmos' `Params`.
parameters: []const []const u8 = &.{},
/// The parameters and `--set`s as typed, for the record of the apply.
recorded: []const []const u8 = &.{},

pub const Error = error{ SetWithoutAssignment, ConfigWithoutDirectory, StatWithoutDiff, OutOfMemory };

/// Sorts `arguments` (without the program name); `--diff`, `--stat`, `--reload`, `--set
/// path=value` and `--config dir` may appear anywhere, and `--stat` only with `--diff`. The slices point into `arguments` and are allocated in
/// `arena`.
pub fn split(arena: std.mem.Allocator, arguments: []const []const u8) Error!Arguments {
    var diff = false;
    var stat = false;
    var reload = false;
    var config: ?[]const u8 = null;
    var assignments: std.ArrayList([]const u8) = .empty;
    var parameters: std.ArrayList([]const u8) = .empty;
    var recorded: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        if (std.mem.eql(u8, argument, "--diff")) {
            diff = true;
        } else if (std.mem.eql(u8, argument, "--stat")) {
            stat = true;
        } else if (std.mem.eql(u8, argument, "--reload")) {
            reload = true;
        } else if (std.mem.eql(u8, argument, "--config")) {
            index += 1;
            if (index == arguments.len) return error.ConfigWithoutDirectory;
            config = arguments[index];
        } else if (std.mem.eql(u8, argument, "--set")) {
            index += 1;
            if (index == arguments.len) return error.SetWithoutAssignment;
            try assignments.append(arena, arguments[index]);
            try recorded.appendSlice(arena, arguments[index - 1 .. index + 1]);
        } else {
            try parameters.append(arena, argument);
            try recorded.append(arena, argument);
        }
    }
    if (stat and !diff) return error.StatWithoutDiff;
    return .{ .diff = diff, .stat = stat, .reload = reload, .config = config, .assignments = assignments.items, .parameters = parameters.items, .recorded = recorded.items };
}

/// These arguments with `parameters` in place of the kosmos' parameters (as many, in the same
/// order), in the record as well.
pub fn withParameters(arguments: Arguments, arena: std.mem.Allocator, parameters: []const []const u8) std.mem.Allocator.Error!Arguments {
    std.debug.assert(parameters.len == arguments.parameters.len);
    const recorded = try arena.dupe([]const u8, arguments.recorded);
    var parameter_index: usize = 0;
    var index: usize = 0;
    while (index < recorded.len) : (index += 1) {
        // `split` takes every --set and its assignment out of the parameters.
        if (std.mem.eql(u8, recorded[index], "--set")) {
            index += 1;
            continue;
        }
        recorded[index] = parameters[parameter_index];
        parameter_index += 1;
    }
    var replaced = arguments;
    replaced.parameters = parameters;
    replaced.recorded = recorded;
    return replaced;
}

const testing = std.testing;

test "diff, config and every set are taken out, parameters keep their order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const arguments = try split(arena.allocator(), &.{ "--blur", "false", "--set", "kitty.opacity=1", "--diff", "--config", "/c", "--accent", "sky", "--set", "kitty=null" });
    try testing.expect(arguments.diff);
    try testing.expectEqualStrings("/c", arguments.config.?);
    try testing.expectEqual(2, arguments.assignments.len);
    try testing.expectEqualStrings("kitty.opacity=1", arguments.assignments[0]);
    try testing.expectEqualStrings("kitty=null", arguments.assignments[1]);
    try testing.expectEqual(4, arguments.parameters.len);
    try testing.expectEqualStrings("--accent", arguments.parameters[2]);
}

test "the record keeps parameters and sets in the order typed, without diff or config" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const arguments = try split(arena.allocator(), &.{ "--set", "kitty=null", "--diff", "--blur", "false", "--config", "/c" });
    try testing.expectEqual(4, arguments.recorded.len);
    try testing.expectEqualStrings("--set", arguments.recorded[0]);
    try testing.expectEqualStrings("kitty=null", arguments.recorded[1]);
    try testing.expectEqualStrings("--blur", arguments.recorded[2]);
    try testing.expectEqualStrings("false", arguments.recorded[3]);
}

test "--stat goes with --diff and is an error without it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const arguments = try split(arena.allocator(), &.{ "--stat", "--diff" });
    try testing.expect(arguments.diff and arguments.stat);
    try testing.expectEqual(0, arguments.recorded.len);
    try testing.expectError(error.StatWithoutDiff, split(arena.allocator(), &.{"--stat"}));
}

test "a trailing --set or --config is an error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.SetWithoutAssignment, split(arena.allocator(), &.{ "--diff", "--set" }));
    try testing.expectError(error.ConfigWithoutDirectory, split(arena.allocator(), &.{"--config"}));
}

test "replaced parameters reach the record in their places between the sets" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const arguments = try split(arena.allocator(), &.{ "--script", "x.lua", "--set", "kitty=null", "--blur", "false" });
    const replaced = try arguments.withParameters(arena.allocator(), &.{ "--script", "/work/x.lua", "--blur", "false" });
    try testing.expectEqualStrings("/work/x.lua", replaced.parameters[1]);
    try testing.expectEqual(6, replaced.recorded.len);
    try testing.expectEqualStrings("/work/x.lua", replaced.recorded[1]);
    try testing.expectEqualStrings("--set", replaced.recorded[2]);
    try testing.expectEqualStrings("kitty=null", replaced.recorded[3]);
    try testing.expectEqualStrings("false", replaced.recorded[5]);
}
