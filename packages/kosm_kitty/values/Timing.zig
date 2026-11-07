//! A duration in seconds, optionally animated with easing functions.

const Timing = @This();

const Joined = @import("../Joined.zig");
const values = @import("../values.zig");

/// The duration in seconds; what 0 and negative values mean depends on the option.
seconds: f64,
/// The easing of the animation, or of its first half; null: not animated.
easing: ?values.Easing = null,
/// The easing of the animation's second half; null: same as `easing`.
second_easing: ?values.Easing = null,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(timing: Timing, joined: *Joined) Joined.Error!void {
    try joined.float(timing.seconds);
    for ([_]?values.Easing{ timing.easing, timing.second_easing }) |optional_easing| {
        if (optional_easing) |easing| {
            try joined.writer().writeByte(' ');
            try easing.write(joined);
        }
    }
}
