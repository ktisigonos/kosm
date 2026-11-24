//! Where a command that works on a config project runs and reports.

const Context = @This();

const std = @import("std");
const Sources = @import("Sources.zig");
const Settings = @import("Settings.zig");

io: std.Io,
/// Holds everything a command allocates; freed by the caller.
arena: std.mem.Allocator,
/// The config project's absolute path.
config: []const u8,
/// The environment for `zig` and the programs it builds; null passes on kosm's own.
environ_map: ?*const std.process.Environ.Map = null,
/// The kosm sources `zig build` uses in place of the config's pinned kosm; null for the pinned one.
sources: ?Sources = null,
/// How `zig build` optimizes the config, passed as `-Doptimize`; null leaves the build's own
/// default, debug, which compiles fastest.
optimize: ?std.builtin.Optimize = null,
/// Whether `runBuild` lets `zig build` draw its progress and print its errors on the
/// terminal; otherwise its output is collected, as tests need.
show_build_output: bool = false,
/// Set once `runBuild` has said which kosm sources its builds use, so a command says it once
/// however many builds it runs; null never says it.
sources_announced: ?*bool = null,
/// What a command did, and what packages provide.
stdout: *std.Io.Writer,
/// Errors, and the output of a failing `zig`.
stderr: *std.Io.Writer,

/// The command failed and has said why on stderr.
pub const Failed = error{Failed};

/// Prints `error: <message>` to stderr and returns `error.Failed`.
pub fn fail(context: Context, comptime format: []const u8, arguments: anytype) (Failed || std.Io.Writer.Error) {
    context.stderr.print("error: " ++ format ++ "\n", arguments) catch |err| return err;
    return error.Failed;
}

pub const RunError = Failed || std.mem.Allocator.Error || std.Io.Writer.Error;

/// Runs `zig` with `arguments` in the config directory; see `run`. A `zig build` gets
/// `--fork` for `sources` when the project depends on kosm by hash.
pub fn runZig(context: Context, arguments: []const []const u8) RunError!std.process.RunResult {
    return context.run(try context.zigArguments(arguments));
}

/// `zig` and `arguments`, with `--fork` and `-Doptimize` after `build` when `runZig` adds them.
pub fn zigArguments(context: Context, arguments: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    if (!isBuild(arguments)) return std.mem.concat(context.arena, []const u8, &.{ &.{"zig"}, arguments });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(context.arena, &.{ "zig", "build" });
    if (try context.forkArgument(arguments)) |fork| try argv.append(context.arena, fork);
    if (context.optimize) |mode| try argv.append(context.arena, try std.fmt.allocPrint(context.arena, "-Doptimize={t}", .{mode}));
    try argv.appendSlice(context.arena, arguments[1..]);
    return argv.items;
}

fn isBuild(arguments: []const []const u8) bool {
    return arguments.len != 0 and std.mem.eql(u8, arguments[0], "build");
}

/// The config's `kosm.zon`, with defaults for a missing file or field. A file that cannot be
/// read or parsed fails, saying why on stderr.
pub fn loadSettings(context: Context) (Failed || std.mem.Allocator.Error || std.Io.Writer.Error)!Settings {
    const path = try std.Io.Dir.path.join(context.arena, &.{ context.config, Settings.file_name });
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return Settings.load(context.arena, context.io, path, &diagnostics) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseZon => {
            try context.stderr.print("{f}\n", .{diagnostics.fmt(path)});
            return context.fail("cannot read {s}", .{path});
        },
        else => return context.fail("cannot read {s}: {s}", .{ path, @errorName(err) }),
    };
}

fn forkArgument(context: Context, arguments: []const []const u8) std.mem.Allocator.Error!?[]const u8 {
    const sources = context.sources orelse return null;
    if (!isBuild(arguments)) return null;
    return sources.forkArgument(context.io, context.arena, context.config);
}

/// Runs `zig build` with `arguments` (which start with "build") in the config directory and
/// returns whether it succeeded. A failure's output reaches stderr either way.
pub fn runBuild(context: Context, arguments: []const []const u8) RunError!bool {
    if (!context.show_build_output) {
        const result = try context.runZig(arguments);
        if (!result.term.success()) try context.stderr.writeAll(result.stderr);
        return result.term.success();
    }
    if (try context.forkArgument(arguments) != null) try context.announceSources();
    // What the command printed so far belongs before the build's own output.
    try context.stdout.flush();
    try context.stderr.flush();
    const argv = try context.zigArguments(arguments);
    var child = std.process.spawn(context.io, .{ .argv = argv, .cwd = .{ .path = context.config }, .environ_map = context.environ_map }) catch |err|
        return context.fail("cannot run {s}: {s}", .{ argv[0], @errorName(err) });
    const term = child.wait(context.io) catch |err| return context.fail("cannot wait for {s}: {s}", .{ argv[0], @errorName(err) });
    return term.success();
}

fn announceSources(context: Context) std.Io.Writer.Error!void {
    const announced = context.sources_announced orelse return;
    if (announced.*) return;
    announced.* = true;
    const sources = context.sources.?;
    try context.stderr.print("building with the kosm at {s} ({s}), not the kosm build.zig.zon pins\n", .{ sources.directory, switch (sources.origin) {
        .override => "set by kosm source",
        .installed => "installed beside this binary",
    } });
}

/// Runs every argv in `argvs` at once in the config directory and collects each one's output,
/// in the order given; a program that cannot start fails, and stops the others.
pub fn runAll(context: Context, argvs: []const []const []const u8) RunError![]std.process.RunResult {
    const children = try context.arena.alloc(std.process.Child, argvs.len);
    var started: usize = 0;
    defer for (children[0..started]) |*child| child.kill(context.io);
    for (argvs, children) |argv, *child| {
        child.* = std.process.spawn(context.io, .{
            .argv = argv,
            .cwd = .{ .path = context.config },
            .environ_map = context.environ_map,
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |err| return context.fail("cannot run {s}: {s}", .{ argv[0], @errorName(err) });
        started += 1;
    }
    const results = try context.arena.alloc(std.process.RunResult, argvs.len);
    for (argvs, children, results) |argv, *child, *result| {
        result.* = collect(context, child) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return context.fail("cannot read the output of {s}: {s}", .{ argv[0], @errorName(err) }),
        };
    }
    return results;
}

/// Reads `child`'s stdout and stderr to their ends, then waits for it.
fn collect(context: Context, child: *std.process.Child) !std.process.RunResult {
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(context.arena, context.io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (reader.fill(64, .none)) |_| {} else |err| switch (err) {
        error.EndOfStream => {},
        else => |other| return other,
    }
    try reader.checkAnyError();
    const term = try child.wait(context.io);
    return .{ .term = term, .stdout = try reader.toOwnedSlice(0), .stderr = try reader.toOwnedSlice(1) };
}

/// Runs `argv` in the config directory and collects its output; a program that cannot start fails.
pub fn run(context: Context, argv: []const []const u8) RunError!std.process.RunResult {
    return std.process.run(context.arena, context.io, .{
        .argv = argv,
        .cwd = .{ .path = context.config },
        .environ_map = context.environ_map,
    }) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => context.fail("cannot run {s}: {s}", .{ argv[0], @errorName(err) }),
    };
}

const testing = std.testing;

test "only a build is given the optimize mode, after the fork" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var discarded: std.Io.Writer.Discarding = .init(&.{});
    var context: Context = .{ .io = testing.io, .arena = arena.allocator(), .config = "/c", .stdout = &discarded.writer, .stderr = &discarded.writer };
    const debug = try context.zigArguments(&.{ "build", "-Dscripts" });
    try testing.expectEqual(3, debug.len);
    try testing.expectEqualStrings("-Dscripts", debug[2]);

    context.optimize = .safe;
    const safe = try context.zigArguments(&.{ "build", "-Dscripts" });
    try testing.expectEqual(4, safe.len);
    try testing.expectEqualStrings("build", safe[1]);
    try testing.expectEqualStrings("-Doptimize=safe", safe[2]);
    try testing.expectEqualStrings("-Dscripts", safe[3]);
    try testing.expectEqual(2, (try context.zigArguments(&.{"env"})).len);
}
