//! What `kosm doctor` checks for an app, which gives it from `pub fn checkup(self: App)
//! kosm.Checkup`: that its program is installed, and that the program reads the app's files.

const Checkup = @This();

/// How the program is found; null checks for none.
program: ?Program = null,
/// Each file of the program that must read a file the app writes, and the line that does.
includes: []const Include = &.{},

pub const Program = @import("Checkup/Program.zig");
pub const Include = @import("Checkup/Include.zig");
