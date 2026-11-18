//! A kosmos failing with a message of its own, which kosm prints as given.

const std = @import("std");

/// The error a kosmos returns through `fail`.
pub const Error = error{KosmosFailed};

/// Room for one message; longer ones are cut short.
const message_capacity = 1024;

/// The message `fail` recorded last. A global, because a kosmos takes no diagnostics or
/// allocator; kosm runs one kosmos per process and reads it once the kosmos has returned.
var message_buffer: [message_capacity]u8 = undefined;
var message_length: ?usize = null;

/// Stops the kosmos with a message kosm prints as given, instead of a bare error name:
/// `return kosm.fail("personal.lua:{d}: expected an integer, got \"{s}\"", .{ line, text })`.
/// Too-long messages are cut short.
pub fn fail(comptime format: []const u8, arguments: anytype) Error {
    const written = std.fmt.bufPrint(&message_buffer, format, arguments) catch message_buffer[0..];
    message_length = written.len;
    return error.KosmosFailed;
}

/// For kosm's runner: the message `fail` recorded since the last `clear`, or null.
pub fn message() ?[]const u8 {
    const length = message_length orelse return null;
    return message_buffer[0..length];
}

/// For kosm's runner: forgets the recorded message.
pub fn clear() void {
    message_length = null;
}

fn failingKosmos(line: u32) Error!void {
    return fail("personal.lua:{d}: hyprland.general.gaps_in: expected an integer, got \"{s}\"", .{ line, "big" });
}

test "fail records its message until cleared" {
    clear();
    defer clear();
    try std.testing.expectEqual(null, message());
    try std.testing.expectError(error.KosmosFailed, failingKosmos(42));
    try std.testing.expectEqualStrings("personal.lua:42: hyprland.general.gaps_in: expected an integer, got \"big\"", message().?);
}

test "a too-long message is cut short" {
    defer clear();
    const long: [2 * message_capacity]u8 = @splat('x');
    try std.testing.expectEqual(error.KosmosFailed, fail("{s}", .{&long}));
    try std.testing.expectEqual(message_capacity, message().?.len);
}
