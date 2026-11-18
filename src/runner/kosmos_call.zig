//! Calls a kosmos the way kosm applies it: its `Params` read from the command line and a
//! script's tables, their images and files loaded, on a stack of its own, so lists pointing into
//! a function that has returned are found afterwards.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const files = @import("files.zig");
const images = @import("images.zig");
const lifetime = @import("lifetime.zig");
const params = @import("params.zig");
const script = @import("script.zig");

/// Failed; `diagnostics` says why.
pub const Reported = error{Reported};

/// What a kosmos' `Params` are read from.
pub const Given = struct {
    /// The command line's parameters, which win.
    arguments: []const []const u8,
    /// Tables a script kosmos sets, the lowest first.
    layers: []const kosm.Loose = &.{},
    /// The folder of the scripts setting `layers`, which relative paths they give start from.
    scripts_folder: []const u8 = "",
};

/// Calls `kosmos` with its `Params` read from `given` and their images and files loaded, on its
/// own stack, which `kosmos_stack` is set to. Never inlined, so the parameters are parsed in
/// stack below its caller's. A kosmos failing through `kosm.fail` reports its own message.
pub noinline fn callKosmos(comptime kosmos: anytype, given: Given, diagnostics: *kosm.Diagnostics, kosmos_stack: *lifetime.Stack, image_context: images.Context) images.Error!discovery.Payload(@typeInfo(@TypeOf(kosmos)).@"fn".return_type.?) {
    const function = @typeInfo(@TypeOf(kosmos)).@"fn";
    var returned: function.return_type.? = undefined;
    kosm.failure.clear();
    if (function.param_types.len == 0) {
        if (given.arguments.len != 0) return fail(diagnostics, "it takes no parameters, got '{s}'", .{given.arguments[0]});
        if (given.layers.len != 0) return fail(diagnostics, "the kosmos it builds on takes no parameters, but a script sets some", .{});
        kosmos_stack.* = try callOnKosmosStack(kosmos, .{}, &returned, diagnostics);
    } else {
        const Params = function.param_types[0].?;
        var start: Params = .{};
        var host_set = false;
        for (given.layers) |layer| {
            kosm.assign(Params, image_context.arena, &start, layer, diagnostics) catch |err| switch (err) {
                error.InvalidAssignment => return error.Reported,
                error.OutOfMemory => return error.OutOfMemory,
            };
            try params.absoluteLayerPaths(Params, image_context.arena, &start, layer, given.scripts_folder);
            host_set = host_set or script.setsKey(layer, "host");
        }
        var hostname_buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = if (comptime params.hasHost(Params)) try readHostname(&hostname_buffer, diagnostics) else "";
        var parsed = params.parseOnto(Params, start, host_set, given.arguments, hostname, diagnostics) catch return error.Reported;
        try images.fill(Params, &parsed, image_context);
        try files.fill(Params, &parsed, .{ .arena = image_context.arena, .io = image_context.io, .places = image_context.places, .diagnostics = diagnostics });
        kosmos_stack.* = try callOnKosmosStack(kosmos, .{parsed}, &returned, diagnostics);
    }
    if (@typeInfo(@TypeOf(returned)) != .error_union) return returned;
    return returned catch |err| {
        if (@as(anyerror, err) == error.KosmosFailed) {
            if (kosm.failure.message()) |message| return fail(diagnostics, "{s}", .{message});
        }
        return fail(diagnostics, "the kosmos function failed: {s}", .{@errorName(err)});
    };
}

/// How deep the stack a kosmos runs on may grow. Kosmoi build whole apps by value, and a Debug
/// build gives every temporary its own stack slot, so a kosmos wearing many apps outgrows a
/// process' usual 8 or 16 MiB. It is only reserved: memory is used as deep as the kosmos goes.
pub const kosmos_stack_size = 256 * 1024 * 1024;

/// Calls `function` with `arguments` on a thread with a `kosmos_stack_size` stack, writing what
/// it returns to `returned`, and gives the part of that stack it ran in.
pub fn callOnKosmosStack(comptime function: anytype, arguments: anytype, returned: *@typeInfo(@TypeOf(function)).@"fn".return_type.?, diagnostics: *kosm.Diagnostics) Reported!lifetime.Stack {
    const Call = struct {
        fn run(call_arguments: @TypeOf(arguments), result: *@TypeOf(returned.*), top: *usize) void {
            top.* = @frameAddress();
            result.* = @call(.auto, function, call_arguments);
        }
    };
    var top: usize = undefined;
    const thread = std.Thread.spawn(.{ .stack_size = kosmos_stack_size }, Call.run, .{ arguments, returned, &top }) catch |err|
        return fail(diagnostics, "cannot start the thread the kosmos runs on: {s}", .{@errorName(err)});
    thread.join();
    return .{ .low = top -| kosmos_stack_size, .high = top };
}

fn readHostname(buffer: *[std.posix.HOST_NAME_MAX]u8, diagnostics: *kosm.Diagnostics) Reported![]const u8 {
    return std.posix.gethostname(buffer) catch |err|
        fail(diagnostics, "cannot read the hostname for Params.host: {s}", .{@errorName(err)});
}

/// Fails naming the first list in `tree` that points into one of `dead`.
pub fn refuseDeadLists(arena: std.mem.Allocator, tree: anytype, dead: []const lifetime.Stack, diagnostics: *kosm.Diagnostics) !void {
    for (dead) |stack| {
        if (try lifetime.findDeadList(arena, tree, stack)) |path|
            return fail(diagnostics, "{s} points into a function that has returned, so what it holds is garbage: write lists of values known only at run time as kosm.keep(T, &.{{ ... }}), or as constants", .{path});
    }
}

/// One Zig kosmos the script runner holds, and the folder of the module declaring it.
pub const ZigKosmos = struct {
    /// As `kosm apply` spells it: "frost", "frost.iced".
    name: []const u8,
    Namespace: type,
    function: []const u8,
    folder: []const u8,
};

/// Every kosmos every module in `sources` declares.
pub fn zigKosmoi(comptime sources: []const @import("ScriptTarget.zig").KosmosSource) []const ZigKosmos {
    @setEvalBranchQuota(discovery.branch_quota);
    comptime var found: []const ZigKosmos = &.{};
    inline for (sources) |source| {
        inline for (comptime discovery.declaredKosmoi(source.module)) |declared| {
            const name = comptime if (declared.name.len == 0) source.name else source.name ++ "." ++ declared.name;
            found = found ++ .{ZigKosmos{ .name = name, .Namespace = declared.Namespace, .function = declared.function, .folder = source.folder }};
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

fn fail(diagnostics: *kosm.Diagnostics, comptime format: []const u8, arguments: anytype) Reported {
    diagnostics.set("", "", format, arguments);
    return error.Reported;
}
