//! The one kosmos a runner build applies, filled in by the main that `addConfigProject` generates.

const Target = @This();

const Places = @import("Places.zig");

/// The kosmos as `kosm apply` spells it: "frost", "frost.iced" or "frost.cold.deep".
name: []const u8,
/// The kosmos file or directory for messages: "kosmoi/frost.zig" or "kosmoi/nord/".
path: []const u8,
/// The config project's absolute path, which `~~/` stands for.
config: []const u8,
/// The absolute path of the kosmos' folder: the folder of a kosmos file, a kosmos folder
/// itself, or a package's folder. `~~kosmos/` and relative paths in the kosmos start here.
folder: []const u8,
/// The folder of every package and local kosmos, app or adapter, which `~~<name>/` stands for.
folders: []const Places.Folder,
/// The kosmos file's module.
file: type,
/// The kosmos in `file`, by its name after the file's ("iced", "cold.deep"); "kosmos" is the
/// file's default.
function: []const u8,
/// Every module that may export adapters: installed packages and local adapters.
adapter_sources: []const AdapterSource,

/// A module that may export adapters, and the package it is, as the user spells it.
pub const AdapterSource = struct {
    package: []const u8,
    module: type,
};
