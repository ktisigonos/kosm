//! What the script runner holds, filled in by the main that `addConfigProject` generates for
//! `-Dscripts`: every Zig kosmos, app and frontend in the config, so any script can use them.

const ScriptTarget = @This();

const Places = @import("Places.zig");
const Target = @import("Target.zig");
const discovery = @import("discovery.zig");

/// The config project's absolute path, which `~~/` stands for and `kosmoi/` is found in.
config: []const u8,
/// The folder of every package and local kosmos, app or adapter, which `~~<name>/` stands for.
folders: []const Places.Folder,
/// Every module that may declare Zig kosmoi a script builds on.
kosmoi: []const KosmosSource,
/// Every module that may export an app a kosmos without a base chooses.
apps: []const discovery.AppSource,
/// Every module that may export adapters and frontends.
adapter_sources: []const Target.AdapterSource,

/// A module declaring Zig kosmoi.
pub const KosmosSource = struct {
    /// The import name, which its kosmoi are named after: "frost", "kosm_probe".
    name: []const u8,
    /// For messages: "kosmoi/frost.zig" or "package kosm_probe".
    origin: []const u8,
    /// The absolute folder `~~kosmos/` and its relative paths start from.
    folder: []const u8,
    module: type,
};
