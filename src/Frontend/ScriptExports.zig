//! What a package's root script exports, written through a frontend: where the script is, and
//! the calls the Zig module kosm generates for the package makes to run its functions through
//! `Host.current()`. A value it gives is typed like one written in Zig, so Zig and scripts use
//! it alike; a function field of that value (a look's `tweak`) gets a Zig function of its own
//! place, calling the function the script last gave there.

const ScriptExports = @This();

const std = @import("std");
const Loose = @import("../Loose.zig");
const Diagnostics = @import("../Diagnostics.zig");
const assignment = @import("../assignment.zig");
const failure = @import("../failure.zig");
const Host = @import("Host.zig");
const Call = @import("Call.zig");
const Handle = @import("Handle.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, in the package's folder: "~~kosm_frost/root.lua".
path: []const u8,

/// The script, as the host runs it.
pub fn file(exports: ScriptExports) ScriptFile {
    return .{ .frontend = exports.frontend, .path = exports.path };
}

/// The `T` the script's export `name` gives when called with `arguments` (a tuple): what it
/// returns, a value of its own or a table set on `T.default` (or `.{}` for a `T` without one),
/// and a Zig function at each place it gave a function. Like an app's `from` it cannot fail: a
/// failure is recorded like `kosm.fail`'s message, which kosm reports once the kosmos returns,
/// and the starting value is given.
pub fn give(comptime exports: ScriptExports, comptime T: type, comptime name: []const u8, arguments: anytype) T {
    comptime checkGiven(T, exports.path, name);
    var built: T = start(T);
    exports.fill(T, name, &built, arguments) catch |err| switch (err) {
        error.OutOfMemory => failure.record("{s}: {s}: out of memory", .{ exports.path, name }),
        // `fill` recorded why.
        error.KosmosFailed => {},
    };
    return built;
}

fn checkGiven(comptime T: type, comptime path: []const u8, comptime name: []const u8) void {
    if (@typeInfo(T) != .@"struct") @compileError(path ++ ": " ++ name ++ ": " ++ @typeName(T) ++ " is not a struct; an exported value is one");
    if (!hasDefault(T)) {
        for (@typeInfo(T).@"struct".field_attrs, @typeInfo(T).@"struct".field_names) |attributes, field| {
            if (attributes.default_value_ptr == null) @compileError(path ++ ": " ++ name ++ ": " ++ @typeName(T) ++ " has no `default` and its field '" ++ field ++ "' has no default, so kosm has nothing to start the value from");
        }
    }
}

fn hasDefault(comptime T: type) bool {
    return @hasDecl(T, "default") and @TypeOf(T.default) == T;
}

/// What a value of `T` the script returns as a table is set on: `T.default`, or `.{}`.
fn start(comptime T: type) T {
    return if (comptime hasDefault(T)) T.default else .{};
}

fn fill(comptime exports: ScriptExports, comptime T: type, comptime name: []const u8, built: *T, arguments: anytype) (std.mem.Allocator.Error || failure.Error)!void {
    const host = Host.current() orelse return failure.fail("{s}: {s}: a package written through a frontend runs only in the runner of scripts, and this runner is none", .{ exports.path, name });
    const given_arguments = try handOverAll(host, exports.path, name, arguments);
    var call = host.call();
    const given = host.run(host.state, &call, exports.file(), name, given_arguments) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CallFailed => return failure.fail("{s}", .{call.message orelse "it failed and did not say why"}),
    };
    var named = given;
    if (named.origin == null) named.origin = try host.arena.print("{s}: {s}", .{ exports.path, name });
    var diagnostics: Diagnostics = .{};
    const values = try withoutFunctions(T, host.arena, named);
    assignment.assignNamed(T, host.arena, built, values, &diagnostics, name) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidAssignment => return failure.fail("{s}", .{diagnostics.message()}),
    };
    placeFunctions(exports, T, name, built, named);
}

/// `arguments` (a tuple) as loose values a script is handed: plain values as they are, a struct
/// as a handle to a copy, a pointer as a handle to what it points at.
fn handOverAll(host: *const Host, comptime path: []const u8, comptime name: []const u8, arguments: anytype) (std.mem.Allocator.Error || failure.Error)![]const Loose {
    const fields = @typeInfo(@TypeOf(arguments)).@"struct".field_names;
    const handed = try host.arena.alloc(Loose, fields.len);
    inline for (fields, 0..) |field, position| {
        handed[position] = try handOver(host, path, name, @field(arguments, field));
    }
    return handed;
}

fn handOver(host: *const Host, comptime path: []const u8, comptime name: []const u8, value: anytype) (std.mem.Allocator.Error || failure.Error)!Loose {
    const T = @TypeOf(value);
    return .{ .value = switch (@typeInfo(T)) {
        .bool => .{ .boolean = value },
        .int, .comptime_int => .{ .integer = std.math.cast(i64, value) orelse return failure.fail("{s}: {s}: {d} is too large to hand to a script", .{ path, name, value }) },
        .float, .comptime_float => .{ .float = value },
        .@"enum" => .{ .string = @tagName(value) },
        .optional => if (value) |present| return handOver(host, path, name, present) else .null,
        .pointer => |pointer| switch (pointer.size) {
            .one => .{ .handle = try handleTo(host, path, name, pointer.child, @constCast(value)) },
            .slice => if (pointer.child == u8) .{ .string = value } else @compileError(path ++ ": " ++ name ++ ": a list (" ++ @typeName(T) ++ ") cannot be handed to a script yet"),
            else => @compileError(path ++ ": " ++ name ++ ": a " ++ @typeName(T) ++ " cannot be handed to a script"),
        },
        .@"struct", .@"union" => copied: {
            const kept = try host.arena.create(T);
            kept.* = value;
            break :copied .{ .handle = try handleTo(host, path, name, T, kept) };
        },
        else => @compileError(path ++ ": " ++ name ++ ": a " ++ @typeName(T) ++ " cannot be handed to a script"),
    } };
}

fn handleTo(host: *const Host, comptime path: []const u8, comptime name: []const u8, comptime T: type, pointer: *T) failure.Error!Handle {
    return host.handleOf(T, pointer) orelse failure.fail("{s}: {s}: a {s} cannot be handed to a script here", .{ path, name, @typeName(T) });
}

/// The function type a field of type `Field` points at (`*const fn` or `?*const fn`), or null.
pub fn FunctionOf(comptime Field: type) ?type {
    const Pointer = switch (@typeInfo(Field)) {
        .optional => |optional| optional.child,
        else => Field,
    };
    const info = switch (@typeInfo(Pointer)) {
        .pointer => |pointer| pointer,
        else => return null,
    };
    if (info.size != .one or @typeInfo(info.child) != .@"fn") return null;
    return info.child;
}

/// The struct inside `Field` (itself, or what an optional holds), or null.
fn StructOf(comptime Field: type) ?type {
    const Inner = switch (@typeInfo(Field)) {
        .optional => |optional| optional.child,
        else => Field,
    };
    return if (@typeInfo(Inner) == .@"struct" and !@typeInfo(Inner).@"struct".is_tuple) Inner else null;
}

/// Whether a `T` holds a function field anywhere in its structs, which only then are walked.
fn holdsFunctions(comptime T: type) bool {
    @setEvalBranchQuota(100_000);
    const Inner = StructOf(T) orelse return false;
    inline for (@typeInfo(Inner).@"struct".field_types) |Field| {
        if (FunctionOf(Field) != null) return true;
        if (StructOf(Field)) |Nested| {
            if (Nested != Inner and holdsFunctions(Nested)) return true;
        }
    }
    return false;
}

/// The types a function field anywhere in `T` hands a script: each parameter's type, or what a
/// pointer parameter points at. The host must be able to hand them over.
pub fn handedTypes(comptime T: type) []const type {
    @setEvalBranchQuota(100_000);
    comptime var found: []const type = &.{};
    if (comptime !holdsFunctions(T)) return found;
    const Inner = StructOf(T).?;
    inline for (@typeInfo(Inner).@"struct".field_types) |Field| {
        if (comptime FunctionOf(Field)) |Function| {
            inline for (@typeInfo(Function).@"fn".param_types) |Parameter| {
                found = found ++ .{HandedType(Parameter.?)};
            }
        } else if (comptime StructOf(Field)) |Nested| {
            if (Nested != Inner) found = found ++ handedTypes(Nested);
        }
    }
    const final = found[0..found.len].*;
    return &final;
}

/// The type a script is handed for a parameter of type `Parameter`: what a pointer points at.
pub fn HandedType(comptime Parameter: type) type {
    return switch (@typeInfo(Parameter)) {
        .pointer => |pointer| if (pointer.size == .one) pointer.child else Parameter,
        .optional => |optional| HandedType(optional.child),
        else => Parameter,
    };
}

/// `loose` without the functions it gives function fields of `T`, which `placeFunctions` sets.
fn withoutFunctions(comptime T: type, arena: std.mem.Allocator, loose: Loose) std.mem.Allocator.Error!Loose {
    if (comptime !holdsFunctions(T)) return loose;
    const Inner = StructOf(T).?;
    if (loose.value != .table) return loose;
    var kept: std.ArrayList(Loose.Entry) = .empty;
    entries: for (loose.value.table) |entry| {
        inline for (@typeInfo(Inner).@"struct".field_names, @typeInfo(Inner).@"struct".field_types) |field, Field| {
            if (std.mem.eql(u8, field, entry.key)) {
                if (comptime FunctionOf(Field) != null) {
                    if (entry.value.value == .function) continue :entries;
                } else if (comptime StructOf(Field) != null) {
                    try kept.append(arena, .{ .key = entry.key, .value = try withoutFunctions(Field, arena, entry.value) });
                    continue :entries;
                }
            }
        }
        try kept.append(arena, entry);
    }
    var result = loose;
    result.value = .{ .table = kept.items };
    return result;
}

/// Sets each function field of `target` that `loose` gives a function to the Zig function of
/// its place (`place` and the field names leading to it: "look.tweak").
fn placeFunctions(comptime exports: ScriptExports, comptime T: type, comptime place: []const u8, target: *T, loose: Loose) void {
    if (comptime !holdsFunctions(T)) return;
    if (loose.value != .table) return;
    if (@typeInfo(T) == .optional) {
        if (target.*) |*present| placeFunctions(exports, @typeInfo(T).optional.child, place, present, loose);
        return;
    }
    for (loose.value.table) |entry| {
        inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |field, Field| {
            if (std.mem.eql(u8, field, entry.key)) {
                const inner = place ++ "." ++ field;
                if (comptime FunctionOf(Field)) |Function| {
                    if (entry.value.value == .function) @field(target.*, field) = Trampoline(exports, inner, Function).function;
                } else if (comptime StructOf(Field) != null) {
                    placeFunctions(exports, Field, inner, &@field(target.*, field), entry.value);
                }
            }
        }
    }
}

/// The Zig function of `place`, of type `Function`: it calls the function the script last gave
/// there with its arguments. It cannot fail, so a failure is recorded like `kosm.fail`'s
/// message, which kosm reports once the kosmos returns.
fn Trampoline(comptime exports: ScriptExports, comptime place: []const u8, comptime Function: type) type {
    const info = @typeInfo(Function).@"fn";
    if (info.return_type != void) @compileError(exports.path ++ ": " ++ place ++ ": only a function returning nothing can be given by a script, and this one returns " ++ @typeName(info.return_type.?));
    const P = info.param_types;
    return struct {
        const function: *const Function = switch (P.len) {
            0 => call0,
            1 => call1,
            2 => call2,
            3 => call3,
            4 => call4,
            else => @compileError(exports.path ++ ": " ++ place ++ ": a function given by a script takes at most 4 parameters"),
        };
        fn call0() void {
            run(.{});
        }
        fn call1(a: P[0].?) void {
            run(.{a});
        }
        fn call2(a: P[0].?, b: P[1].?) void {
            run(.{ a, b });
        }
        fn call3(a: P[0].?, b: P[1].?, c: P[2].?) void {
            run(.{ a, b, c });
        }
        fn call4(a: P[0].?, b: P[1].?, c: P[2].?, d: P[3].?) void {
            run(.{ a, b, c, d });
        }
        fn run(arguments: anytype) void {
            runAt(exports, place, arguments) catch |err| switch (err) {
                error.OutOfMemory => failure.record("{s}: {s}: out of memory", .{ exports.path, place }),
                // `runAt` recorded why.
                error.KosmosFailed => {},
            };
        }
    };
}

fn runAt(comptime exports: ScriptExports, comptime place: []const u8, arguments: anytype) (std.mem.Allocator.Error || failure.Error)!void {
    const host = Host.current() orelse return failure.fail("{s}: {s}: a package written through a frontend runs only in the runner of scripts, and this runner is none", .{ exports.path, place });
    const given_arguments = try handOverAll(host, exports.path, place, arguments);
    var call = host.call();
    _ = host.run(host.state, &call, exports.file(), place, given_arguments) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CallFailed => return failure.fail("{s}", .{call.message orelse "it failed and did not say why"}),
    };
}

const testing = std.testing;

const TestFonts = struct { size: i64 = 13, family: []const u8 = "monospace" };

const TestBase = struct { size: i64 = 0 };

const TestLook = struct {
    fonts: TestFonts,
    rounding: i64 = 0,
    tweak: ?*const fn (base: *TestBase, look: TestLook) void = null,

    pub const default: TestLook = .{ .fonts = .{} };
};

/// What the test host saw last: the function run and the base it was handed.
const Seen = struct {
    var function: []const u8 = "";
    var base: ?*TestBase = null;
};

/// A host whose `look` returns a table with fonts and a tweak, `broken` fails, and whose
/// `look.tweak` sets the size of the base it is handed.
const TestHost = struct {
    fn run(state: *anyopaque, call: *Call, script: ScriptFile, function: []const u8, arguments: []const Loose) Call.Error!Loose {
        _ = state;
        _ = script;
        Seen.function = function;
        if (std.mem.eql(u8, function, "broken")) return call.fail("~~kosm_frost/root.lua:3: attempt to index a nil value", .{});
        if (std.mem.eql(u8, function, "look.tweak")) {
            const base = arguments[0].value.handle.as(TestBase).?;
            const look = arguments[1].value.handle.as(TestLook).?;
            base.size = look.fonts.size;
            Seen.base = base;
            return .{ .value = .null };
        }
        const fonts = try call.arena.dupe(Loose.Entry, &.{.{ .key = "size", .value = .{ .value = .{ .integer = 14 } } }});
        return .{ .value = .{ .table = try call.arena.dupe(Loose.Entry, &.{
            .{ .key = "fonts", .value = .{ .value = .{ .table = fonts } } },
            .{ .key = "tweak", .value = .{ .value = .{ .function = "look.tweak" } } },
        }) } };
    }

    fn handle(state: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle {
        _ = state;
        const Types = struct {
            const base: Handle.Type = .{ .id = Handle.id(TestBase), .name = "TestBase", .get = undefined, .set = undefined, .length = undefined };
            const look: Handle.Type = .{ .id = Handle.id(TestLook), .name = "TestLook", .get = undefined, .set = undefined, .length = undefined };
        };
        if (id == Handle.id(TestBase)) return .{ .pointer = pointer, .type = &Types.base };
        if (id == Handle.id(TestLook)) return .{ .pointer = pointer, .type = &Types.look };
        return null;
    }
};

const test_exports: ScriptExports = .{ .frontend = "test", .path = "~~kosm_frost/root.lua" };

test "an exported value is the script's table set on the type's default, and its function field calls the script" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host: Host = .{ .state = undefined, .arena = arena.allocator(), .run = TestHost.run, .handle = TestHost.handle };
    Host.install(&host);
    defer Host.install(null);
    failure.clear();
    defer failure.clear();
    const look = test_exports.give(TestLook, "look", .{});
    try testing.expectEqual(null, failure.message());
    try testing.expectEqual(14, look.fonts.size);
    try testing.expectEqualStrings("monospace", look.fonts.family);
    var base: TestBase = .{};
    look.tweak.?(&base, look);
    try testing.expectEqual(null, failure.message());
    try testing.expectEqualStrings("look.tweak", Seen.function);
    try testing.expectEqual(&base, Seen.base.?);
    try testing.expectEqual(14, base.size);
}

test "a failing export records the script's message and gives the default" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host: Host = .{ .state = undefined, .arena = arena.allocator(), .run = TestHost.run, .handle = TestHost.handle };
    Host.install(&host);
    defer Host.install(null);
    failure.clear();
    defer failure.clear();
    const look = test_exports.give(TestLook, "broken", .{});
    try testing.expectEqual(13, look.fonts.size);
    try testing.expectEqual(null, look.tweak);
    try testing.expectEqualStrings("~~kosm_frost/root.lua:3: attempt to index a nil value", failure.message().?);
}

test "an export run outside the runner of scripts records why" {
    Host.install(null);
    failure.clear();
    defer failure.clear();
    _ = test_exports.give(TestLook, "look", .{});
    try testing.expectEqualStrings("~~kosm_frost/root.lua: look: a package written through a frontend runs only in the runner of scripts, and this runner is none", failure.message().?);
}

test "the types a value's function fields hand a script are what their parameters point at" {
    const handed = comptime handedTypes(TestLook);
    try testing.expectEqual(2, handed.len);
    try testing.expect(handed[0] == TestBase and handed[1] == TestLook);
    try testing.expectEqual(0, comptime handedTypes(TestFonts).len);
}
