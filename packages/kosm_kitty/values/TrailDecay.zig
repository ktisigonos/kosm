//! The cursor trail's decay times in seconds.

const TrailDecay = @This();

const Joined = @import("../Joined.zig");

/// The fastest decay time.
fastest: f64,
/// The slowest decay time, at least `fastest`.
slowest: f64,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(decay: TrailDecay, joined: *Joined) Joined.Error!void {
    try joined.floats(&.{ decay.fastest, decay.slowest }, " ");
}
