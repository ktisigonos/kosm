//! Builds a `kosm.Value.joined` (D89) for a value kitty spells as one piece of text: literal text
//! goes to `writer`, while floats, booleans and colors become parts the adapter writes in the
//! file's format (D70), so a clipped color warns (D88).

const Joined = @This();

const std = @import("std");
const kosm = @import("kosm");

const Allocator = std.mem.Allocator;

allocator: Allocator,
parts: std.ArrayList(kosm.Value) = .empty,
text: std.Io.Writer.Allocating,

/// `error.WriteFailed` means out of memory: every part lives in the allocator.
pub const Error = std.Io.Writer.Error;

/// Parts and text live in `allocator`, typically the output's arena; `finish` hands them over.
pub fn init(allocator: Allocator) Joined {
    return .{ .allocator = allocator, .text = .init(allocator) };
}

/// Where literal text between values goes.
pub fn writer(joined: *Joined) *std.Io.Writer {
    return &joined.text.writer;
}

/// Adds a float, written at the file's `float_precision`.
pub fn float(joined: *Joined, value: f64) Error!void {
    try joined.append(.{ .float = value });
}

/// Adds floats with `separator` text between them.
pub fn floats(joined: *Joined, values: []const f64, separator: []const u8) Error!void {
    for (values, 0..) |number, index| {
        if (index != 0) try joined.writer().writeAll(separator);
        try joined.float(number);
    }
}

/// Adds a boolean, written in the file's `boolean` spelling.
pub fn boolean(joined: *Joined, value: bool) Error!void {
    try joined.append(.{ .boolean = value });
}

/// Adds a color, written in the file's color format.
pub fn color(joined: *Joined, value: kosm.Color) Error!void {
    try joined.append(.{ .color = value });
}

/// The finished value; its parts are owned by the allocator given to `init`.
pub fn finish(joined: *Joined) Error!kosm.Value {
    try joined.flushText();
    return .{ .joined = joined.parts.items };
}

fn append(joined: *Joined, part: kosm.Value) Error!void {
    try joined.flushText();
    joined.parts.append(joined.allocator, part) catch return error.WriteFailed;
}

fn flushText(joined: *Joined) Error!void {
    if (joined.text.written().len == 0) return;
    const text = joined.text.toOwnedSlice() catch return error.WriteFailed;
    joined.parts.append(joined.allocator, .{ .raw = text }) catch return error.WriteFailed;
}
