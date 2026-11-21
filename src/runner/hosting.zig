//! The host apps written through a frontend run through in the runner of scripts: it reads each
//! app's script once, when its first function runs, hands it to the frontend claiming it, and
//! gives scripts handles to the theme, the output, the reloader and the apps themselves.

const std = @import("std");
const kosm = @import("kosm");
const discovery = @import("discovery.zig");
const Places = @import("Places.zig");

const Call = kosm.Frontend.Call;
const Handle = kosm.Frontend.Handle;
const Loose = kosm.Loose;
const ScriptApp = kosm.Frontend.ScriptApp;

/// Scripts are small; this only guards against reading something huge.
const max_script_size = 16 * 1024 * 1024;

/// The host of `frontends`, its scripts calling Zig code through `Library` (from
/// `bindings.Library`), handing scripts the types in `handled`.
pub fn Hosting(comptime frontends: []const discovery.DeclaredFrontend, comptime Library: type, comptime handled: []const type) type {
    return struct {
        /// What the host keeps for the whole run.
        pub const State = struct {
            arena: std.mem.Allocator,
            io: std.Io,
            /// The config project, which scripts' paths are relative to.
            config: []const u8,
            /// What `~~<name>/` stands for in a script's path: a package's root script is
            /// `~~<package>/root.lua`.
            folders: []const Places.Folder = &.{},
            library: kosm.Frontend.Library,
            /// Each script's text by its path, read once.
            sources: std.StringHashMapUnmanaged([]const u8) = .empty,

            fn source(state: *State, path: []const u8) ![]const u8 {
                if (state.sources.get(path)) |known| return known;
                const places: Places = .{ .home = state.config, .config = state.config, .kosmos = state.config, .folders = state.folders };
                const full = try places.resolve(state.arena, path);
                const text = try std.Io.Dir.cwd().readFileAlloc(state.io, full, state.arena, .limited(max_script_size));
                try state.sources.put(state.arena, path, text);
                return text;
            }
        };

        /// The host running through `state`, which must outlive it.
        pub fn host(state: *State) kosm.Frontend.Host {
            return .{ .state = state, .arena = state.arena, .run = run, .handle = handle };
        }

        fn run(state_pointer: *anyopaque, call: *Call, app: kosm.Frontend.ScriptFile, function: []const u8, arguments: []const Loose) Call.Error!Loose {
            const state: *State = @ptrCast(@alignCast(state_pointer));
            const frontend = for (frontends) |declared| {
                if (std.mem.eql(u8, declared.frontend.name, app.frontend)) break declared.frontend;
            } else return call.fail("{s}: no frontend of the config is named '{s}'", .{ app.path, app.frontend });
            const call_function = frontend.call orelse return call.fail("{s}: the {s} frontend runs no apps or adapters", .{ app.path, frontend.name });
            const text = state.source(app.path) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnknownPlace => return call.fail("{s}: the package holding it is not in the config's build.zig.zon, so kosm cannot find its script; kosm add it", .{app.path}),
                else => return call.fail("cannot read {s}: {s}", .{ app.path, @errorName(err) }),
            };
            var context: kosm.Frontend.Context = .{ .arena = call.arena, .path = app.path, .library = state.library };
            return call_function(&context, text, function, arguments) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidScript => {
                    const message = context.message orelse "it failed and did not say why";
                    if (std.mem.startsWith(u8, message, app.path)) return call.fail("{s}", .{message});
                    return call.fail("{s}: {s}", .{ app.path, message });
                },
            };
        }

        fn handle(state_pointer: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle {
            _ = state_pointer;
            inline for (handled) |T| {
                if (id == Handle.id(T)) return .{ .pointer = pointer, .type = Library.typeOf(T) };
            }
            return null;
        }
    };
}

/// The types the host hands scripts: the theme, the output and reloader, colors (for adapters),
/// and every app in `sources` written through a frontend.
pub fn handledTypes(comptime sources: []const discovery.AppSource) []const type {
    comptime var found: []const type = &.{ kosm.Theme, kosm.Output, kosm.Reloader, kosm.Color };
    inline for (sources) |source| {
        if (comptime isScriptApp(source.module)) found = found ++ .{source.module.App};
    }
    const final = found[0..found.len].*;
    return &final;
}

/// Whether `Module` is the generated module of an app written through a frontend.
pub fn isScriptApp(comptime Module: type) bool {
    if (@typeInfo(Module) != .@"struct" or !@hasDecl(Module, "App")) return false;
    const App = Module.App;
    return @TypeOf(App) == type and @typeInfo(App) == .@"struct" and @hasDecl(App, "script") and @TypeOf(App.script) == ScriptApp;
}

/// Whether any module of `sources` is the generated module of an adapter written through a
/// frontend, which only the runner of scripts can run.
pub fn holdsScriptAdapters(comptime sources: []const @import("Target.zig").AdapterSource) bool {
    inline for (sources) |source| {
        if (comptime isScriptAdapter(source.module)) return true;
    }
    return false;
}

/// Whether `Module` is the generated module of an adapter written through a frontend.
pub fn isScriptAdapter(comptime Module: type) bool {
    return @typeInfo(Module) == .@"struct" and @hasDecl(Module, "script") and @TypeOf(Module.script) == kosm.Frontend.ScriptAdapter;
}

/// Whether a tree of type `T` holds an app written through a frontend anywhere, which only the
/// runner of scripts can run.
pub fn holdsScriptApps(comptime T: type) bool {
    return holdsScriptAppsWithin(T, 0);
}

/// How deep `holdsScriptApps` looks; a type holding itself is taken for holding none beyond it.
const max_depth = 16;

fn holdsScriptAppsWithin(comptime T: type, comptime depth: usize) bool {
    @setEvalBranchQuota(discovery.branch_quota);
    if (depth > max_depth) return false;
    return switch (@typeInfo(T)) {
        .optional => |optional| holdsScriptAppsWithin(optional.child, depth + 1),
        .@"struct" => |info| blk: {
            if (@hasDecl(T, "script") and @TypeOf(T.script) == ScriptApp) break :blk true;
            if (kosm.app.is(T)) break :blk false;
            inline for (info.field_types) |Field| {
                if (holdsScriptAppsWithin(Field, depth + 1)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

const testing = std.testing;

const TestScriptApp = struct {
    size: i64 = 0,
    pub const script: ScriptApp = .{ .frontend = "test", .path = "apps/test.lua" };
    pub fn apply(self: TestScriptApp, output: *kosm.Output) !void {
        return script.apply(TestScriptApp, self, output);
    }
};

const TestZigApp = struct {
    size: i64 = 0,
    pub fn apply(self: TestZigApp, output: *kosm.Output) !void {
        _ = self;
        _ = output;
    }
};

test "sources hold script adapters when any module is one" {
    const script_adapter = struct {
        pub const script: kosm.Frontend.ScriptAdapter = .{ .frontend = "test", .path = "adapters/keys.lua" };
    };
    try testing.expect(holdsScriptAdapters(&.{ .{ .package = "kitty", .module = struct {} }, .{ .package = "keys", .module = script_adapter } }));
    try testing.expect(!holdsScriptAdapters(&.{.{ .package = "kitty", .module = struct {} }}));
}

test "a tree holds script apps when any app inside it, at any depth or optional, is one" {
    try testing.expect(holdsScriptApps(struct { terminal: struct { visualizer: ?TestScriptApp = null } }));
    try testing.expect(!holdsScriptApps(struct { terminal: struct { kitty: TestZigApp }, size: u8 }));
    try testing.expect(isScriptApp(struct {
        pub const App = TestScriptApp;
    }));
    try testing.expect(!isScriptApp(struct {
        pub const App = TestZigApp;
    }));
}
