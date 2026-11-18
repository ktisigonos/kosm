//! Every Zig function, value and namespace a script may call, which kosm hands a frontend's
//! `load` so a script can build on Zig code: `kosmoi`, `kosm` and every package.

const Namespace = @import("Namespace.zig");
const Call = @import("Call.zig");
const std = @import("std");

/// Each one a global of the script, named after `Namespace.name`.
globals: []const *const Namespace = &.{},
/// Kosm's own, which every `Call` carries.
state: ?*anyopaque = null,

/// A call made through this library, allocating in `arena`.
pub fn call(library: @This(), arena: std.mem.Allocator) Call {
    return .{ .arena = arena, .state = library.state };
}
