//! Formatted color text with fixed capacity, so formatting needs no allocator.

const Text = @This();

buffer: [capacity]u8 = undefined,
length: usize = 0,

/// Maximum formatted length in bytes, checked at compile time by `format`.
pub const capacity = 256;

/// The formatted text. Valid while this `Text` lives.
pub fn slice(text: *const Text) []const u8 {
    return text.buffer[0..text.length];
}

/// Appends bytes; the caller guarantees they fit (`Color.format` checks at compile time).
pub fn append(text: *Text, bytes: []const u8) void {
    @memcpy(text.buffer[text.length..][0..bytes.len], bytes);
    text.length += bytes.len;
}
