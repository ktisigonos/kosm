//! `kosm list [kosmos]`: builds the config's listing program and passes on what it prints.

const std = @import("std");
const Context = @import("Context.zig");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dlist`.
const lister_path = "zig-out/bin/list";

/// Lists every kosmos and installed package, or with `kosmos` only that kosmos file or variant.
pub fn list(context: Context, kosmos: ?[]const u8) Error!void {
    const build = try context.runZig(&.{ "build", "-Dlist" });
    if (!build.term.success()) {
        try context.stderr.writeAll(build.stderr);
        return context.fail("the config project {s} does not build, so it cannot be listed", .{context.config});
    }
    const lister = try std.Io.Dir.path.join(context.arena, &.{ context.config, lister_path });
    const result = try context.run(if (kosmos) |name| &.{ lister, name } else &.{lister});
    try context.stdout.writeAll(result.stdout);
    try context.stderr.writeAll(result.stderr);
    if (!result.term.success()) return error.Failed;
}
