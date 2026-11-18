//! Another kosmos a kosmos builds on, named in its `Params` the way an image is.

const std = @import("std");

/// A kosmos (Zig or script) whose tree is a `Tree`, named in a kosmos' `Params`:
/// `on: kosm.Kosmos(Apps) = .{ .name = "personal.nord" }`. Kosm builds it before calling the
/// kosmos naming it, which then takes its tree with `tree()` and assigns its own values on it.
pub fn Kosmos(comptime TreeType: type) type {
    return struct {
        const Self = @This();

        /// The tree the named kosmos gives.
        pub const Tree = TreeType;

        /// The kosmos as `kosm apply` spells it: "personal", "personal.nord". A flag or a
        /// script names another one, whose tree must be a `Tree` too.
        name: []const u8,
        /// Its tree. Kosm builds it for every kosmos named in a kosmos' `Params` before calling
        /// it; one named anywhere else has none, and taking its tree fails.
        built: ?*const Tree = null,

        /// A copy of the named kosmos' tree, for the caller to assign its own values on.
        pub fn tree(kosmos: Self) Error!Tree {
            const built = kosmos.built orelse return error.KosmosNotBuilt;
            return built.*;
        }
    };
}

pub const Error = error{
    /// The kosmos was not built: kosm builds only the kosmoi a kosmos names in its `Params`.
    KosmosNotBuilt,
};

/// Whether `T` is a `Kosmos` of some tree.
pub fn is(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct" or !@hasDecl(T, "Tree")) return false;
    if (@TypeOf(T.Tree) != type) return false;
    return T == Kosmos(T.Tree);
}

test "a kosmos kosm did not build has no tree, a built one gives a copy" {
    const Tree = struct { size: u32 };
    const unbuilt: Kosmos(Tree) = .{ .name = "frost" };
    try std.testing.expectError(error.KosmosNotBuilt, unbuilt.tree());
    const original: Tree = .{ .size = 3 };
    const built: Kosmos(Tree) = .{ .name = "frost", .built = &original };
    var copy = try built.tree();
    copy.size = 4;
    try std.testing.expectEqual(3, original.size);
}

test "only a Kosmos of some tree is one" {
    const Apps = struct { size: u32 };
    try std.testing.expect(is(Kosmos(Apps)));
    try std.testing.expect(!is(Apps));
    try std.testing.expect(!is(struct {
        pub const Tree = u8;
    }));
    try std.testing.expect(!is(u8));
}
