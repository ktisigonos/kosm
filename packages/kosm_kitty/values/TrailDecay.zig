//! The cursor trail's decay times in seconds.

const TrailDecay = @This();

const std = @import("std");

/// The fastest decay time.
fastest: f64,
/// The slowest decay time, at least `fastest`.
slowest: f64,

/// Writes the value the way kitty.conf spells it.
pub fn format(decay: TrailDecay, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{d} {d}", .{ decay.fastest, decay.slowest });
}
