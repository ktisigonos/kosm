//! `kosm doctor`: plans each app of a tree, then checks it for what makes an apply show nothing
//! without failing: a program that isn't installed, or one that never reads the app's file.
//! Every app gets one line: fine, nothing to check, or each problem found, an app that cannot
//! be applied among them.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const walk = @import("walk.zig");

/// What the checks read besides the tree.
pub const Context = struct {
    /// Scratch memory for the lines; freed by the caller afterwards.
    allocator: std.mem.Allocator,
    io: std.Io,
    /// Absolute home directory that `~` expands to.
    home: []const u8,
    /// The `PATH` commands are looked up in, or null when it is not set.
    path_variable: ?[]const u8,
    /// The folders a Flatpak's app id is looked up in, each holding one folder per installed app
    /// (`~/.local/share/flatpak/app`, `/var/lib/flatpak/app`).
    flatpak_folders: []const []const u8,
    /// Plans each app before it is checked, so a file the apply would write or add an include to
    /// is read as it would be afterwards. Its plan is never committed.
    planning: walk.Context,
};

/// The folder system-wide Flatpaks are installed in, one folder per app id.
pub const system_flatpak_folder = "/var/lib/flatpak/app";

/// Plans and checks every app in `tree`, in field order, and prints its line to `writer`. An
/// app that cannot be applied is that app's problem, and the others are still checked. Returns
/// how many apps have a problem.
pub fn checkTree(tree: anytype, context: Context, writer: *std.Io.Writer) !usize {
    var lines: std.ArrayList(Line) = .empty;
    try checkNode(tree, "", context, &lines);
    var width: usize = 0;
    for (lines.items) |line| width = @max(width, line.app.len);
    var problems: usize = 0;
    for (lines.items) |line| {
        try writer.writeAll(line.app);
        try writer.splatByteAll(' ', width - line.app.len + 2);
        try writer.print("{s}\n", .{line.text});
        if (line.problem) problems += 1;
    }
    return problems;
}

/// One app's result.
const Line = struct {
    /// The app's path in the tree ("terminal.kitty").
    app: []const u8,
    text: []const u8,
    problem: bool,
};

fn checkNode(node: anytype, comptime path: []const u8, context: Context, lines: *std.ArrayList(Line)) !void {
    @setEvalBranchQuota(discovery.branch_quota);
    const Node = @TypeOf(node);
    if (@typeInfo(Node) == .optional) {
        if (node) |present| try checkNode(present, path, context, lines);
        return;
    }
    if (comptime discovery.isApp(Node)) {
        const line = if (try notApplied(node, path, context)) |problem|
            problem
        else if (comptime discovery.hasCheckup(Node))
            try checkApp(node, context)
        else
            nothing_to_check;
        return lines.append(context.allocator, .{ .app = path, .text = line.text, .problem = line.problem });
    }
    if (comptime !discovery.containsApp(Node)) return;
    inline for (@typeInfo(Node).@"struct".field_names) |name| {
        const child_path = if (path.len == 0) name else path ++ "." ++ name;
        try checkNode(@field(node, name), child_path, context, lines);
    }
}

const Result = struct {
    text: []const u8,
    problem: bool,
};

const nothing_to_check: Result = .{ .text = "nothing to check", .problem = false };

/// Plans `app`; why it cannot be applied, or null when it can.
fn notApplied(app: anytype, comptime path: []const u8, context: Context) !?Result {
    const diagnostics = context.planning.diagnostics;
    walk.planApp(app, path, context.planning) catch {
        defer diagnostics.set("", "", "", .{});
        const text = if (diagnostics.file.len != 0)
            try context.allocator.print("cannot apply {s}: {s}", .{ diagnostics.file, diagnostics.message() })
        else
            try context.allocator.print("cannot apply: {s}", .{diagnostics.message()});
        kosm.failure.clear();
        return .{ .text = text, .problem = true };
    };
    return null;
}

fn checkApp(app: anytype, context: Context) !Result {
    kosm.failure.clear();
    const checkup: kosm.Checkup = app.checkup();
    // A checkup cannot fail, so a script's failure in one is only recorded.
    if (kosm.failure.message()) |message| {
        defer kosm.failure.clear();
        return .{ .text = try context.allocator.print("cannot check: {s}", .{message}), .problem = true };
    }
    var problems: std.ArrayList([]const u8) = .empty;
    if (checkup.program) |program| {
        if (!try isInstalled(program, context)) try problems.append(context.allocator, try notFound(context.allocator, program));
    }
    for (checkup.includes) |include| {
        if (try notIncluded(include, context)) |problem| try problems.append(context.allocator, problem);
    }
    if (problems.items.len != 0) return .{ .text = try std.mem.join(context.allocator, "; ", problems.items), .problem = true };
    if (checkup.program == null and checkup.includes.len == 0) return nothing_to_check;
    return .{ .text = "fine", .problem = false };
}

fn isInstalled(program: kosm.Checkup.Program, context: Context) !bool {
    if (program.command) |command| {
        if (try hasCommand(command, context)) return true;
    }
    if (program.flatpak) |id| {
        for (context.flatpak_folders) |folder| {
            const installed = try std.Io.Dir.path.join(context.allocator, &.{ folder, id });
            if (exists(context.io, installed)) return true;
        }
    }
    return false;
}

fn hasCommand(command: []const u8, context: Context) !bool {
    if (std.mem.findScalar(u8, command, '/') != null) return isExecutable(context.io, try expandHome(command, context));
    var folders = std.mem.tokenizeScalar(u8, context.path_variable orelse return false, ':');
    while (folders.next()) |folder| {
        if (!std.Io.Dir.path.isAbsolute(folder)) continue;
        if (isExecutable(context.io, try std.Io.Dir.path.join(context.allocator, &.{ folder, command }))) return true;
    }
    return false;
}

fn isExecutable(io: std.Io, path: []const u8) bool {
    if (!std.Io.Dir.path.isAbsolute(path)) return false;
    std.Io.Dir.accessAbsolute(io, path, .{ .execute = true }) catch return false;
    return true;
}

fn exists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    return true;
}

fn notFound(allocator: std.mem.Allocator, program: kosm.Checkup.Program) ![]const u8 {
    var places: std.ArrayList([]const u8) = .empty;
    if (program.command) |command| try places.append(allocator, try allocator.print("no `{s}` command", .{command}));
    if (program.flatpak) |id| try places.append(allocator, try allocator.print("no Flatpak {s}", .{id}));
    if (places.items.len == 0) return "program not found: its checkup names no command and no Flatpak";
    return allocator.print("program not found: {s}", .{try std.mem.join(allocator, ", ", places.items)});
}

/// What is wrong with `include`, or null when its file holds the line, as it would after the
/// apply.
fn notIncluded(include: kosm.Checkup.Include, context: Context) !?[]const u8 {
    const path = try expandHome(include.file, context);
    if (!std.Io.Dir.path.isAbsolute(path))
        return try context.allocator.print("cannot check {s}: file paths start with ~/ or /", .{include.file});
    const file = context.planning.plan.loadExisting(path, include.file) catch |err|
        return try context.allocator.print("cannot read {s}: {s}", .{ include.file, @errorName(err) });
    const found = file orelse
        return try context.allocator.print("not included: {s} does not exist; create it holding `{s}`", .{ include.file, include.line });
    if (include.isIn(found.new)) return null;
    return try context.allocator.print("not included: add `{s}` to {s}", .{ include.line, include.file });
}

fn expandHome(path: []const u8, context: Context) ![]const u8 {
    if (std.mem.startsWith(u8, path, "~/")) return std.Io.Dir.path.join(context.allocator, &.{ context.home, path[2..] });
    return path;
}

const testing = std.testing;

const CheckedApp = struct {
    checkup_given: kosm.Checkup,

    pub fn apply(self: CheckedApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }

    pub fn checkup(self: CheckedApp) kosm.Checkup {
        return self.checkup_given;
    }
};

const UncheckedApp = struct {
    pub fn apply(self: UncheckedApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

const RecordingApp = struct {
    pub fn apply(self: RecordingApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }

    pub fn checkup(self: RecordingApp) kosm.Checkup {
        _ = self;
        kosm.failure.record("apps/cava.lua:4: attempt to index a nil value", .{});
        return .{};
    }
};

const UnappliedApp = struct {
    file: []const u8,

    pub fn apply(self: UnappliedApp, output: *kosm.Output) !void {
        if (self.file.len == 0) return error.GlowMissing;
        try output.verbatim(.{ .file = self.file, .content = "" });
    }

    pub fn checkup(self: UnappliedApp) kosm.Checkup {
        _ = self;
        return .{ .program = .{ .command = "never-checked" } };
    }
};

const Fixture = struct {
    tmp: testing.TmpDir,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    home: []const u8 = "",
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings = undefined,

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        fixture.warnings = .init(fixture.arena.allocator());
        fixture.home = fixture.home_buffer[0..try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer)];
        try fixture.tmp.dir.createDirPath(testing.io, "bin");
        try fixture.tmp.dir.createDirPath(testing.io, "flatpak/org.equicord.equibop");
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "bin/kitty", .data = "", .flags = .{ .permissions = .executable_file } });
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "bin/notes", .data = "" });
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn context(fixture: *Fixture) !Context {
        const allocator = fixture.arena.allocator();
        return .{
            .allocator = allocator,
            .io = testing.io,
            .home = fixture.home,
            .path_variable = try std.mem.concat(allocator, u8, &.{ "relative:", fixture.home, "/bin" }),
            .flatpak_folders = try allocator.dupe([]const u8, &.{try std.Io.Dir.path.join(allocator, &.{ fixture.home, "flatpak" })}),
            .planning = .{
                .allocator = allocator,
                .home = fixture.home,
                .adapters = &.{},
                .plan = &fixture.plan,
                .diagnostics = &fixture.diagnostics,
                .warnings = &fixture.warnings,
            },
        };
    }

    fn check(fixture: *Fixture, tree: anytype, problems: usize, expected: []const u8) !void {
        var output: std.Io.Writer.Allocating = .init(testing.allocator);
        defer output.deinit();
        try testing.expectEqual(problems, try checkTree(tree, try fixture.context(), &output.writer));
        try testing.expectEqualStrings(expected, output.written());
    }
};

test "an installed program reading the app's file is fine, and an app without a checkup has nothing to check" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "kitty.conf", .data = "font_size 12\ninclude kosm.conf\n" });
    const tree = .{
        .terminal = .{
            .kitty = CheckedApp{ .checkup_given = .{ .program = .{ .command = "kitty" }, .includes = &.{.{ .file = "~/kitty.conf", .line = "include kosm.conf" }} } },
            .foot = @as(?CheckedApp, null),
        },
        .gtk = UncheckedApp{},
        .equibop = CheckedApp{ .checkup_given = .{ .program = .{ .command = "equibop", .flatpak = "org.equicord.equibop" } } },
        .empty = CheckedApp{ .checkup_given = .{} },
    };
    try fixture.check(tree, 0,
        \\terminal.kitty  fine
        \\gtk             nothing to check
        \\equibop         fine
        \\empty           nothing to check
        \\
    );
}

test "a program found neither on PATH nor as a Flatpak is not found, naming both" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const tree = .{
        .equibop = CheckedApp{ .checkup_given = .{ .program = .{ .command = "equibop", .flatpak = "org.equicord.Equibop" } } },
        // Not executable, so no command, even though the file is on PATH.
        .notes = CheckedApp{ .checkup_given = .{ .program = .{ .command = "notes" } } },
        .kitty = CheckedApp{ .checkup_given = .{ .program = .{ .command = "~/bin/kitty" } } },
    };
    try fixture.check(tree, 2,
        \\equibop  program not found: no `equibop` command, no Flatpak org.equicord.Equibop
        \\notes    program not found: no `notes` command
        \\kitty    fine
        \\
    );
}

test "a file without the line, or missing, is not included, naming the line to add" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "config", .data = "# config-file = kosm\n" });
    const tree = .{
        .ghostty = CheckedApp{ .checkup_given = .{ .includes = &.{.{ .file = "~/config", .line = "config-file = kosm" }} } },
        .kitty = CheckedApp{ .checkup_given = .{ .program = .{ .command = "missing" }, .includes = &.{.{ .file = "~/kitty.conf", .line = "include kosm.conf" }} } },
    };
    try fixture.check(tree, 2,
        \\ghostty  not included: add `config-file = kosm` to ~/config
        \\kitty    program not found: no `missing` command; not included: ~/kitty.conf does not exist; create it holding `include kosm.conf`
        \\
    );
}

test "a line the apply would add counts as included, also in a file it would create" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "hyprland.lua", .data = "-- mine\n" });
    const existing = try std.Io.Dir.path.join(fixture.arena.allocator(), &.{ fixture.home, "hyprland.lua" });
    try fixture.plan.add(existing, "~/hyprland.lua", "hyprland", "-- mine\nhl.config(require(\"kosm\"))\n");
    const created = try std.Io.Dir.path.join(fixture.arena.allocator(), &.{ fixture.home, "new.lua" });
    try fixture.plan.add(created, "~/new.lua", "other", "include kosm\n");
    const tree = .{
        .hyprland = CheckedApp{ .checkup_given = .{ .includes = &.{.{ .file = "~/hyprland.lua", .line = "hl.config(require(\"kosm\"))" }} } },
        .other = CheckedApp{ .checkup_given = .{ .includes = &.{.{ .file = "~/new.lua", .line = "include kosm" }} } },
    };
    try fixture.check(tree, 0,
        \\hyprland  fine
        \\other     fine
        \\
    );
}

test "a script's failure in its checkup is that app's problem, and the others are still checked" {
    defer kosm.failure.clear();
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const tree = .{ .cava = RecordingApp{}, .kitty = CheckedApp{ .checkup_given = .{ .program = .{ .command = "kitty" } } } };
    try fixture.check(tree, 1,
        \\cava   cannot check: apps/cava.lua:4: attempt to index a nil value
        \\kitty  fine
        \\
    );
}

test "an app that cannot be applied is that app's problem, naming its file, and the others are still checked" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const tree = .{
        .relative = UnappliedApp{ .file = "relative.conf" },
        .failing = UnappliedApp{ .file = "" },
        .kitty = CheckedApp{ .checkup_given = .{ .program = .{ .command = "kitty" } } },
    };
    try fixture.check(tree, 2,
        \\relative  cannot apply relative.conf: file paths start with ~/ or /
        \\failing   cannot apply: apply failed: GlowMissing
        \\kitty     fine
        \\
    );
}
