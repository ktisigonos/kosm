//! How an app's file names its settings, so `Setting.withExtras` reads and checks extras the
//! way the file does.

/// How an extra's path is read. Default: `.keys`.
paths: Paths = .keys,
/// Whether `*` may stand for any one key. Only where kosm sets values in files it edits;
/// a generated file has no keys to match. Default: false.
any_key: bool = false,
/// Top-level keys the program reads more than once, each one adding another (kitty's `map`,
/// ghostty's `keybind`). Settings with one of these keys never clash. Default: none.
repeatable: []const []const u8 = &.{},

/// How an extra's path names its key.
pub const Paths = enum {
    /// A path: dot-separated keys that nest, `"quoted.keys"` for a key holding a dot.
    keys,
    /// A path of exactly one key, for files whose keys don't nest (kitty.conf, ghostty).
    one_key,
    /// The whole text is one key, dots and all, for flat names (Firefox prefs).
    whole_name,
};
