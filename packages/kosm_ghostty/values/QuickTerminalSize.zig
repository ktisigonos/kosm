//! The size of the quick terminal: height for one at the top or bottom, width for one at a side,
//! and optionally the other dimension.

const QuickTerminalSize = @This();

const Joined = @import("../Joined.zig");

/// The size along the axis the quick terminal slides in on.
primary: Size,
/// The other size; null: the full screen, or ghostty's choice when centered.
secondary: ?Size = null,

/// A percentage of the screen, or pixels.
pub const Size = union(enum) {
    percent: f64,
    pixels: u32,

    fn write(size: Size, joined: *Joined) Joined.Error!void {
        switch (size) {
            .percent => |percent| {
                try joined.float(percent);
                try joined.writer().writeByte('%');
            },
            .pixels => |pixels| try joined.writer().print("{d}px", .{pixels}),
        }
    }
};

/// Writes the value the way ghostty spells it (`50%,500px`), numbers in the file's format.
pub fn write(size: QuickTerminalSize, joined: *Joined) Joined.Error!void {
    try size.primary.write(joined);
    if (size.secondary) |secondary| {
        try joined.writer().writeByte(',');
        try secondary.write(joined);
    }
}
