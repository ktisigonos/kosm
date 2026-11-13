//! One change an adapter's `insert` makes to put a new entry into a table or list: a byte
//! range of the file's contents and the bytes replacing it.

/// First byte replaced; equal to `end` when bytes are only added.
start: usize,
/// One past the last byte replaced.
end: usize,
/// The bytes written in place of the range.
content: []const u8,
