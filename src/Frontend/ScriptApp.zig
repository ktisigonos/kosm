//! An app written through a frontend: where its script is, and the calls the Zig module kosm
//! generates for it makes to run the script's `from`, `apply` and `reload` through
//! `Host.current()`. Its `App` keeps a Zig app's shape, so it is used like any app.

const ScriptApp = @This();

const std = @import("std");
const Loose = @import("../Loose.zig");
const Theme = @import("../Theme.zig");
const Output = @import("../Output.zig");
const Reloader = @import("../Reloader.zig");
const Diagnostics = @import("../Diagnostics.zig");
const assignment = @import("../assignment.zig");
const failure = @import("../failure.zig");
const Host = @import("Host.zig");
const Call = @import("Call.zig");
const Handle = @import("Handle.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, relative to the config: "apps/cava/root.lua".
path: []const u8,

/// The script, as the host runs it.
pub fn file(app: ScriptApp) ScriptFile {
    return .{ .frontend = app.frontend, .path = app.path };
}

/// The app the script's `from(theme)` gives: the fields of the table it returns, set on the
/// app's defaults. Like a Zig app's `from` it cannot fail: a failure is recorded like
/// `kosm.fail`'s message, which kosm reports once the kosmos returns, and the defaults are given.
pub fn from(app: ScriptApp, comptime App: type, theme: Theme) App {
    var built: App = .{};
    app.fill(App, &built, theme) catch |err| switch (err) {
        error.OutOfMemory => failure.record("{s}: out of memory", .{app.path}),
        // `fill` recorded why.
        error.KosmosFailed => {},
    };
    return built;
}

fn fill(app: ScriptApp, comptime App: type, built: *App, theme: Theme) (std.mem.Allocator.Error || failure.Error)!void {
    const host = Host.current() orelse return failure.fail("{s}: an app written through a frontend runs only in the runner of scripts, and this runner is none", .{app.path});
    const kept = try host.arena.create(Theme);
    kept.* = theme;
    const theme_handle = host.handleOf(Theme, kept) orelse return failure.fail("{s}: a kosm.Theme cannot be handed to a script here", .{app.path});
    var call = host.call();
    const given = host.run(host.state, &call, app.file(), "from", &.{.{ .value = .{ .handle = theme_handle } }}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CallFailed => return failure.fail("{s}", .{call.message orelse "from failed and did not say why"}),
    };
    var diagnostics: Diagnostics = .{};
    const origin = try host.arena.print("{s}: from", .{app.path});
    assignment.assignNamed(App, host.arena, built, withOrigin(given, origin), &diagnostics, "the app") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidAssignment => return failure.fail("{s}", .{diagnostics.message()}),
    };
}

/// `loose` with `origin` where it names none, so messages about it name the script.
fn withOrigin(loose: Loose, origin: []const u8) Loose {
    var named = loose;
    if (named.origin == null) named.origin = origin;
    return named;
}

/// Runs the script's `apply(self, output)`. A failure fails the apply with the script's message,
/// naming the file when a call on `output` failed.
pub fn apply(app: ScriptApp, comptime App: type, self: App, output: *Output) Output.Error!void {
    const host = Host.current() orelse return output.fail("", "{s}: an app written through a frontend runs only in the runner of scripts, and this runner is none", .{app.path});
    const kept = try output.allocator.create(App);
    kept.* = self;
    const self_handle = host.handleOf(App, kept) orelse return output.fail("", "{s}: the app cannot be handed to its script", .{app.path});
    const output_handle = host.handleOf(Output, output) orelse return output.fail("", "{s}: a kosm.Output cannot be handed to a script here", .{app.path});
    var call = host.call();
    _ = host.run(host.state, &call, app.file(), "apply", &.{ .{ .value = .{ .handle = self_handle } }, .{ .value = .{ .handle = output_handle } } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CallFailed => {
            // A call on `output` that failed recorded its file; the script's message holds its own.
            const failed_file = if (output.diagnostics.message().len != 0) output.diagnostics.file else "";
            return output.fail(failed_file, "{s}", .{call.message orelse "apply failed and did not say why"});
        },
    };
}

/// Runs the script's `reload(self, reloader)`.
pub fn reload(app: ScriptApp, comptime App: type, self: App, reloader: *Reloader) Reloader.Error!void {
    const host = Host.current() orelse return reloader.fail("{s}: an app written through a frontend runs only in the runner of scripts, and this runner is none", .{app.path});
    const kept = host.arena.create(App) catch return reloader.fail("out of memory", .{});
    kept.* = self;
    const self_handle = host.handleOf(App, kept) orelse return reloader.fail("{s}: the app cannot be handed to its script", .{app.path});
    const reloader_handle = host.handleOf(Reloader, reloader) orelse return reloader.fail("{s}: a kosm.Reloader cannot be handed to a script here", .{app.path});
    var call = host.call();
    _ = host.run(host.state, &call, app.file(), "reload", &.{ .{ .value = .{ .handle = self_handle } }, .{ .value = .{ .handle = reloader_handle } } }) catch |err| switch (err) {
        error.OutOfMemory => return reloader.fail("out of memory", .{}),
        error.CallFailed => return reloader.fail("{s}", .{call.message orelse "reload failed and did not say why"}),
    };
}

const testing = std.testing;

/// A host whose `from` returns a table (or fails, for `apps/broken.lua`) and whose `apply`
/// fails after a call on `output` failed.
const TestHost = struct {
    fn run(state: *anyopaque, call: *Call, app: ScriptFile, function: []const u8, arguments: []const Loose) Call.Error!Loose {
        _ = state;
        if (std.mem.eql(u8, function, "from")) {
            if (std.mem.eql(u8, app.path, "apps/broken.lua")) return call.fail("apps/broken.lua:3: attempt to index a nil value", .{});
            if (std.mem.eql(u8, app.path, "apps/wrong.lua")) return .{ .value = .{ .table = &.{.{ .key = "size", .value = .{ .value = .{ .string = "big" } } }} } };
            const theme = arguments[0].value.handle.as(Theme).?;
            return .{ .value = .{ .table = try call.arena.dupe(Loose.Entry, &.{
                .{ .key = "size", .value = .{ .value = .{ .integer = if (theme.mode == .light) 2 else 1 } } },
                .{ .key = "name", .value = .{ .value = .{ .string = "cava" } } },
            }) } };
        }
        const output = arguments[1].value.handle.as(Output).?;
        output.diagnostics.set(output.app, "~/.config/cava/config", "no adapter claims it", .{});
        return call.fail("apps/cava.lua:9: kosm.Output.generateValue: no adapter claims it", .{});
    }

    fn handle(state: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle {
        _ = state;
        inline for (.{ Theme, Output, TestApp }) |T| {
            if (id == Handle.id(T)) return .{ .pointer = pointer, .type = tableOf(T) };
        }
        return null;
    }

    /// A table good only for telling the handle's type; nothing reads through it.
    fn tableOf(comptime T: type) *const Handle.Type {
        return &struct {
            const table: Handle.Type = .{ .id = Handle.id(T), .name = @typeName(T), .get = undefined, .set = undefined, .length = undefined };
        }.table;
    }
};

const TestApp = struct {
    size: i64 = 0,
    name: ?[]const u8 = null,
};

fn testTheme(mode: Theme.Mode) Theme {
    const black = @import("../root.zig").hex("000000");
    const white = @import("../root.zig").hex("ffffff");
    return .from(.{ .palette = .{ .black = black, .white = white }, .mode = mode });
}

fn withTestHost(arena: std.mem.Allocator) Host {
    return .{ .state = undefined, .arena = arena, .run = TestHost.run, .handle = TestHost.handle };
}

test "from sets the fields of the table the script returns on the app's defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    failure.clear();
    const app: ScriptApp = .{ .frontend = "test", .path = "apps/cava.lua" };
    const built = app.from(TestApp, testTheme(.light));
    try testing.expectEqual(2, built.size);
    try testing.expectEqualStrings("cava", built.name.?);
    try testing.expectEqual(null, failure.message());
}

test "a failing from is recorded for kosm to report and gives the defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    defer failure.clear();
    failure.clear();
    const broken = (ScriptApp{ .frontend = "test", .path = "apps/broken.lua" }).from(TestApp, testTheme(.dark));
    try testing.expectEqual(0, broken.size);
    try testing.expectEqualStrings("apps/broken.lua:3: attempt to index a nil value", failure.message().?);
    failure.clear();
    _ = (ScriptApp{ .frontend = "test", .path = "apps/wrong.lua" }).from(TestApp, testTheme(.dark));
    try testing.expect(std.mem.startsWith(u8, failure.message().?, "apps/wrong.lua: from: size: "));
    failure.clear();
    Host.install(null);
    _ = (ScriptApp{ .frontend = "test", .path = "apps/cava.lua" }).from(TestApp, testTheme(.dark));
    try testing.expectEqualStrings("apps/cava.lua: an app written through a frontend runs only in the runner of scripts, and this runner is none", failure.message().?);
}

test "a failing apply names the file a call on its output failed on, with the script's message" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    var plan: @import("../Plan.zig") = .init(testing.allocator, testing.io);
    defer plan.deinit();
    var diagnostics: Diagnostics = .{ .kosmos = "frost" };
    var warnings: @import("../Warnings.zig") = .init(arena.allocator());
    var output: Output = .{ .allocator = arena.allocator(), .home = "/home/test", .adapters = &.{}, .plan = &plan, .diagnostics = &diagnostics, .warnings = &warnings, .app = "cava" };
    const app: ScriptApp = .{ .frontend = "test", .path = "apps/cava.lua" };
    try testing.expectError(error.AppFailed, app.apply(TestApp, .{}, &output));
    try testing.expectEqualStrings("~/.config/cava/config", diagnostics.file);
    try testing.expectEqualStrings("apps/cava.lua:9: kosm.Output.generateValue: no adapter claims it", diagnostics.message());
}
