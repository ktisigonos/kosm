//! The script of an app, adapter or modifier written through a frontend, which the host runs functions of.

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, relative to the config: "apps/cava/root.lua".
path: []const u8,
