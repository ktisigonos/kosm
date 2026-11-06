//! Walks a kosmos tree (D18): plans every app in it, each `apply` writing into one shared plan
//! under its path in the tree ("terminal.kitty"), and later reloads them (D74). Null optional
//! apps are skipped.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const report = @import("report.zig");

/// Everything an app's `Output` shares with the others.
pub const Context = struct {
    /// Scratch memory for every apply; freed by the caller afterwards.
    allocator: std.mem.Allocator,
    /// Absolute home directory that `~` expands to.
    home: []const u8,
    adapters: []const kosm.Adapter,
    plan: *kosm.Plan,
    diagnostics: *kosm.Diagnostics,
};

/// The first app failed; `context.diagnostics` names it.
pub const Error = error{ApplyFailed};

/// Calls `apply` on every app in `tree`, in field order, stopping at the first failure.
pub fn planTree(tree: anytype, context: Context) Error!void {
    try planNode(tree, "", context);
}

fn planNode(node: anytype, comptime path: []const u8, context: Context) Error!void {
    @setEvalBranchQuota(discovery.branch_quota);
    const Node = @TypeOf(node);
    if (@typeInfo(Node) == .optional) {
        if (node) |present| try planNode(present, path, context);
        return;
    }
    if (comptime discovery.isApp(Node)) return planApp(node, path, context);
    if (comptime !discovery.containsApp(Node)) return;
    inline for (@typeInfo(Node).@"struct".field_names) |name| {
        const child_path = if (path.len == 0) name else path ++ "." ++ name;
        try planNode(@field(node, name), child_path, context);
    }
}

fn planApp(app: anytype, comptime path: []const u8, context: Context) Error!void {
    var output: kosm.Output = .{
        .allocator = context.allocator,
        .home = context.home,
        .adapters = context.adapters,
        .plan = context.plan,
        .diagnostics = context.diagnostics,
        .app = path,
    };
    app.apply(&output) catch |err| {
        // Output's own errors already explain themselves; an app's own error only has its name.
        if (context.diagnostics.message().len == 0) context.diagnostics.set(path, "", "apply failed: {s}", .{@errorName(err)});
        return error.ApplyFailed;
    };
}

/// Calls `reload` on every app in `tree` that has one, in field order. A failure is a warning
/// on `warnings` naming `kosmos` and the app, and the rest still reload.
pub fn reloadTree(tree: anytype, io: std.Io, kosmos: []const u8, warnings: *std.Io.Writer) std.Io.Writer.Error!void {
    try reloadNode(tree, "", .{ .io = io, .kosmos = kosmos, .warnings = warnings });
}

const ReloadContext = struct {
    io: std.Io,
    kosmos: []const u8,
    warnings: *std.Io.Writer,
};

fn reloadNode(node: anytype, comptime path: []const u8, context: ReloadContext) std.Io.Writer.Error!void {
    @setEvalBranchQuota(discovery.branch_quota);
    const Node = @TypeOf(node);
    if (@typeInfo(Node) == .optional) {
        if (node) |present| try reloadNode(present, path, context);
        return;
    }
    if (comptime discovery.isApp(Node)) {
        if (comptime !discovery.hasReload(Node)) return;
        var reloader: kosm.Reloader = .{ .io = context.io };
        node.reload(&reloader) catch |err| {
            const reason = if (reloader.failure().len != 0) reloader.failure() else @errorName(err);
            try report.reloadFailed(context.warnings, context.kosmos, path, reason);
        };
        return;
    }
    if (comptime !discovery.containsApp(Node)) return;
    inline for (@typeInfo(Node).@"struct".field_names) |name| {
        const child_path = if (path.len == 0) name else path ++ "." ++ name;
        try reloadNode(@field(node, name), child_path, context);
    }
}

const testing = std.testing;

const lines_adapter: kosm.Adapter = .{ .name = "lines", .extensions = &.{".lines"}, .serialize = serializeLines };

fn serializeLines(writer: *std.Io.Writer, root: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    _ = context;
    for (root.table) |entry| try writer.print("{s} = {d}\n", .{ entry.key, entry.value.integer });
}

const WritingApp = struct {
    file: []const u8,
    size: u8 = 1,
    pub fn apply(self: WritingApp, output: *kosm.Output) !void {
        try output.generate(.{ .file = self.file }, .{ .size = self.size });
    }
};

const FailingApp = struct {
    pub fn apply(self: FailingApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
        return error.GlowMissing;
    }
};

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},

    fn init(fixture: *Fixture) void {
        fixture.* = .{ .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
    }

    fn context(fixture: *Fixture, home: []const u8) Context {
        return .{
            .allocator = fixture.arena.allocator(),
            .home = home,
            .adapters = &.{lines_adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
        };
    }
};

test "every app in nested structs is planned under its tree path, null ones are skipped" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const home = home_buffer[0..try tmp.dir.realPath(testing.io, &home_buffer)];
    var fixture: Fixture = undefined;
    fixture.init();
    defer fixture.deinit();

    const tree = .{
        .terminal = .{ .kitty = WritingApp{ .file = "~/a.lines" }, .foot = @as(?WritingApp, null) },
        .editor = @as(?WritingApp, .{ .file = "~/b.lines", .size = 2 }),
        .modifier = kosm.Modifier{},
    };
    try planTree(tree, fixture.context(home));
    try testing.expectEqual(2, fixture.plan.files.items.len);
    try testing.expectEqualStrings("terminal.kitty", fixture.plan.files.items[0].owner());
    try testing.expectEqualStrings("editor", fixture.plan.files.items[1].owner());
    try testing.expectEqualStrings("size = 2\n", fixture.plan.files.items[1].new);
}

test "an app's own error is reported with its path" {
    var fixture: Fixture = undefined;
    fixture.init();
    defer fixture.deinit();
    try testing.expectError(error.ApplyFailed, planTree(.{ .bar = .{ .waybar = FailingApp{} } }, fixture.context("/home/test")));
    try testing.expectEqualStrings("bar.waybar", fixture.diagnostics.app);
    try testing.expectEqualStrings("apply failed: GlowMissing", fixture.diagnostics.message());
}

const ReloadingApp = struct {
    command: []const []const u8,
    reloads: *usize,

    pub fn apply(self: ReloadingApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }

    pub fn reload(self: ReloadingApp, reloader: *kosm.Reloader) !void {
        self.reloads.* += 1;
        try reloader.run(self.command);
    }
};

test "every app with reload reloads, and a failing one is a warning while the rest go on" {
    var reloads: usize = 0;
    const tree = .{
        .terminal = .{
            .kitty = ReloadingApp{ .command = &.{"false"}, .reloads = &reloads },
            .foot = @as(?ReloadingApp, null),
        },
        .bar = ReloadingApp{ .command = &.{"true"}, .reloads = &reloads },
        .editor = WritingApp{ .file = "~/a.lines" },
    };
    var buffer: [256]u8 = undefined;
    var warnings: std.Io.Writer = .fixed(&buffer);
    try reloadTree(tree, testing.io, "frost", &warnings);
    try testing.expectEqual(2, reloads);
    try testing.expectEqualStrings("warning: kosmos 'frost', app 'terminal.kitty': reload failed: 'false' exited with code 1\n", warnings.buffered());
}

test "an Output error keeps the message Output wrote" {
    var fixture: Fixture = undefined;
    fixture.init();
    defer fixture.deinit();
    try testing.expectError(error.ApplyFailed, planTree(.{ .kitty = WritingApp{ .file = "relative.lines" } }, fixture.context("/home/test")));
    try testing.expectEqualStrings("kitty", fixture.diagnostics.app);
    try testing.expectEqualStrings("file paths start with ~/ or /", fixture.diagnostics.message());
}
