//! `kosm colors <kosmos>`: builds the program that prints the kosmos' palettes and passes on
//! what it prints.

const std = @import("std");
const Context = @import("Context.zig");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dcolors=...`.
const program_path = "zig-out/bin/colors";
/// Asks the program for colored blocks; it cannot see that kosm's stdout is a terminal.
const blocks_argument = "--blocks";

/// Prints every palette the file of `kosmos` declares; a variant (`frost.iced`) shows its
/// file's. With `blocks`, each color is also drawn as a truecolor block.
pub fn colors(context: Context, kosmos: []const u8, blocks: bool) Error!void {
    const build = try context.runZig(&.{ "build", try context.arena.print("-Dcolors={s}", .{kosmos}) });
    if (!build.term.success()) {
        try context.stderr.writeAll(build.stderr);
        return context.fail("the colors of kosmos '{s}' cannot be shown: the config project {s} does not build it", .{ kosmos, context.config });
    }
    const program = try std.Io.Dir.path.join(context.arena, &.{ context.config, program_path });
    const result = try context.run(if (blocks) &.{ program, blocks_argument } else &.{program});
    try context.stdout.writeAll(result.stdout);
    try context.stderr.writeAll(result.stderr);
    if (!result.term.success()) return error.Failed;
}
