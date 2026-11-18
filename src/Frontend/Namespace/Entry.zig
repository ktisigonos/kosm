//! One name in a namespace.

const Function = @import("../Function.zig");
const Namespace = @import("../Namespace.zig");

name: []const u8,
kind: Kind,

pub const Kind = union(enum) {
    function: Function,
    namespace: *const Namespace,
    /// A value declared once (`krystallos.look`): calling it with no arguments gives a fresh
    /// copy each time, so changing one never changes the declaration.
    constant: Function,
};
