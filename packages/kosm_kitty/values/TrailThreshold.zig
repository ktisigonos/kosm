//! How many cells the cursor must move before its trail starts.

const TrailThreshold = @This();

const Joined = @import("../Joined.zig");

/// Cells moved horizontally, or in both directions when `vertical` is null.
horizontal: u32,
/// Cells moved vertically; null: same as `horizontal`.
vertical: ?u32 = null,

/// Writes the value the way kitty.conf spells it, numbers in the file's format.
pub fn write(threshold: TrailThreshold, joined: *Joined) Joined.Error!void {
    try joined.float(threshold.horizontal);
    if (threshold.vertical) |vertical| {
        try joined.writer().writeByte(' ');
        try joined.float(vertical);
    }
}
