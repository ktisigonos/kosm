//! A length of time, written in ghostty's units (`1h30m`, `750ms`). Parts add up.

const Duration = @This();

const std = @import("std");

/// Whole hours.
hours: u32 = 0,
/// Whole minutes, added to the hours.
minutes: u32 = 0,
/// Whole seconds, added to the rest.
seconds: u32 = 0,
/// Milliseconds, added to the rest.
milliseconds: u32 = 0,

/// Writes the value the way ghostty spells it; zero is `0ms`.
pub fn format(duration: Duration, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (duration.hours != 0) try writer.print("{d}h", .{duration.hours});
    if (duration.minutes != 0) try writer.print("{d}m", .{duration.minutes});
    if (duration.seconds != 0) try writer.print("{d}s", .{duration.seconds});
    const nothing_written = duration.hours == 0 and duration.minutes == 0 and duration.seconds == 0;
    if (duration.milliseconds != 0 or nothing_written) try writer.print("{d}ms", .{duration.milliseconds});
}
