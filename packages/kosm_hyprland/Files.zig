//! The Lua files an `edit` target sets Hyprland's options in (D79).

/// A glob of the files: `~/...` or absolute, `*` inside a name, `**` for any depth.
/// Default: every Lua file under `~/.config/hypr`.
files: []const u8 = "~/.config/hypr/**/*.lua",
/// Globs of files to leave out, written like `files`. Default: none.
exclude: []const []const u8 = &.{},
