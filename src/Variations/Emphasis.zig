//! Mode-aware: more or less contrast against the background. Apple label hierarchy, Radix steps 11-12, GTK dim-label.

const Emphasis = @This();

const Modifier = @import("../Modifier.zig");

/// Default: 0.08 lightness away from the background.
strong: Modifier,
/// Default: 0.2 lightness toward the background, chroma -0.02.
muted: Modifier,
/// Default: 0.3 lightness toward the background, chroma -0.03.
subtle: Modifier,
/// Default: 0.4 lightness toward the background, chroma -0.04.
faint: Modifier,
