//! The diff colors a kosmos sets itself; every one left null takes its default from a role.

const Color = @import("../../Color.zig");

/// Added lines and new files. null: the success role.
added: ?Color = null,
/// Changed lines and modified files. null: the warning role.
changed: ?Color = null,
/// Removed lines and deleted files. null: the error role.
removed: ?Color = null,
