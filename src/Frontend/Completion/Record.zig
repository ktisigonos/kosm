//! A struct a script may set, as `Completion` describes it.

const Completion = @import("../Completion.zig");

/// Unique among the records: "kosm_kitty.App".
name: []const u8,
/// The struct's doc comment, without the slashes; null when it has none.
doc: ?[]const u8 = null,
fields: []const Completion.Field,
/// Functions a script calls on a value of this type (`color:mix(other, 0.5)`), each with the
/// value itself as its first parameter.
methods: []const Completion.Function = &.{},
