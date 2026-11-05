//! Mode-aware elevation. GTK shade/card/popover, Material surface containers, Qt Shadow.

const Surface = @This();

const Modifier = @import("../Modifier.zig");

/// Default: 0.04 lightness toward the background.
sunken: Modifier,
/// Default: 0.04 lightness away from the background.
raised: Modifier,
/// Default: 0.08 lightness away from the background.
overlay: Modifier,
/// Dark in both modes. Default: 80% toward the palette's black, alpha 0.5.
shadow: Modifier,
