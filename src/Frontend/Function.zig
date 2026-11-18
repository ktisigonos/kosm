//! A Zig function a script calls: an app's `from`, a Zig kosmos, a color's method. Kosm builds
//! one per function by reflection; a frontend only calls it.

const Loose = @import("../Loose.zig");
const Call = @import("Call.zig");

/// As a script names it, for messages: "from", "mix".
name: []const u8,
/// Runs the function with `arguments`, each read into its parameter's type as `kosm.assign`
/// reads a value. A struct, union or list it returns comes back as a handle.
call: *const fn (call: *Call, arguments: []const Loose) Call.Error!Loose,
