//! Readable foreground on top of this color. Material onPrimary, libadwaita accent_fg_color.

const Contrast = @This();

const Modifier = @import("../Modifier.zig");

/// Default: the palette's black or white, whichever has the higher contrast ratio.
on: Modifier,
/// Default: `on`, mixed 30% back toward the color.
on_muted: Modifier,
