//! Mode-aware: libadwaita borders, Material outline / outlineVariant.

const Line = @This();

const Modifier = @import("../Modifier.zig");

/// Default: 0.12 lightness away from the background.
border: Modifier,
/// Default: 0.22 lightness away from the background.
border_strong: Modifier,
/// Default: 0.07 lightness away from the background.
separator: Modifier,
