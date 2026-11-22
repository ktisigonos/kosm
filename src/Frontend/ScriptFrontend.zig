//! A frontend written through another frontend: where its script is, and the functions the Zig
//! module kosm generates for it gives kosm, each running the script's function of the same name
//! through `Host.current()`. What crosses is plain tables:
//! - `load(source, path, variant)` gets a script kosmos' text, its place ("kosmoi/mine.json") and
//!   the variant to build as a list of names, and returns a table of `Script`'s fields: `base`
//!   and the tables `params`, `theme` and `overrides`, or `tree` alone, a Zig value.
//! - `variants(source, path)` returns the variants the script gives, as a list of names spelled
//!   as `kosm apply` takes them after the script's own ("dark.soft").
//! - `complete(completion)` gets `Completion` as tables, a union as `{ kind = "record",
//!   value = "kosm_kitty.App" }` (no `value` for a tag without one), a null field left out, and
//!   returns a list of files, `{ path = "kosmos.schema.json", contents = "..." }`.
//! A script fails a function by raising an error. One starting with the place it read in the
//! kosmos ("kosmoi/mine.json:3: ...") is reported at that place alone.

const ScriptFrontend = @This();

const std = @import("std");
const Loose = @import("../Loose.zig");
const Host = @import("Host.zig");
const Context = @import("Context.zig");
const Script = @import("Script.zig");
const Completion = @import("Completion.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, relative to the config: "frontends/json.lua".
path: []const u8,

const Error = std.mem.Allocator.Error || error{InvalidScript};

const no_host = "a frontend written through a frontend runs only in the runner of scripts, and this runner is none";

/// What `load`'s returned table holds, for messages.
const script_fields = "base, params, theme and overrides, or tree alone";

/// The script, as the host runs it.
pub fn file(script: ScriptFrontend) ScriptFile {
    return .{ .frontend = script.frontend, .path = script.path };
}

/// The functions of `script` as `kosm.Frontend` takes them; the generated module sets those
/// its script gives.
pub fn Functions(comptime script: ScriptFrontend) type {
    return struct {
        pub fn load(context: *Context, source: []const u8) Error!Script {
            return script.loadScript(context, source);
        }

        pub fn variants(context: *Context, source: []const u8) Error![]const []const u8 {
            return script.listVariants(context, source);
        }

        pub fn complete(context: *Context, completion: Completion) Error![]const Completion.File {
            return script.writeCompletion(context, completion);
        }
    };
}

/// Runs the script's `load(source, path, variant)` and reads the table it returns.
pub fn loadScript(script: ScriptFrontend, context: *Context, source: []const u8) Error!Script {
    const variant = try context.arena.alloc(Loose, context.variant.len);
    for (context.variant, variant) |name, *item| item.* = text(name);
    const given = try script.run(context, "load", &.{ text(source), text(context.path), .{ .value = .{ .list = variant } } });
    const entries = try script.tableOf(context, "load", given, script_fields);
    var found: Script = .{};
    for (entries) |entry| {
        const value = entry.value;
        if (value.value == .null) return script.fail(context, value, "load returned {s} set to null; leave it out instead", .{entry.key});
        if (std.mem.eql(u8, entry.key, "base")) {
            found.base = if (value.value == .string) value.value.string else return script.fail(context, value, "load returned a base that is {s}; it is a kosmos' name", .{describe(value)});
        } else if (std.mem.eql(u8, entry.key, "params")) {
            found.params = value;
        } else if (std.mem.eql(u8, entry.key, "theme")) {
            found.theme = value;
        } else if (std.mem.eql(u8, entry.key, "overrides")) {
            found.overrides = value;
        } else if (std.mem.eql(u8, entry.key, "tree")) {
            found.tree = if (value.value == .handle) value.value.handle else return script.fail(context, value, "load returned a tree that is {s}; it is a tree a Zig kosmos built", .{describe(value)});
        } else return script.fail(context, value, "load returned a table setting '{s}'; it holds {s}", .{ entry.key, script_fields });
    }
    if (found.tree != null and entries.len != 1) return script.fail(context, given, "load returned a tree beside other fields; a tree comes alone", .{});
    return found;
}

/// Runs the script's `variants(source, path)` and reads the names it returns.
pub fn listVariants(script: ScriptFrontend, context: *Context, source: []const u8) Error![]const []const u8 {
    const given = try script.run(context, "variants", &.{ text(source), text(context.path) });
    const items = try script.listOf(context, "variants", given);
    const names = try context.arena.alloc([]const u8, items.len);
    for (items, names) |item, *name| {
        name.* = if (item.value == .string) item.value.string else return script.fail(context, item, "variants returned a list holding {s}; it lists the variants' names", .{describe(item)});
    }
    return names;
}

/// Runs the script's `complete(completion)` and reads the files it returns.
pub fn writeCompletion(script: ScriptFrontend, context: *Context, completion: Completion) Error![]const Completion.File {
    const given = try script.run(context, "complete", &.{try looseOf(context.arena, completion)});
    const items = try script.listOf(context, "complete", given);
    const files = try context.arena.alloc(Completion.File, items.len);
    const shape = "a file is a table of path and contents";
    for (items, files) |item, *written| {
        const entries = try script.tableOf(context, "complete", item, shape);
        var path: ?[]const u8 = null;
        var contents: ?[]const u8 = null;
        for (entries) |entry| {
            const slot = if (std.mem.eql(u8, entry.key, "path")) &path else if (std.mem.eql(u8, entry.key, "contents")) &contents else return script.fail(context, entry.value, "complete returned a file setting '{s}'; {s}", .{ entry.key, shape });
            slot.* = if (entry.value.value == .string) entry.value.value.string else return script.fail(context, entry.value, "complete returned a file whose {s} is {s}, not text", .{ entry.key, describe(entry.value) });
        }
        written.* = .{
            .path = path orelse return script.fail(context, item, "complete returned a file without a path; {s}", .{shape}),
            .contents = contents orelse return script.fail(context, item, "complete returned a file without contents; {s}", .{shape}),
        };
    }
    return files;
}

/// Runs the script's `function` with `arguments`, failing through `context` with the script's
/// message.
fn run(script: ScriptFrontend, context: *Context, function: []const u8, arguments: []const Loose) Error!Loose {
    const host = Host.current() orelse return context.fail("{s}: {s}", .{ script.path, no_host });
    var call = host.call();
    return host.run(host.state, &call, script.file(), function, arguments) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.CallFailed => context.fail("{s}", .{script.placed(context.path, call.message orelse "it failed and did not say why")}),
    };
}

/// `message` at the kosmos' place alone when it starts there, as an error the script raised
/// about the kosmos it reads; otherwise at the frontend's script, as the host gives it.
fn placed(script: ScriptFrontend, kosmos: []const u8, message: []const u8) []const u8 {
    if (!std.mem.startsWith(u8, message, script.path)) return message;
    const rest = message[script.path.len..];
    if (!std.mem.startsWith(u8, rest, ": ")) return message;
    const about = rest[2..];
    if (kosmos.len != 0 and std.mem.startsWith(u8, about, kosmos)) return about;
    return message;
}

/// The entries of `given`, which `function` must have returned as a table holding `shape`.
fn tableOf(script: ScriptFrontend, context: *Context, comptime function: []const u8, given: Loose, shape: []const u8) Error![]const Loose.Entry {
    return switch (given.value) {
        .table => |entries| entries,
        // An empty table reads as an empty list.
        .list => |items| if (items.len == 0) &.{} else script.fail(context, given, function ++ " returned a list; {s}", .{shape}),
        else => script.fail(context, given, function ++ " returned {s}; {s}", .{ describe(given), shape }),
    };
}

/// The items of `given`, which `function` must have returned as a list.
fn listOf(script: ScriptFrontend, context: *Context, comptime function: []const u8, given: Loose) Error![]const Loose {
    return switch (given.value) {
        .list => |items| items,
        .table => |entries| if (entries.len == 0) &.{} else script.fail(context, given, function ++ " returned a table with names; it returns a list", .{}),
        else => script.fail(context, given, function ++ " returned {s}; it returns a list", .{describe(given)}),
    };
}

/// Fails at `value`'s place, or at the script's when it has none.
fn fail(script: ScriptFrontend, context: *Context, value: Loose, comptime format: []const u8, arguments: anytype) Error {
    const message = try context.arena.print(format, arguments);
    return context.fail("{s}: {s}", .{ value.origin orelse script.path, message });
}

fn text(value: []const u8) Loose {
    return .{ .value = .{ .string = value } };
}

/// What `value` is, for messages.
fn describe(value: Loose) []const u8 {
    return switch (value.value) {
        .table => "a table",
        .list => "a list",
        .string, .text => "text",
        .integer => "an integer",
        .float => "a number",
        .boolean => "a boolean",
        .null => "null",
        .handle => "a value from Zig",
        .function => "a function",
    };
}

/// `value`, plain data, as loose tables a script reads: a struct as a table without its null
/// fields, a slice as a list (text as text), a union as `{ kind, value }`, an enum as its name.
pub fn looseOf(arena: std.mem.Allocator, value: anytype) std.mem.Allocator.Error!Loose {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .bool => .{ .value = .{ .boolean = value } },
        .int, .comptime_int => .{ .value = .{ .integer = @intCast(value) } },
        .float => .{ .value = .{ .float = value } },
        .@"enum" => text(@tagName(value)),
        .optional => if (value) |present| looseOf(arena, present) else .{ .value = .null },
        .pointer => |pointer| switch (pointer.size) {
            .one => looseOf(arena, value.*),
            .slice => if (pointer.child == u8) text(value) else list: {
                const items = try arena.alloc(Loose, value.len);
                for (value, items) |item, *loose| loose.* = try looseOf(arena, item);
                break :list .{ .value = .{ .list = items } };
            },
            else => @compileError("no loose form for " ++ @typeName(T)),
        },
        .@"struct" => |info| table: {
            var entries: std.ArrayList(Loose.Entry) = .empty;
            inline for (info.field_names, info.field_types) |name, Field| {
                const field_value = @field(value, name);
                const absent = @typeInfo(Field) == .optional and field_value == null;
                if (!absent) try entries.append(arena, .{ .key = name, .value = try looseOf(arena, field_value) });
            }
            break :table .{ .value = .{ .table = entries.items } };
        },
        .@"union" => switch (value) {
            inline else => |payload, tag| table: {
                const kind: Loose.Entry = .{ .key = "kind", .value = text(@tagName(tag)) };
                if (@TypeOf(payload) == void) break :table .{ .value = .{ .table = try arena.dupe(Loose.Entry, &.{kind}) } };
                break :table .{ .value = .{ .table = try arena.dupe(Loose.Entry, &.{ kind, .{ .key = "value", .value = try looseOf(arena, payload) } }) } };
            },
        },
        else => @compileError("no loose form for " ++ @typeName(T)),
    };
}

const testing = std.testing;

fn entryOf(loose: Loose, key: []const u8) ?Loose {
    for (loose.value.table) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return entry.value;
    }
    return null;
}

test "completion crosses as tables: unions as kind and value, null fields left out" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const color: Completion.Type = .color;
    const completion: Completion = .{
        .records = &.{.{ .name = "kosm_kitty.App", .fields = &.{
            .{ .name = "foreground", .doc = "The text color.", .type = .{ .optional = &color } },
            .{ .name = "shape", .type = .{ .choice = &.{ "block", "beam" } } },
            .{ .name = "bare", .type = null },
        } }},
        .kosmoi = &.{.{ .name = "personal", .tree = "kosmoi.personal.Tree" }},
        .standalone = "kosm.Standalone",
        .theme = "kosm.Theme.Input",
    };
    const loose = try looseOf(arena, completion);
    try testing.expectEqualStrings("kosm.Standalone", entryOf(loose, "standalone").?.value.string);
    const fields = entryOf(entryOf(loose, "records").?.value.list[0], "fields").?.value.list;
    try testing.expectEqualStrings("The text color.", entryOf(fields[0], "doc").?.value.string);
    const foreground = entryOf(fields[0], "type").?;
    try testing.expectEqualStrings("optional", entryOf(foreground, "kind").?.value.string);
    const inner = entryOf(foreground, "value").?;
    try testing.expectEqualStrings("color", entryOf(inner, "kind").?.value.string);
    try testing.expectEqual(null, entryOf(inner, "value"));
    try testing.expectEqualStrings("beam", entryOf(entryOf(fields[1], "type").?, "value").?.value.list[1].value.string);
    try testing.expectEqual(null, entryOf(fields[2], "type"));
    try testing.expectEqual(null, entryOf(entryOf(loose, "kosmoi").?.value.list[0], "params"));
}

const test_script: ScriptFrontend = .{ .frontend = "test", .path = "frontends/json.lua" };

test "an error the script raises about the kosmos is reported at the kosmos' place alone" {
    try testing.expectEqualStrings("kosmoi/mine.json:3: expected a value", test_script.placed("kosmoi/mine.json", "frontends/json.lua: kosmoi/mine.json:3: expected a value"));
    try testing.expectEqualStrings("frontends/json.lua:40: attempt to index a nil value", test_script.placed("kosmoi/mine.json", "frontends/json.lua:40: attempt to index a nil value"));
    try testing.expectEqualStrings("frontends/json.lua: it broke", test_script.placed("kosmoi/mine.json", "frontends/json.lua: it broke"));
}
