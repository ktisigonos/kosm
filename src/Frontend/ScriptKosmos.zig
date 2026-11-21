//! A package's kosmos written through a frontend: where its root script is. The Zig module kosm
//! generates for such a package declares it as `script`, so the runner of scripts finds the
//! kosmos by the package's name.

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, in the package's folder: "~~kosm_frost/root.lua".
path: []const u8,
