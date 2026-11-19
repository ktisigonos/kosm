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
    /// Tables script kosmoi set, the lowest first.
    layers: []const Layer = &.{},
    /// Builds the kosmoi its `kosm.Kosmos` fields name; null in a runner that cannot, where
    /// naming one fails.
    kosmoi: ?Builder = null,
};

/// Builds a kosmos by name for a `kosm.Kosmos` field, in a runner holding every kosmos.
pub const Builder = struct {
    state: *anyopaque,
    /// Builds kosmos `name`, which must give a tree of identity `tree` (`kosm.Frontend.Handle.id`),
    /// called `tree_name` in messages, and returns it, kept for the whole run.
    build: *const fn (state: *anyopaque, name: []const u8, tree: *const anyopaque, tree_name: []const u8, diagnostics: *kosm.Diagnostics) images.Error!*const anyopaque,
};

/// The kosmoi being built, the outermost first, so one building on itself fails naming the
/// circle instead of building forever.
pub const Building = struct {
    names: std.ArrayList([]const u8) = .empty,

    /// Marks kosmos `name` as being built; fails when it already is.
    pub fn enter(building: *Building, arena: std.mem.Allocator, name: []const u8, diagnostics: *kosm.Diagnostics) (Reported || std.mem.Allocator.Error)!void {
        for (building.names.items) |earlier| {
            if (!std.mem.eql(u8, earlier, name)) continue;
            try building.names.append(arena, name);
            return fail(diagnostics, "the kosmoi build on each other in a circle: {s}", .{try std.mem.join(arena, " -> ", building.names.items)});
        }
        try building.names.append(arena, name);
    }

    /// How many kosmoi are being built, to `restore` once those entered after are done.
    pub fn depth(building: Building) usize {
        return building.names.items.len;
    }

    /// Marks every kosmos entered since `depth` was `earlier` as built.
    pub fn restore(building: *Building, earlier: usize) void {
        building.names.shrinkRetainingCapacity(earlier);
    }
};

/// A table of `Params` a script sets.
pub const Layer = struct {
    values: kosm.Loose,
    /// The absolute folder of the script, which relative paths it gives start from.
    folder: []const u8,
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
            kosm.assign(Params, image_context.arena, &start, layer.values, diagnostics) catch |err| switch (err) {
                error.InvalidAssignment => return error.Reported,
                error.OutOfMemory => return error.OutOfMemory,
            };
            try params.absoluteLayerPaths(Params, image_context.arena, &start, layer.values, layer.folder);
            host_set = host_set or script.setsKey(layer.values, "host");
        }
        var hostname_buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = if (comptime params.hasHost(Params)) try readHostname(&hostname_buffer, diagnostics) else "";
        var parsed = params.parseOnto(Params, start, host_set, given.arguments, hostname, diagnostics) catch return error.Reported;
        try images.fill(Params, &parsed, image_context);
        try files.fill(Params, &parsed, .{ .arena = image_context.arena, .io = image_context.io, .places = image_context.places, .diagnostics = diagnostics });
        try buildKosmoi(Params, &parsed, given.kosmoi, image_context.arena, diagnostics);
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

/// Builds the kosmos every `kosm.Kosmos` (or non-null `?kosm.Kosmos`) field of `params_value`
/// names, through `builder`.
fn buildKosmoi(comptime Params: type, params_value: *Params, builder: ?Builder, arena: std.mem.Allocator, diagnostics: *kosm.Diagnostics) images.Error!void {
    const fields = @typeInfo(Params).@"struct";
    inline for (fields.field_names, fields.field_types) |name, Field| {
        if (comptime kosm.isKosmos(Field)) {
            try buildKosmos(Field, &@field(params_value, name), name, builder, arena, diagnostics);
        } else if (comptime @typeInfo(Field) == .optional and kosm.isKosmos(@typeInfo(Field).optional.child)) {
            if (@field(params_value, name)) |*kosmos| try buildKosmos(@TypeOf(kosmos.*), kosmos, name, builder, arena, diagnostics);
        }
    }
}

fn buildKosmos(comptime Kosmos: type, kosmos: *Kosmos, comptime field: []const u8, builder: ?Builder, arena: std.mem.Allocator, diagnostics: *kosm.Diagnostics) images.Error!void {
    const known = builder orelse return fail(diagnostics, "Params." ++ field ++ ": '{s}' can only be built by the runner of scripts, which `kosm apply` runs a kosmos building on another in", .{kosmos.name});
    var inner: kosm.Diagnostics = .{ .kosmos = kosmos.name };
    const built = known.build(known.state, kosmos.name, kosm.Frontend.Handle.id(Kosmos.Tree), @typeName(Kosmos.Tree), &inner) catch |err| switch (err) {
        error.Reported => {
            const file = if (inner.file.len == 0) "" else try std.fmt.allocPrint(arena, ", file {s}", .{inner.file});
            const app = if (inner.app.len == 0) "" else try std.fmt.allocPrint(arena, ", app {s}", .{inner.app});
            // A name that is no kosmos fails naming none, so its message stands alone.
            if (inner.kosmos.len == 0) return fail(diagnostics, "Params." ++ field ++ ": {s}", .{inner.message()});
            return fail(diagnostics, "Params." ++ field ++ ": kosmos '{s}'{s}{s}: {s}", .{ kosmos.name, app, file, inner.message() });
        },
        else => |other| return other,
    };
    kosmos.built = @ptrCast(@alignCast(built));
}

/// Whether `Params` names a kosmos to build on, which only the runner of scripts can build.
pub fn buildsOnKosmoi(comptime Params: type) bool {
    inline for (@typeInfo(Params).@"struct".field_types) |Field| {
        if (kosm.isKosmos(Field)) return true;
        if (@typeInfo(Field) == .optional and kosm.isKosmos(@typeInfo(Field).optional.child)) return true;
    }
    return false;
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
    if (try lifetime.findDeadList(arena, tree, dead)) |path|
        return fail(diagnostics, "{s} points into a function that has returned, so what it holds is garbage: write lists of values known only at run time as kosm.keep(T, &.{{ ... }}), or as constants", .{path});
}

/// One Zig kosmos the script runner holds, and the folder of the module declaring it.
pub const ZigKosmos = struct {
    /// As `kosm apply` spells it: "frost", "frost.iced".
    name: []const u8,
    /// Where it is declared, for messages: "kosmoi/frost.zig", "package kosm_probe".
    origin: []const u8,
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
            found = found ++ .{ZigKosmos{ .name = name, .origin = source.origin, .Namespace = declared.Namespace, .function = declared.function, .folder = source.folder }};
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

fn fail(diagnostics: *kosm.Diagnostics, comptime format: []const u8, arguments: anytype) Reported {
    diagnostics.set("", "", format, arguments);
    return error.Reported;
}

const testing = std.testing;

const TestGroup = struct { name: []const u8, colors: []const u32 };
const TestTree = struct { groups: []const TestGroup = &.{} };

/// A kosmos writing a list of groups that holds a run-time color without `kosm.keep`.
noinline fn treeWithDeadGroups(color: u32) TestTree {
    var tree: TestTree = .{};
    tree.groups = &.{.{ .name = "active", .colors = &.{ color, color } }};
    std.mem.doNotOptimizeAway(&tree);
    return tree;
}

test "a list left on the kosmos' stack is refused by its path, though that stack is gone" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    var diagnostics: kosm.Diagnostics = .{};
    var tree: TestTree = undefined;
    const stack = try callOnKosmosStack(treeWithDeadGroups, .{@as(u32, 7)}, &tree, &diagnostics);
    try testing.expectError(error.Reported, refuseDeadLists(arena_state.allocator(), tree, &.{ .below(@intFromPtr(&tree)), stack }, &diagnostics));
    try testing.expect(std.mem.startsWith(u8, diagnostics.message(), "groups points into a function that has returned"));
}
