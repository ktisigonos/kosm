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

/// A list of `length` items kept like `keep`, for a list whose length is known only at run
/// time, like `allocator.alloc(T, length)`. Every item is undefined until set.
pub fn keepList(comptime T: type, length: usize) []T {
    // A kosmos cannot handle running out of memory; kosm stops with this message instead.
    return arena_state.allocator().alloc(T, length) catch @panic("kosm.keepList: out of memory");
}

/// Text formatted like `std.fmt.bufPrint`, kept like `keep` for the whole run, so a package
/// builds a string from values known only at run time without an allocator:
/// `kosm.keepPrint("{s} {d}", .{ family, size })`.
pub fn keepPrint(comptime format: []const u8, arguments: anytype) []const u8 {
    // A kosmos cannot handle running out of memory; kosm stops with this message instead.
    return arena_state.allocator().print(format, arguments) catch @panic("kosm.keepPrint: out of memory");
}

fn keptSquares(count: usize) []const u8 {
    const squares = keepList(u8, count);
    for (squares, 0..) |*square, index| square.* = @intCast(index * index);
    return squares;
}

fn keptFont(family: []const u8, size: f64) []const u8 {
    var buffer: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&buffer, "{s} Bold", .{family}) catch unreachable;
    return keepPrint("{s} {d}", .{ name, size });
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

test "kept text of run-time values outlives the function writing it" {
    var size: f64 = 13.5;
    std.mem.doNotOptimizeAway(&size);
    const kept = keptFont("Iosevka", size);
    _ = overwriteStack(0xff);
    try std.testing.expectEqualStrings("Iosevka Bold 13.5", kept);
}

test "a kept list of run-time length outlives the function filling it" {
    var count: usize = 4;
    std.mem.doNotOptimizeAway(&count);
    const kept = keptSquares(count);
    _ = overwriteStack(0xff);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 4, 9 }, kept);
}
