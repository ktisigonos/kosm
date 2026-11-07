//! How far one step of the mouse wheel scrolls, per kind of device; clamped by ghostty to 0.01..10000.

const MouseScrollMultiplier = @This();

const Joined = @import("../Joined.zig");

/// Touchpads and other precise devices. null: ghostty's default, `1`.
precision: ?f64 = null,
/// Mouse wheels that scroll in steps. null: ghostty's default, `3`.
discrete: ?f64 = null,

/// Writes the value the way ghostty spells it (`precision:1,discrete:3`), numbers in the file's format.
pub fn write(multiplier: MouseScrollMultiplier, joined: *Joined) Joined.Error!void {
    if (multiplier.precision) |precision| {
        try joined.writer().writeAll("precision:");
        try joined.float(precision);
    }
    if (multiplier.discrete) |discrete| {
        if (multiplier.precision != null) try joined.writer().writeByte(',');
        try joined.writer().writeAll("discrete:");
        try joined.float(discrete);
    }
}
