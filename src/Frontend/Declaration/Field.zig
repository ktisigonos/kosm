//! One field of an app, modifier or palette style a script declares.

const Declaration = @import("../Declaration.zig");
const Loose = @import("../../Loose.zig");

name: []const u8,
/// The doc comment written above it, without the comment markers; null for none.
doc: ?[]const u8 = null,
type: Declaration.Type,
/// The value it starts with: a boolean, integer, float or string for a scalar. Null takes the
/// type's own default, which a boolean, integer, float or text field does not have.
default: ?Loose = null,
/// The line it is written on, for messages; 0 when unknown.
line: usize = 0,
