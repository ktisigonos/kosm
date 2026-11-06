//! A runner's arguments, sorted into kosm's own (`--diff`, `--set`, `--config`) and the kosmos'
//! parameters.

const Arguments = @This();

const std = @import("std");

/// Print the plan as a diff instead of committing it (D37).
diff: bool = false,
/// The config project's absolute path, which `kosm apply` passes on for the record (D75).
config: ?[]const u8 = null,
/// The `path=value` text of every `--set`, in order (D20).
assignments: []const []const u8 = &.{},
/// Everything else, in order, for the kosmos' `Params` (D19).
parameters: []const []const u8 = &.{},
/// The parameters and `--set`s as typed, for the record of the apply (D75).
recorded: []const []const u8 = &.{},

pub const Error = error{ SetWithoutAssignment, ConfigWithoutDirectory, OutOfMemory };

/// Sorts `arguments` (without the program name); `--diff`, `--set path=value` and
/// `--config dir` may appear anywhere. The slices point into `arguments` and are allocated in
/// `arena`.
pub fn split(arena: std.mem.Allocator, arguments: []const []const u8) Error!Arguments {
    var diff = false;
    var config: ?[]const u8 = null;
    var assignments: std.ArrayList([]const u8) = .empty;
    var parameters: std.ArrayList([]const u8) = .empty;
    var recorded: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        if (std.mem.eql(u8, argument, "--diff")) {
            diff = true;
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
    return .{ .diff = diff, .config = config, .assignments = assignments.items, .parameters = parameters.items, .recorded = recorded.items };
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

test "a trailing --set or --config is an error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.SetWithoutAssignment, split(arena.allocator(), &.{ "--diff", "--set" }));
    try testing.expectError(error.ConfigWithoutDirectory, split(arena.allocator(), &.{"--config"}));
}
