//! The program `kosm apply` builds for one kosmos: parses its parameters, plans every app,
//! then prints the plan as a diff or commits it all or nothing (D19, D36, D37).

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const params = @import("params.zig");
const report = @import("report.zig");
const walk = @import("walk.zig");

/// The kosmos a build applies.
pub const Target = @import("Target.zig");

/// The flag that prints the plan instead of committing it (D37).
const diff_flag = "--diff";

/// Runs the kosmos in `target` with the process arguments (`[--param value]... [--diff]`).
/// Returns the exit status: 0 on success, 1 after printing what went wrong.
pub fn run(init: std.process.Init, comptime target: Target) !u8 {
    comptime checkTarget(target);
    const kosmos = @field(target.file, target.function);
    const adapters = comptime discovery.adapters(target.adapter_sources);
    var diagnostics: kosm.Diagnostics = .{ .kosmos = target.name };
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);

    apply(init, kosmos, adapters, &diagnostics, &stdout.interface) catch |err| switch (err) {
        error.Reported => {
            try stdout.interface.flush();
            var stderr_buffer: [1024]u8 = undefined;
            var stderr = std.Io.File.stderr().writer(init.io, &stderr_buffer);
            try diagnostics.write(&stderr.interface);
            try stderr.interface.flush();
            return 1;
        },
        else => return err,
    };
    try stdout.interface.flush();
    return 0;
}

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

fn apply(init: std.process.Init, comptime kosmos: anytype, adapters: []const kosm.Adapter, diagnostics: *kosm.Diagnostics, stdout: *std.Io.Writer) !void {
    const arena = init.arena.allocator();
    const all_arguments = try init.minimal.args.toSlice(arena);
    var diff = false;
    var parameter_arguments: std.ArrayList([]const u8) = .empty;
    for (all_arguments[1..]) |argument| {
        if (std.mem.eql(u8, argument, diff_flag)) diff = true else try parameter_arguments.append(arena, argument);
    }

    const tree = try callKosmos(kosmos, parameter_arguments.items, diagnostics);
    const home = init.environ_map.get("HOME") orelse return fail(diagnostics, "HOME is not set, so ~ cannot be expanded", .{});

    var plan: kosm.Plan = .init(init.gpa, init.io);
    defer plan.deinit();
    walk.planTree(tree, .{ .allocator = arena, .home = home, .adapters = adapters, .plan = &plan, .diagnostics = diagnostics }) catch
        return error.Reported;

    if (!plan.hasChanges()) return report.nothingToChange(stdout);
    if (diff) return kosm.diff.writePlan(init.gpa, stdout, &plan);
    var failure: kosm.commit.Failure = .{};
    kosm.commit.writePlan(init.gpa, init.io, &plan, &failure) catch |err| {
        diagnostics.set(ownerOf(&plan, failure.path), failure.path, "cannot write it: {s}", .{@errorName(err)});
        return error.Reported;
    };
    for (plan.files.items) |file| {
        if (file.changed()) try report.wrote(stdout, file.display_path);
    }
}

/// The app planning the file shown as `display_path`, or empty.
fn ownerOf(plan: *const kosm.Plan, display_path: []const u8) []const u8 {
    for (plan.files.items) |file| {
        if (std.mem.eql(u8, file.display_path, display_path)) return file.owner;
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
    std.testing.refAllDecls(discovery);
    std.testing.refAllDecls(params);
    std.testing.refAllDecls(walk);
}
