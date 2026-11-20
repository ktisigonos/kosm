//! The scaffold_name frontend, made by `kosm new frontend scaffold_name`. It reads kosmoi
//! written as `kosmoi/<name>.scaffold_name`, one setting per line:
//!
//!     # A comment.
//!     base kyanos
//!     kitty.fonts.font_size = 12
//!
//! `kosm new kosmos <name> --language scaffold_name` starts one.

const std = @import("std");
const kosm = @import("kosm");

/// `load` is required; `variants`, `complete`, `scaffolds` and the functions running apps,
/// adapters and frontends written in this language are optional.
pub const frontend: kosm.Frontend = .{
    .name = "scaffold_name",
    .extensions = &.{".scaffold_name"},
    .load = load,
    .scaffolds = .{ .kosmos = kosmos_scaffold },
};

/// What `kosm new kosmos` writes; the placeholder is spelled through kosm's constant, so the
/// new kosmos' name replaces it rather than this frontend's.
const kosmos_scaffold = "# The " ++ new_name ++ " kosmos, made by `kosm new kosmos " ++ new_name ++ " --language scaffold_name`.\n" ++
    "# Apply it with `kosm apply " ++ new_name ++ "`, or add `--diff` to see what it would change first.\n" ++
    \\
    \\# The kosmos this one builds on, as `kosm apply` spells it.
    \\base kyanos
    \\# Any value of its tree, by the path `--set` takes.
    \\# kitty.fonts.font_size = 12
    \\
;
const new_name = kosm.Frontend.Scaffolds.name_placeholder;

/// Reads `base <kosmos>` and `<path> = <value>` lines; each value is read as its field's type,
/// as a command-line flag is.
fn load(context: *kosm.Frontend.Context, source: []const u8) kosm.Frontend.Error!kosm.Frontend.Script {
    var script: kosm.Frontend.Script = .{};
    var overrides: std.ArrayList(kosm.Loose.Entry) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var number: usize = 0;
    while (lines.next()) |untrimmed| {
        number += 1;
        const line = std.mem.trim(u8, untrimmed, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "base ")) {
            script.base = std.mem.trim(u8, line["base ".len..], " \t");
            continue;
        }
        const equals = std.mem.findScalar(u8, line, '=') orelse
            return context.fail("{s}: expected 'base <kosmos>' or '<path> = <value>'", .{try context.at(number)});
        const path = std.mem.trim(u8, line[0..equals], " \t");
        const value: kosm.Loose = .{ .value = .{ .text = std.mem.trim(u8, line[equals + 1 ..], " \t") }, .origin = try context.at(number) };
        try overrides.append(context.arena, try nested(context.arena, path, value));
    }
    if (overrides.items.len != 0) script.overrides = .{ .value = .{ .table = overrides.items } };
    return script;
}

/// `a.b.c` set to `leaf`, as tables nested one per segment.
fn nested(arena: std.mem.Allocator, path: []const u8, leaf: kosm.Loose) std.mem.Allocator.Error!kosm.Loose.Entry {
    const dot = std.mem.findScalar(u8, path, '.') orelse return .{ .key = path, .value = leaf };
    const inner = try arena.dupe(kosm.Loose.Entry, &.{try nested(arena, path[dot + 1 ..], leaf)});
    return .{ .key = path[0..dot], .value = .{ .value = .{ .table = inner } } };
}
