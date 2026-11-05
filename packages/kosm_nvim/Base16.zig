//! The 16 base16 slots, named as base16 names them.

const kosm = @import("kosm");

/// Default background. Default: black, white in light mode.
base00: kosm.Color,
/// Lighter background (status bars, line numbers). Default: `surface.raised` of `base00`.
base01: kosm.Color,
/// Selection background. Default: `state.selected` of `base00`.
base02: kosm.Color,
/// Comments and invisibles. Default: `emphasis.muted` of `base05`.
base03: kosm.Color,
/// Dark foreground (status bars). Default: `emphasis.muted` of `base05`.
base04: kosm.Color,
/// Default foreground. Default: white, black in light mode.
base05: kosm.Color,
/// Light foreground. Default: `emphasis.strong` of `base05`.
base06: kosm.Color,
/// Lightest foreground. Default: `lightness.bright` of `base05`.
base07: kosm.Color,
/// Variables, tags, diff deletions. Default: red.
base08: kosm.Color,
/// Constants, numbers, booleans. Default: orange.
base09: kosm.Color,
/// Classes, search background. Default: yellow.
base0A: kosm.Color,
/// Strings, diff insertions. Default: green.
base0B: kosm.Color,
/// Support, regular expressions, escapes. Default: cyan.
base0C: kosm.Color,
/// Functions, headings. Default: blue.
base0D: kosm.Color,
/// Keywords, storage, diff changes. Default: purple.
base0E: kosm.Color,
/// Deprecated code, embedded language tags. Default: pink.
base0F: kosm.Color,
