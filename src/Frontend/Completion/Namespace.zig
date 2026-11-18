//! A name a script reaches functions and values through (`kosm_kitty`, `kosm.Theme`,
//! `kosmoi.personal`), as `Completion` describes it.

const Completion = @import("../Completion.zig");

/// From the global down: "kosm.Theme".
name: []const u8,
doc: ?[]const u8 = null,
/// What calling the namespace itself does, or null.
call: ?Completion.Function = null,
functions: []const Completion.Function = &.{},
/// Values, and the namespaces inside it typed `.namespace`.
values: []const Completion.Field = &.{},
