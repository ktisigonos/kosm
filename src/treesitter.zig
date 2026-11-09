//! The tree-sitter runtime kosm owns, for adapters whose parser is declared by node names
//!. An adapter package fetches only its grammar and declares its entry point:
//! `extern fn tree_sitter_json() callconv(.c) *const kosm.treesitter.Language;`.

const std = @import("std");
const c = @import("tree_sitter_api");
const Adapter = @import("Adapter.zig");

/// A grammar, as its `tree_sitter_<name>` function returns it.
pub const Language = c.TSLanguage;
/// A grammar's node names for keys and values.
pub const Spec = @import("treesitter/Spec.zig");
/// A grammar's entry point.
pub const LanguageFunction = *const fn () callconv(.c) *const Language;

const Builder = @import("treesitter/Builder.zig");

/// An adapter `parser` reading files with `language` and finding keys by `spec`'s node names.
/// A file with a syntax error is refused, naming its line and column.
pub fn parser(comptime language: LanguageFunction, comptime spec: Spec) *const fn (std.mem.Allocator, []const u8, *Adapter.Context) Adapter.ParseError!Adapter.Node {
    return struct {
        fn parse(allocator: std.mem.Allocator, source: []const u8, context: *Adapter.Context) Adapter.ParseError!Adapter.Node {
            return Builder.parse(allocator, language(), spec, source, context);
        }
    }.parse;
}
