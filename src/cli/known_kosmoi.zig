//! The kosmoi a config declares, as the config's lister names them, with the variants scripts
//! give (which only the runner of scripts can list): for checking a kosmos name before building
//! anything for it, and for `kosm list` and shell completion.

const std = @import("std");
const Context = @import("Context.zig");
const interface = @import("kosm_interface");
const kosmos_names = @import("kosm_names");
const scripts = @import("scripts.zig");

pub const Error = Context.RunError;

/// What `addConfigProject` installs for `-Dlist`.
pub const lister_path = "zig-out/bin/list";

/// One kosmos or variant.
pub const Listed = struct {
    /// As `kosm apply` spells it: "frost" or "frost.iced".
    name: []const u8,
    /// Where it is declared: "kosmoi/frost.zig", "apps/my_bar/" or "package kosm_probe".
    origin: []const u8,
};

/// How a name must match: be a kosmos, or also a file or group holding one (`kosm build frost`).
pub const Match = enum { kosmos, or_holder };

/// Fails with one line naming the closest kosmoi unless `name` is a kosmos of the config (or,
/// with `.or_holder`, picks one). `subject` starts the message when not empty
/// (`.../kosm.zon: there is no kosmos ...`). Script variants are only listed when `name` is
/// none of the other kosmoi, since that needs the runner of scripts.
pub fn check(context: Context, name: []const u8, match: Match, subject: []const u8) Error!void {
    var listed = try list(context, .without_script_variants);
    if (matches(name, listed, match)) return;
    if (try scripts.any(context)) {
        listed = try list(context, .with_script_variants);
        if (matches(name, listed, match)) return;
    }
    return context.fail("{s}{s}{s}", .{ subject, if (subject.len == 0) "" else ": ", try kosmos_names.unknownMessage(context.arena, name, try nameList(context.arena, listed)) });
}

/// Whether `name` matches one of `listed` the way `match` asks.
pub fn matches(name: []const u8, listed: []const Listed, match: Match) bool {
    for (listed) |kosmos| {
        const found = switch (match) {
            .kosmos => std.mem.eql(u8, name, kosmos.name),
            .or_holder => kosmos_names.picks(name, kosmos.name),
        };
        if (found) return true;
    }
    return false;
}

/// The names of `listed`, in order.
pub fn nameList(arena: std.mem.Allocator, listed: []const Listed) std.mem.Allocator.Error![]const []const u8 {
    const found = try arena.alloc([]const u8, listed.len);
    for (listed, found) |kosmos, *name| name.* = kosmos.name;
    return found;
}

/// Whether a listing asks the runner of scripts for the variants scripts give.
pub const Variants = enum { without_script_variants, with_script_variants };

/// Every kosmos and variant of the config, in the lister's order.
pub fn list(context: Context, variants: Variants) Error![]const Listed {
    try buildLister(context);
    const extra = switch (variants) {
        .without_script_variants => &.{},
        .with_script_variants => try scriptVariantArguments(context),
    };
    var environ: std.process.Environ.Map = if (context.environ_map) |map| try map.clone(context.arena) else .init(context.arena);
    try environ.put(interface.completions_variable, "1");
    var listing = context;
    listing.environ_map = &environ;
    const result = try listing.run(try listerCommand(context, &.{}, extra));
    if (!result.term.success()) {
        try context.stderr.writeAll(result.stderr);
        return context.fail("cannot list the kosmoi of {s}", .{context.config});
    }
    return parseListing(context.arena, result.stdout);
}

/// Builds the config's lister, failing when the config does not build.
pub fn buildLister(context: Context) Error!void {
    if (!try context.runBuild(&.{ "build", "-Dlist" }))
        return context.fail("the config project {s} does not build, so its kosmoi cannot be listed", .{context.config});
}

/// The lister built by `buildLister` with `arguments`, then `extra`.
pub fn listerCommand(context: Context, arguments: []const []const u8, extra: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const lister = try std.Io.Dir.path.join(context.arena, &.{ context.config, lister_path });
    return std.mem.concat(context.arena, []const u8, &.{ &.{lister}, arguments, extra });
}

/// The lister's arguments giving it every script kosmos and variant, which the runner of
/// scripts lists, built first when it is stale; none when `kosmoi/` holds no script.
pub fn scriptVariantArguments(context: Context) Error![]const []const u8 {
    if (!try scripts.any(context)) return &.{};
    if (!try scripts.prepare(context))
        return context.fail("the script runner does not build, so the variants of the config's scripts cannot be listed", .{});
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, scripts.runner_path });
    const result = try context.run(&.{ runner, interface.list_scripts_flag, "--config", context.config });
    if (!result.term.success()) {
        try context.stderr.writeAll(result.stderr);
        return context.fail("cannot list the script kosmoi of {s}", .{context.config});
    }
    var arguments: std.ArrayList([]const u8) = .empty;
    for (try parseListing(context.arena, result.stdout)) |kosmos| {
        try arguments.appendSlice(context.arena, &.{ interface.script_kosmos_flag, kosmos.name, kosmos.origin });
    }
    return arguments.items;
}

/// The lister's arguments giving it every frontend the runner of scripts holds, built first
/// when it is stale: `--frontend <name> <module>` each.
pub fn frontendArguments(context: Context) Error![]const []const u8 {
    if (!try scripts.prepare(context))
        return context.fail("the script runner does not build, so the config's frontends cannot be listed", .{});
    const runner = try std.Io.Dir.path.join(context.arena, &.{ context.config, scripts.runner_path });
    const result = try context.run(&.{ runner, interface.list_frontends_flag, "--config", context.config });
    if (!result.term.success()) {
        try context.stderr.writeAll(result.stderr);
        return context.fail("cannot list the frontends of {s}", .{context.config});
    }
    var arguments: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        const name = fields.first();
        const module = fields.next() orelse return context.fail("the script runner listed a frontend without its module: '{s}'", .{line});
        try arguments.appendSlice(context.arena, &.{ interface.frontend_flag, name, module });
    }
    return arguments.items;
}

/// The lister's completion lines, `name<TAB>origin` each.
fn parseListing(arena: std.mem.Allocator, listing: []const u8) std.mem.Allocator.Error![]const Listed {
    var listed: std.ArrayList(Listed) = .empty;
    var lines = std.mem.tokenizeScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        try listed.append(arena, .{ .name = fields.first(), .origin = fields.rest() });
    }
    return listed.items;
}
