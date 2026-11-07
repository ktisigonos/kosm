//! What the bell does (`bell-features`). Null flags keep ghostty's defaults.

const BellFeatures = @This();

const std = @import("std");
const values = @import("../values.zig");

/// Use the system bell. ghostty's default: off.
system: ?bool = null,
/// Play `bell_audio_path`. ghostty's default: off.
audio: ?bool = null,
/// Request attention for the window. ghostty's default: on.
attention: ?bool = null,
/// Show a bell emoji in the title. ghostty's default: on.
title: ?bool = null,
/// Flash a border around the terminal. ghostty's default: off.
border: ?bool = null,

/// Writes the set flags the way ghostty spells them (`system,no-border`).
pub fn format(flags: BellFeatures, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return values.writeFlags(flags, writer);
}
