//! Low-alpha washes. Material state layers, editor selection / search highlights.

const Alpha = @This();

const Modifier = @import("../Modifier.zig");

/// Default: alpha 0.5.
translucent: Modifier,
/// Default: alpha 0.25.
highlight: Modifier,
