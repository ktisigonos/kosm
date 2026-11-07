//! One key binding: a trigger, the action it runs and any chained ones. ghostty applies
//! bindings in order, so a later one for the same trigger wins.

const Keybind = @This();

const Joined = @import("../Joined.zig");
const Action = @import("action.zig").Action;

/// Keys held together joined by `+` (`ctrl+shift+t`), and steps pressed one after another
/// joined by `>` (`ctrl+a>n`, a leader key), in ghostty's key names.
trigger: []const u8,
/// What the binding does.
action: Action,
/// More actions run after `action`, in order; each is written as a `chain=` line.
chain: []const Action = &.{},
/// The key table the binding belongs to, active only through `activate_key_table`. null: the default table.
table: ?[]const u8 = null,
/// Run the action on every terminal surface, not only the focused one.
all: bool = false,
/// Work even when ghostty isn't focused; implies `all`. Needs compositor support on Linux.
global: bool = false,
/// Let the key reach the program as well.
unconsumed: bool = false,
/// Only swallow the key when the action can be performed.
performable: bool = false,

/// Writes the binding's own line the way ghostty spells it (`vim/global:ctrl+a=new_window`).
pub fn write(keybind: Keybind, joined: *Joined) Joined.Error!void {
    const writer = joined.writer();
    if (keybind.table) |table| try writer.print("{s}/", .{table});
    if (keybind.all) try writer.writeAll("all:");
    if (keybind.global) try writer.writeAll("global:");
    if (keybind.unconsumed) try writer.writeAll("unconsumed:");
    if (keybind.performable) try writer.writeAll("performable:");
    try writer.print("{s}=", .{keybind.trigger});
    try keybind.action.write(joined, .line);
}

/// Writes one chained action's line the way ghostty spells it (`chain=goto_split:left`).
pub fn writeChained(action: Action, joined: *Joined) Joined.Error!void {
    try joined.writer().writeAll("chain=");
    try action.write(joined, .line);
}
