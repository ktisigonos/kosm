//! The one kosmos a runner build applies, filled in by the main that `addConfigProject` generates.

const Target = @This();

/// The kosmos as `kosm apply` spells it: "frost" or "frost.iced".
name: []const u8,
/// The kosmos file or directory for messages: "kosmoi/frost.zig" or "kosmoi/nord/".
path: []const u8,
/// The kosmos file's module.
file: type,
/// The kosmos function in `file`; "kosmos" is the file's default (D17).
function: []const u8,
/// Every module that may export adapters: installed packages and local adapters.
adapter_sources: []const type,
