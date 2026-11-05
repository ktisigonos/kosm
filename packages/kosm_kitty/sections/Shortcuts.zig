//! kitty's "Keyboard shortcuts" options. Field names are kitty's option names (D27).

const values = @import("../values.zig");

/// Special modifier key alias for default shortcuts. null: kitty's default, `ctrl+shift`.
kitty_mod: ?values.Modifiers = null,
/// Remap modifiers, making one modifier act as another. null: kitty's default.
remap_modifiers: ?[]const values.ModifierRemap = null,
/// Remove all shortcut definitions up to this point. null: kitty's default, `no`.
clear_all_shortcuts: ?bool = null,
/// The default timeout (in seconds) for multi-key mappings and modal keyboard modes. null: kitty's default, `0.0`.
map_timeout: ?f64 = null,
/// Define action aliases to avoid repeating the same options in multiple mappings. Each item is written as its own line.
action_alias: []const values.Alias = &.{},
/// Like `action_alias` above, but specifically for kittens. Each item is written as its own line.
kitten_alias: []const values.Alias = &.{},

/// Options kitty allows more than once: each item is its own line.
pub const repeated = [_][]const u8{ "action_alias", "kitten_alias" };
