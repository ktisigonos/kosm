//! The program `kosm apply` builds for one kosmos: parses its parameters and `--set`s, plans
//! every app, then prints the plan as a diff or commits it all or nothing and reloads the apps
//! (D19, D20, D36, D37, D74).

const std = @import("std");
const kosm = @import("kosm");
const Arguments = @import("Arguments.zig");
const discovery = @import("discovery.zig");
const params = @import("params.zig");
const report = @import("report.zig");
const set = @import("set.zig");
const walk = @import("walk.zig");

/// The kosmos a build applies.
pub const Target = @import("Target.zig");

/// Runs the kosmos in `target` with the process arguments
/// (`[--param value]... [--set path=value]... [--diff]`).
/// Returns the exit status: 0 on success, 1 after printing what went wrong.
pub fn run(init: std.process.Init, comptime target: Target) !u8 {
    comptime checkTarget(target);
    const kosmos = @field(target.file, target.function);
    const adapters = comptime discovery.adapters(target.adapter_sources);
    var diagnostics: kosm.Diagnostics = .{ .kosmos = target.name };
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    const streams: Streams = .{ .stdout = &stdout.interface, .stderr = &stderr.interface };

    const status: u8 = if (apply(init, kosmos, adapters, &diagnostics, streams)) 0 else |err| switch (err) {
        error.Reported => 1,
        else => return err,
    };
    try stdout.interface.flush();
    if (status != 0) try diagnostics.write(&stderr.interface);
    try stderr.interface.flush();
    return status;
}

/// Where the runner reports: results on stdout, errors and warnings on stderr.
const Streams = struct {
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
};

/// Compile error unless `target.function` is a kosmos, listing the file's kosmoi (D17).
fn checkTarget(comptime target: Target) void {
    const file_name = target.name[0 .. std.mem.findScalar(u8, target.name, '.') orelse target.name.len];
    if (discovery.notKosmosReason(target.file, target.function)) |reason| {
        const subject = if (std.mem.eql(u8, target.function, "kosmos")) "the default kosmos 'kosmos'" else "'" ++ target.function ++ "'";
        @compileError(target.path ++ ": " ++ subject ++ " is not a kosmos: " ++ reason ++
            ". Kosmoi in this file: " ++ discovery.kosmosList(target.file, file_name));
    }
}

/// Failed; `diagnostics` says why.
const Reported = error{Reported};

fn apply(init: std.process.Init, comptime kosmos: anytype, adapters: []const kosm.Adapter, diagnostics: *kosm.Diagnostics, streams: Streams) !void {
    const arena = init.arena.allocator();
    const all_arguments = try init.minimal.args.toSlice(arena);
    const arguments = Arguments.split(arena, all_arguments[1..]) catch |err| switch (err) {
        error.SetWithoutAssignment => return fail(diagnostics, "--set needs path=value", .{}),
        error.OutOfMemory => return error.OutOfMemory,
    };

    var tree = try callKosmos(kosmos, arguments.parameters, diagnostics);
    for (arguments.assignments) |assignment| set.assign(&tree, assignment, diagnostics) catch return error.Reported;
    const home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{});

    var plan: kosm.Plan = .init(init.gpa, init.io);
    defer plan.deinit();
    walk.planTree(tree, .{ .allocator = arena, .home = home, .adapters = adapters, .plan = &plan, .diagnostics = diagnostics }) catch
        return error.Reported;
    try deliver(tree, &plan, .{ .gpa = init.gpa, .arena = arena, .io = init.io, .diff = arguments.diff, .diagnostics = diagnostics, .streams = streams });
}

/// What `deliver` needs besides the tree and its plan.
const Delivery = struct {
    gpa: std.mem.Allocator,
    /// Outlives the plan, so a failure's app and file can still be printed after it is freed.
    arena: std.mem.Allocator,
    io: std.Io,
    diff: bool,
    diagnostics: *kosm.Diagnostics,
    streams: Streams,
};

/// Prints the plan as a diff, or commits it and then reloads every app in `tree` (D74), also
/// when nothing changed. A failed commit reloads nothing.
fn deliver(tree: anytype, plan: *kosm.Plan, delivery: Delivery) !void {
    const stdout = delivery.streams.stdout;
    if (delivery.diff) {
        if (!plan.hasChanges()) return report.nothingToChange(stdout);
        return kosm.diff.writePlan(delivery.gpa, stdout, plan);
    }
    if (plan.hasChanges()) {
        var failure: kosm.commit.Failure = .{};
        kosm.commit.writePlan(delivery.gpa, delivery.io, plan, &failure) catch |err| {
            const app = try delivery.arena.dupe(u8, ownerOf(plan, failure.path));
            const file = try delivery.arena.dupe(u8, failure.path);
            delivery.diagnostics.set(app, file, "cannot write it: {s}", .{@errorName(err)});
            return error.Reported;
        };
        for (plan.files.items) |file| {
            if (file.changed()) try report.wrote(stdout, file.display_path);
        }
    } else try report.nothingToChange(stdout);
    // The written files are reported before any reload's own output or warning.
    try stdout.flush();
    try walk.reloadTree(tree, delivery.io, delivery.diagnostics.kosmos, delivery.streams.stderr);
}

/// The app planning the file shown as `display_path`, or empty.
fn ownerOf(plan: *const kosm.Plan, display_path: []const u8) []const u8 {
    for (plan.files.items) |file| {
        if (std.mem.eql(u8, file.display_path, display_path)) return file.owner();
    }
    return "";
}

fn callKosmos(comptime kosmos: anytype, arguments: []const []const u8, diagnostics: *kosm.Diagnostics) Reported!discovery.Payload(@typeInfo(@TypeOf(kosmos)).@"fn".return_type.?) {
    const function = @typeInfo(@TypeOf(kosmos)).@"fn";
    const returned = if (function.param_types.len == 0) blk: {
        if (arguments.len != 0) return fail(diagnostics, "it takes no parameters, got '{s}'", .{arguments[0]});
        break :blk kosmos();
    } else blk: {
        const Params = function.param_types[0].?;
        var hostname_buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = if (comptime params.hasHost(Params)) try readHostname(&hostname_buffer, diagnostics) else "";
        break :blk kosmos(params.parse(Params, arguments, hostname, diagnostics) catch return error.Reported);
    };
    if (@typeInfo(@TypeOf(returned)) != .error_union) return returned;
    return returned catch |err| fail(diagnostics, "the kosmos function failed: {s}", .{@errorName(err)});
}

fn readHostname(buffer: *[std.posix.HOST_NAME_MAX]u8, diagnostics: *kosm.Diagnostics) Reported![]const u8 {
    return std.posix.gethostname(buffer) catch |err|
        fail(diagnostics, "cannot read the hostname for Params.host: {s}", .{@errorName(err)});
}

fn fail(diagnostics: *kosm.Diagnostics, comptime format: []const u8, arguments: anytype) Reported {
    diagnostics.set("", "", format, arguments);
    return error.Reported;
}

test {
    std.testing.refAllDecls(Arguments);
    std.testing.refAllDecls(set);
    std.testing.refAllDecls(discovery);
    std.testing.refAllDecls(params);
    std.testing.refAllDecls(walk);
}

const testing = std.testing;

const lines_adapter: kosm.Adapter = .{ .name = "lines", .extensions = &.{".lines"}, .serialize = serializeLines };

fn serializeLines(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    _ = context;
    for (root.table) |entry| try writer.print("{s} = {d}\n", .{ entry.key, entry.value.integer });
}

const ReloadingApp = struct {
    file: []const u8,
    reloads: *usize,

    pub fn apply(self: ReloadingApp, output: *kosm.Output) !void {
        try output.generate(.{ .file = self.file }, .{ .size = 1 });
    }

    pub fn reload(self: ReloadingApp, reloader: *kosm.Reloader) !void {
        self.reloads.* += 1;
        try reloader.run(&.{"true"});
    }
};

/// Plans `tree` against `home` and delivers it, with stdout in `output`. Diagnostics live in `arena`.
fn planAndDeliver(arena: *std.heap.ArenaAllocator, tree: anytype, home: []const u8, diff: bool, diagnostics: *kosm.Diagnostics, output: *std.Io.Writer.Allocating) !void {
    var plan: kosm.Plan = .init(testing.allocator, testing.io);
    defer plan.deinit();
    try walk.planTree(tree, .{ .allocator = arena.allocator(), .home = home, .adapters = &.{lines_adapter}, .plan = &plan, .diagnostics = diagnostics });
    var warning_buffer: [256]u8 = undefined;
    var warnings: std.Io.Writer = .fixed(&warning_buffer);
    try deliver(tree, &plan, .{
        .gpa = testing.allocator,
        .arena = arena.allocator(),
        .io = testing.io,
        .diff = diff,
        .diagnostics = diagnostics,
        .streams = .{ .stdout = &output.writer, .stderr = &warnings },
    });
    try testing.expectEqualStrings("", warnings.buffered());
}

fn tmpPath(tmp: *testing.TmpDir, buffer: *[std.Io.Dir.max_path_bytes]u8) ![]const u8 {
    return buffer[0..try tmp.dir.realPath(testing.io, buffer)];
}

test "a diff writes and reloads nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var reloads: usize = 0;
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();

    try planAndDeliver(&arena, .{ .kitty = ReloadingApp{ .file = "~/a.lines", .reloads = &reloads } }, home, true, &diagnostics, &output);
    try testing.expectEqual(0, reloads);
    try testing.expect(std.mem.find(u8, output.written(), "+size = 1") != null);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "a.lines", .{}));
}

test "a commit reloads every app, also when nothing changed" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var reloads: usize = 0;
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const tree = .{ .kitty = ReloadingApp{ .file = "~/a.lines", .reloads = &reloads } };

    var first: std.Io.Writer.Allocating = .init(testing.allocator);
    defer first.deinit();
    try planAndDeliver(&arena, tree, home, false, &diagnostics, &first);
    try testing.expectEqual(1, reloads);
    try testing.expectEqualStrings("wrote ~/a.lines\n", first.written());

    var second: std.Io.Writer.Allocating = .init(testing.allocator);
    defer second.deinit();
    try planAndDeliver(&arena, tree, home, false, &diagnostics, &second);
    try testing.expectEqual(2, reloads);
    try testing.expectEqualStrings("nothing to change\n", second.written());
}

test "a failed commit reloads nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(testing.io, "locked", .default_dir);
    try tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o500), .{});
    defer tmp.dir.setFilePermissions(testing.io, "locked", .fromMode(0o700), .{}) catch {};
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = try tmpPath(&tmp, &home_buffer);
    var reloads: usize = 0;
    var diagnostics: kosm.Diagnostics = .{ .kosmos = "frost" };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();

    const tree = .{ .kitty = ReloadingApp{ .file = "~/locked/a.lines", .reloads = &reloads } };
    try testing.expectError(error.Reported, planAndDeliver(&arena, tree, home, false, &diagnostics, &output));
    try testing.expectEqual(0, reloads);
    try testing.expectEqualStrings("kitty", diagnostics.app);
    try testing.expectEqualStrings("~/locked/a.lines", diagnostics.file);
}
