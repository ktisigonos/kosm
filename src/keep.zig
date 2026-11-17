//! Copies of lists a kosmos builds from values known only at run time, kept for the whole run.

const std = @import("std");

/// Holds every kept list until the process ends. A global, because a kosmos takes no
/// allocator; kosm runs one kosmos per process, on one thread.
var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

/// A copy of `items` that stays valid after the function writing it returns, like
/// `allocator.dupe(T, items)`. A list of values known only at run time
/// (`&.{ theme.palette.blue }` with a theme from an image or `Params`) lives in the function
/// writing it and turns to garbage once it returns; kosm refuses to apply a tree holding one.
/// Lists of constants need no keeping. Shallow: lists inside the items need their own `keep`.
pub fn keep(comptime T: type, items: []const T) []const T {
    // A kosmos cannot handle running out of memory; kosm stops with this message instead.
    return arena_state.allocator().dupe(T, items) catch @panic("kosm.keep: out of memory");
}

fn keptBlue(blue: u8) []const u8 {
    return keep(u8, &.{ blue, blue });
}

fn overwriteStack(seed: u8) u8 {
    var buffer: [256]u8 = @splat(seed);
    std.mem.doNotOptimizeAway(&buffer);
    return buffer[0];
}

test "a kept list of run-time values outlives the function writing it" {
    var blue: u8 = 7;
    std.mem.doNotOptimizeAway(&blue);
    const kept = keptBlue(blue);
    _ = overwriteStack(0xff);
    try std.testing.expectEqualSlices(u8, &.{ 7, 7 }, kept);
}
