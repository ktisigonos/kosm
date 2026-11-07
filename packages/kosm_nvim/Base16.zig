//! The 16 base16 slots, named as base16 names them.

const kosm = @import("kosm");

/// Default background. null: not written. `from`: black, white in light mode.
base00: ?kosm.Color = null,
/// Lighter background (status bars, line numbers). null: not written. `from`: `surface.raised` of `base00`.
base01: ?kosm.Color = null,
/// Selection background. null: not written. `from`: `state.selected` of `base00`.
base02: ?kosm.Color = null,
/// Comments and invisibles. null: not written. `from`: `emphasis.muted` of `base05`.
base03: ?kosm.Color = null,
/// Dark foreground (status bars). null: not written. `from`: `emphasis.muted` of `base05`.
base04: ?kosm.Color = null,
/// Default foreground. null: not written. `from`: white, black in light mode.
base05: ?kosm.Color = null,
/// Light foreground. null: not written. `from`: `emphasis.strong` of `base05`.
base06: ?kosm.Color = null,
/// Lightest foreground. null: not written. `from`: `lightness.bright` of `base05`.
base07: ?kosm.Color = null,
/// Variables, tags, diff deletions. null: not written. `from`: red.
base08: ?kosm.Color = null,
/// Constants, numbers, booleans. null: not written. `from`: orange.
base09: ?kosm.Color = null,
/// Classes, search background. null: not written. `from`: yellow.
base0A: ?kosm.Color = null,
/// Strings, diff insertions. null: not written. `from`: green.
base0B: ?kosm.Color = null,
/// Support, regular expressions, escapes. null: not written. `from`: cyan.
base0C: ?kosm.Color = null,
/// Functions, headings. null: not written. `from`: blue.
base0D: ?kosm.Color = null,
/// Keywords, storage, diff changes. null: not written. `from`: purple.
base0E: ?kosm.Color = null,
/// Deprecated code, embedded language tags. null: not written. `from`: pink.
base0F: ?kosm.Color = null,
