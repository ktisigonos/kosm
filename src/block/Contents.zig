//! Where a block's contents lie in its file: the bytes between its two marker lines.

/// First byte after the `kosm:begin` line.
start: usize,
/// First byte of the `kosm:end` line.
end: usize,
