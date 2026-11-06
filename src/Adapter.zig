//! Support for one language or file format (D39, D54). Every capability is optional, and kosm
//! names the missing one when an app needs it. An adapter never knows about any app (D1).

const Adapter = @This();

const std = @import("std");
const Format = @import("Format.zig");
const Value = @import("value.zig").Value;

/// The language name apps pass as `.lang`, e.g. "css".
name: []const u8,
/// File extensions this adapter claims, with the dot (".css"). Picked from the file name
/// unless the app passes `.lang` (D26).
extensions: []const []const u8 = &.{},
/// How this language spells values where neither the app nor the user chose (D70).
/// Named apart from the `format` capability (D39).
default_format: Format = .{},
/// Writes one value as source text (`true`, `"text"`, `1.5`); with `parser`, enables `edit` (D42).
format: ?*const fn (writer: *std.Io.Writer, value: Value, context: *Context) Error!void = null,
/// Reads a file into a tree of keys and values; with `format`, enables `edit` (D39).
/// `kosm.treesitter.parser` builds one from node names (D40). The tree may point into `source`.
parser: ?*const fn (allocator: std.mem.Allocator, source: []const u8, context: *Context) ParseError!Node = null,
/// Writes a whole file from a value tree; enables `generate` and data blocks (D71).
serialize: ?*const fn (writer: *std.Io.Writer, root: Value, context: *Context) Error!void = null,
/// How this language writes a comment on a line of its own; enables `block` (D72).
comment: ?Comment = null,

/// What a capability gets besides its input: the file's format and a place to explain
/// a failure.
pub const Context = @import("Adapter/Context.zig");

/// A language's comment syntax: `.{ .line = "#" }` or `.{ .block = .{ .open = "/*", .close = "*/" } }`.
pub const Comment = union(enum) {
    /// Starts a comment running to the end of the line ("#", "--").
    line: []const u8,
    /// Wraps a comment in delimiters.
    block: BlockComment,
};

/// Delimiters of a `Comment.block`.
pub const BlockComment = @import("Adapter/BlockComment.zig");

/// Errors a capability may return. Return `UnsupportedValue` through `Context.unsupported`.
pub const Error = std.Io.Writer.Error || error{UnsupportedValue};

/// Errors a `parser` may return. Return `InvalidSyntax` through `Context.invalidSyntax`.
pub const ParseError = std.mem.Allocator.Error || error{InvalidSyntax};

/// One entry of a parsed file.
pub const Node = @import("Adapter/Node.zig");

/// A byte range of a file's contents.
pub const Range = @import("Adapter/Range.zig");

/// Whether this adapter claims `extension` (".css").
pub fn claims(adapter: Adapter, extension: []const u8) bool {
    for (adapter.extensions) |claimed| {
        if (std.mem.eql(u8, claimed, extension)) return true;
    }
    return false;
}
