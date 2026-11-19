//! `kosm list [kosmos]`: builds the config's listing program and passes on what it prints.

const std = @import("std");
const Context = @import("Context.zig");
const known_kosmoi = @import("known_kosmoi.zig");

pub const Error = Context.RunError;

/// Lists every kosmos (with the variants scripts give) and installed package, or with `kosmos`
/// only that kosmos file or variant.
pub fn list(context: Context, kosmos: ?[]const u8) Error!void {
    try known_kosmoi.buildLister(context);
    const variants = try known_kosmoi.scriptVariantArguments(context);
    const result = try context.run(try known_kosmoi.listerCommand(context, if (kosmos) |name| &.{name} else &.{}, variants));
    try context.stdout.writeAll(result.stdout);
    try context.stderr.writeAll(result.stderr);
    if (!result.term.success()) return error.Failed;
}
