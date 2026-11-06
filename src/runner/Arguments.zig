//! A runner's arguments, sorted into kosm's own (`--diff`, `--set`) and the kosmos' parameters.

const Arguments = @This();

const std = @import("std");

/// Print the plan as a diff instead of committing it (D37).
diff: bool = false,
/// The `path=value` text of every `--set`, in order (D20).
assignments: []const []const u8 = &.{},
/// Everything else, in order, for the kosmos' `Params` (D19).
parameters: []const []const u8 = &.{},

pub const Error = error{ SetWithoutAssignment, OutOfMemory };

/// Sorts `arguments` (without the program name); `--diff` and `--set path=value` may appear
/// anywhere. The slices point into `arguments` and are allocated in `arena`.
pub fn split(arena: std.mem.Allocator, arguments: []const []const u8) Error!Arguments {
    var diff = false;
    var assignments: std.ArrayList([]const u8) = .empty;
    var parameters: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        if (std.mem.eql(u8, argument, "--diff")) {
            diff = true;
        } else if (std.mem.eql(u8, argument, "--set")) {
            index += 1;
            if (index == arguments.len) return error.SetWithoutAssignment;
            try assignments.append(arena, arguments[index]);
        } else try parameters.append(arena, argument);
    }
    return .{ .diff = diff, .assignments = assignments.items, .parameters = parameters.items };
}

const testing = std.testing;

test "diff and every set are taken out, parameters keep their order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const arguments = try split(arena.allocator(), &.{ "--blur", "false", "--set", "kitty.opacity=1", "--diff", "--accent", "sky", "--set", "kitty=null" });
    try testing.expect(arguments.diff);
    try testing.expectEqual(2, arguments.assignments.len);
    try testing.expectEqualStrings("kitty.opacity=1", arguments.assignments[0]);
    try testing.expectEqualStrings("kitty=null", arguments.assignments[1]);
    try testing.expectEqual(4, arguments.parameters.len);
    try testing.expectEqualStrings("--accent", arguments.parameters[2]);
}

test "a trailing --set is an error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.SetWithoutAssignment, split(arena.allocator(), &.{ "--diff", "--set" }));
}
