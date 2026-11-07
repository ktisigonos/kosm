//! The parameter of the `resize_split` action.

const ResizeSplit = @This();

/// Which way the split's edge moves.
direction: enum { up, down, left, right },
/// How far, in pixels.
pixels: u16,
