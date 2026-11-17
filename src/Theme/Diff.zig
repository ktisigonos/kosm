//! Colors for changes between versions: diffs, version-control gutters and status, merge tools
//! and file managers marking changed files.

const Diff = @This();

const std = @import("std");
const Color = @import("../Color.zig");
const Roles = @import("Roles.zig");

/// Added lines and new files. Default: the success role.
added: Color,
/// Changed lines and modified files. Default: the warning role.
changed: Color,
/// Removed lines and deleted files. Default: the error role.
removed: Color,

/// The diff colors a kosmos sets itself, each optional.
pub const Overrides = @import("Diff/Overrides.zig");

/// Every diff color `overrides` leaves null from the `roles`.
pub fn from(roles: Roles, overrides: Overrides) Diff {
    return .{
        .added = overrides.added orelse roles.success,
        .changed = overrides.changed orelse roles.warning,
        .removed = overrides.removed orelse roles.@"error",
    };
}

test "every diff color can be overridden" {
    try std.testing.expectEqualDeep(
        std.meta.fieldNames(Diff),
        std.meta.fieldNames(Overrides),
    );
}
