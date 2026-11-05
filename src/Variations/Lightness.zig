//! Absolute: ignores mode. Qt Light/Midlight/Dark/Shadow, Tailwind/Radix scales, ANSI bright.

const Lightness = @This();

const Modifier = @import("../Modifier.zig");

/// Default: lightness +0.3.
lightest: Modifier,
/// Default: lightness +0.2.
lighter: Modifier,
/// Default: lightness +0.1.
light: Modifier,
/// Default: lightness -0.1.
dark: Modifier,
/// Default: lightness -0.2.
darker: Modifier,
/// Default: lightness -0.3.
darkest: Modifier,
/// Terminal "bright" colors. Default: lightness +0.08, chroma +0.02.
bright: Modifier,
