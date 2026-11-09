//! One value a path matched, from `Selection.nodes` or `Selection.elements`.
//! Read its text if needed, but never parse it: `elements` gives a list's structure.

const Adapter = @import("../Adapter.zig");

/// The file, as messages show it ("~/.config/waybar/config.jsonc").
file: []const u8,
/// 1-based line where the entry starts.
line: usize,
/// What the value is; only a `list` has `elements`.
kind: Adapter.Node.Kind,
/// The value's bytes in the file; null for a table spelled only through headers or dotted keys.
value: ?Adapter.Range,
/// The value's source text, empty when `value` is null.
text: []const u8,
/// Kosm's own: which selected file this is in.
file_index: usize,
/// Kosm's own: the parsed entry.
node: *const Adapter.Node,
