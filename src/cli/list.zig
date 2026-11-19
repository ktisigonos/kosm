//! `kosm list [kosmos | kinds]`: builds the config's listing program and passes on what it prints.

const std = @import("std");
const Context = @import("Context.zig");
const known_kosmoi = @import("known_kosmoi.zig");

pub const Error = Context.RunError;

/// The flags listing one kind alone, as the lister reads them.
pub const kind_flags = [_][]const u8{ "--kosmoi", "--apps", "--adapters", "--frontends", "--packages" };

/// Lists every kosmos (with the variants scripts give) and installed package; with `kosmos`
/// only that kosmos file or variant; with `kinds` (some of `kind_flags`) only those kinds.
pub fn list(context: Context, kosmos: ?[]const u8, kinds: []const []const u8) Error!void {
    try known_kosmoi.buildLister(context);
    const variants = try known_kosmoi.scriptVariantArguments(context);
    const frontends = if (asks(kinds, "--frontends")) try known_kosmoi.frontendArguments(context) else &.{};
    const arguments = if (kosmos) |name| &.{name} else kinds;
    const result = try context.run(try known_kosmoi.listerCommand(context, arguments, try std.mem.concat(context.arena, []const u8, &.{ variants, frontends })));
    try context.stdout.writeAll(result.stdout);
    try context.stderr.writeAll(result.stderr);
    if (!result.term.success()) return error.Failed;
}

fn asks(kinds: []const []const u8, flag: []const u8) bool {
    for (kinds) |kind| {
        if (std.mem.eql(u8, kind, flag)) return true;
    }
    return false;
}
