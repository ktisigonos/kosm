//! An adapter written through a frontend: where its script is, and the capabilities the Zig
//! module kosm generates for it gives kosm, each running the script's function of the same name
//! through `Host.current()`. What crosses is plain tables, with byte positions counted from the
//! frontend's `counts_from`:
//! - a value is `{ kind = "string", value = "text" }`, its kind one of `kosm.Value`'s tags. A
//!   boolean, float or color also has `text`, spelled in the file's format; a color's `value` is
//!   a `kosm.Color`. A table's `value` is a list of `{ key = "name", value = <value> }` in order,
//!   a list's and a joined value's a list of values.
//! - a node is `kosm.Adapter.Node`'s fields, its range a list of its first and last position:
//!   `{ key = "size", kind = "scalar", position = 1, value = { 8, 9 } }`.
//! - an insertion is `{ range = { 8, 7 }, content = "text" }`.
//! A script fails a capability by raising an error, whose message kosm reports with the file.

const ScriptAdapter = @This();

const std = @import("std");
const Adapter = @import("../Adapter.zig");
const Loose = @import("../Loose.zig");
const Value = @import("../value.zig").Value;
const Color = @import("../Color.zig");
const Host = @import("Host.zig");
const Call = @import("Call.zig");
const ScriptFile = @import("ScriptFile.zig");

/// The frontend reading the script, by `Frontend.name`: "lua".
frontend: []const u8,
/// The script, relative to the config: "adapters/keys/root.lua".
path: []const u8,
/// The frontend's `counts_from`: where the script counts byte positions from.
counts_from: u1 = 0,

/// How deep nodes and values may nest; deeper is taken for a table holding itself.
const max_depth = 256;

const no_host = "an adapter written through a frontend runs only in the runner of scripts, and this runner is none";

/// The script, as the host runs it.
pub fn file(adapter: ScriptAdapter) ScriptFile {
    return .{ .frontend = adapter.frontend, .path = adapter.path };
}

/// The capabilities of `adapter` as `kosm.Adapter` takes them; the generated module sets those
/// its script gives.
pub fn Capabilities(comptime adapter: ScriptAdapter) type {
    return struct {
        pub fn format(writer: *std.Io.Writer, value: Value, context: *Adapter.Context) Adapter.Error!void {
            return adapter.formatValue(writer, value, context);
        }

        pub fn parser(allocator: std.mem.Allocator, source: []const u8, context: *Adapter.Context) Adapter.ParseError!Adapter.Node {
            return adapter.parse(allocator, source, context);
        }

        pub fn serialize(writer: *std.Io.Writer, root: Value, context: *Adapter.Context) Adapter.Error!void {
            return adapter.serializeValue(writer, root, context);
        }

        pub fn insert(allocator: std.mem.Allocator, source: []const u8, parent: *const Adapter.Node, key: ?[]const u8, value: []const u8, context: *Adapter.Context) Adapter.InsertError![]const Adapter.Insertion {
            return adapter.insertEntry(allocator, source, parent, key, value, context);
        }
    };
}

/// Runs the script's `format(value)`, which returns the value's source text.
pub fn formatValue(adapter: ScriptAdapter, writer: *std.Io.Writer, value: Value, context: *Adapter.Context) Adapter.Error!void {
    try writer.writeAll(try adapter.textOf("format", value, context));
}

/// Runs the script's `serialize(root)`, which returns the whole file.
pub fn serializeValue(adapter: ScriptAdapter, writer: *std.Io.Writer, root: Value, context: *Adapter.Context) Adapter.Error!void {
    try writer.writeAll(try adapter.textOf("serialize", root, context));
}

/// Runs the script's `parser(source)`, which returns the root node.
pub fn parse(adapter: ScriptAdapter, allocator: std.mem.Allocator, source: []const u8, context: *Adapter.Context) Adapter.ParseError!Adapter.Node {
    const host = Host.current() orelse return context.invalidSyntax("{s}: {s}", .{ adapter.path, no_host });
    var call = host.call();
    const failed = failed: {
        const given = host.run(host.state, &call, adapter.file(), "parser", &.{.{ .value = .{ .string = source } }}) catch |err| break :failed err;
        var reader: NodeReader = .{ .call = &call, .allocator = allocator, .adapter = adapter, .function = "parser", .length = source.len };
        return reader.node(given, "the root", 0) catch |err| break :failed err;
    };
    return switch (failed) {
        error.OutOfMemory => error.OutOfMemory,
        error.CallFailed => context.invalidSyntax("{s}", .{call.message orelse "parser failed and did not say why"}),
    };
}

/// Runs the script's `insert(source, parent, key, value)`, which returns the insertions; `key`
/// is nil for a list element.
pub fn insertEntry(adapter: ScriptAdapter, allocator: std.mem.Allocator, source: []const u8, parent: *const Adapter.Node, key: ?[]const u8, value: []const u8, context: *Adapter.Context) Adapter.InsertError![]const Adapter.Insertion {
    const host = Host.current() orelse return context.unsupported("{s}: {s}", .{ adapter.path, no_host });
    var call = host.call();
    const failed = failed: {
        const parent_loose = adapter.looseNode(host.arena, parent.*) catch |err| break :failed err;
        const key_loose: Loose = if (key) |given| .{ .value = .{ .string = given } } else .{ .value = .null };
        const given = host.run(host.state, &call, adapter.file(), "insert", &.{ .{ .value = .{ .string = source } }, parent_loose, key_loose, .{ .value = .{ .string = value } } }) catch |err| break :failed err;
        return adapter.insertions(&call, allocator, given, source.len) catch |err| break :failed err;
    };
    return switch (failed) {
        error.OutOfMemory => error.OutOfMemory,
        error.CallFailed => context.unsupported("{s}", .{call.message orelse "insert failed and did not say why"}),
    };
}

/// What the script's `function` returns for `value`, which must be text.
fn textOf(adapter: ScriptAdapter, comptime function: []const u8, value: Value, context: *Adapter.Context) error{UnsupportedValue}![]const u8 {
    const host = Host.current() orelse return context.unsupported("{s}: {s}", .{ adapter.path, no_host });
    var call = host.call();
    const failed = failed: {
        const argument = adapter.looseValue(host, &call, value, context, 0) catch |err| break :failed err;
        const given = host.run(host.state, &call, adapter.file(), function, &.{argument}) catch |err| break :failed err;
        if (given.value == .string) return given.value.string;
        break :failed call.fail("{s}: " ++ function ++ " returned {s}; it returns the text to write", .{ adapter.path, describe(given) });
    };
    return switch (failed) {
        error.OutOfMemory => context.unsupported("{s}: out of memory", .{adapter.path}),
        error.CallFailed => context.unsupported("{s}", .{call.message orelse function ++ " failed and did not say why"}),
    };
}

/// `value` as the script gets it.
fn looseValue(adapter: ScriptAdapter, host: *const Host, call: *Call, value: Value, context: *Adapter.Context, depth: usize) Call.Error!Loose {
    if (depth > max_depth) return call.fail("{s}: the value nests more than {d} deep", .{ adapter.path, max_depth });
    const arena = host.arena;
    const given: Loose = switch (value) {
        .string, .raw => |text| .{ .value = .{ .string = text } },
        .integer => |integer| .{ .value = .{ .integer = integer } },
        .float => |float| .{ .value = .{ .float = float } },
        .boolean => |boolean| .{ .value = .{ .boolean = boolean } },
        .color => |color| color: {
            const kept = try arena.create(Color);
            kept.* = color;
            const handle = host.handleOf(Color, kept) orelse return call.fail("{s}: a kosm.Color cannot be handed to a script here", .{adapter.path});
            break :color .{ .value = .{ .handle = handle } };
        },
        .table => |entries| table: {
            const items = try arena.alloc(Loose, entries.len);
            for (entries, items) |entry, *item| item.* = try table(arena, &.{
                .{ .key = "key", .value = .{ .value = .{ .string = entry.key } } },
                .{ .key = "value", .value = try adapter.looseValue(host, call, entry.value, context, depth + 1) },
            });
            break :table .{ .value = .{ .list = items } };
        },
        .list, .joined => |values| list: {
            const items = try arena.alloc(Loose, values.len);
            for (values, items) |item_value, *item| item.* = try adapter.looseValue(host, call, item_value, context, depth + 1);
            break :list .{ .value = .{ .list = items } };
        },
    };
    var spelled: std.Io.Writer.Allocating = .init(arena);
    const has_text = switch (value) {
        .boolean => |boolean| written: {
            context.writeBoolean(&spelled.writer, boolean) catch return error.OutOfMemory;
            break :written true;
        },
        .float => |float| written: {
            context.writeFloat(&spelled.writer, float) catch return error.OutOfMemory;
            break :written true;
        },
        .color => |color| written: {
            context.writeColor(&spelled.writer, color) catch return error.OutOfMemory;
            break :written true;
        },
        else => false,
    };
    const kind: Loose.Entry = .{ .key = "kind", .value = .{ .value = .{ .string = @tagName(value) } } };
    const held: Loose.Entry = .{ .key = "value", .value = given };
    if (has_text) return table(arena, &.{ kind, .{ .key = "text", .value = .{ .value = .{ .string = spelled.written() } } }, held });
    return table(arena, &.{ kind, held });
}

/// A loose table of `entries`, copied into `arena`.
fn table(arena: std.mem.Allocator, entries: []const Loose.Entry) std.mem.Allocator.Error!Loose {
    return .{ .value = .{ .table = try arena.dupe(Loose.Entry, entries) } };
}

/// `node` as the script gets it, its positions counted from `counts_from`.
fn looseNode(adapter: ScriptAdapter, arena: std.mem.Allocator, node: Adapter.Node) std.mem.Allocator.Error!Loose {
    var entries: std.ArrayList(Loose.Entry) = .empty;
    if (node.key) |key| try entries.append(arena, .{ .key = "key", .value = .{ .value = .{ .string = key } } });
    try entries.append(arena, .{ .key = "kind", .value = .{ .value = .{ .string = @tagName(node.kind) } } });
    try entries.append(arena, .{ .key = "position", .value = .{ .value = .{ .integer = adapter.positionOf(node.position) } } });
    if (node.value) |range| try entries.append(arena, .{ .key = "value", .value = try adapter.looseRange(arena, range) });
    const children = try arena.alloc(Loose, node.children.len);
    for (node.children, children) |child, *loose| loose.* = try adapter.looseNode(arena, child);
    try entries.append(arena, .{ .key = "children", .value = .{ .value = .{ .list = children } } });
    return .{ .value = .{ .table = entries.items } };
}

fn looseRange(adapter: ScriptAdapter, arena: std.mem.Allocator, range: Adapter.Range) std.mem.Allocator.Error!Loose {
    // Counting from 1, a range ends on its last byte, which is where it ends counting from 0.
    const ends = try arena.dupe(Loose, &.{ .{ .value = .{ .integer = adapter.positionOf(range.start) } }, .{ .value = .{ .integer = @intCast(range.end) } } });
    return .{ .value = .{ .list = ends } };
}

fn positionOf(adapter: ScriptAdapter, offset: usize) i64 {
    return @as(i64, @intCast(offset)) + adapter.counts_from;
}

/// The insertions the script's `insert` returned.
fn insertions(adapter: ScriptAdapter, call: *Call, allocator: std.mem.Allocator, given: Loose, length: usize) Call.Error![]const Adapter.Insertion {
    const items = listOf(given) orelse return call.fail("{s}: insert returned {s}; it returns a list of {{ range = {{ first, last }}, content = \"text\" }}", .{ adapter.path, describe(given) });
    const found = try allocator.alloc(Adapter.Insertion, items.len);
    var reader: NodeReader = .{ .call = call, .allocator = allocator, .adapter = adapter, .function = "insert", .length = length };
    for (items, found, 1..) |item, *insertion, number| {
        const where = try call.arena.print("insertion {d}", .{number});
        const entries = try reader.fields(item, where, &.{ "range", "content" });
        const range = try reader.range(fieldOf(entries, "range") orelse return reader.fail(where, "it has no range", .{}), try call.arena.print("{s}.range", .{where}));
        const content = fieldOf(entries, "content") orelse return reader.fail(where, "it has no content", .{});
        if (content.value != .string) return reader.fail(where, "content is {s}, not text", .{describe(content)});
        insertion.* = .{ .start = range.start, .end = range.end, .content = try allocator.dupe(u8, content.value.string) };
    }
    return found;
}

/// Reads the nodes a script returns, checking every field and range.
const NodeReader = struct {
    call: *Call,
    allocator: std.mem.Allocator,
    adapter: ScriptAdapter,
    /// The capability whose result this is, for messages.
    function: []const u8,
    /// How many bytes the file holds, which no range may pass.
    length: usize,

    fn node(reader: *NodeReader, given: Loose, where: []const u8, depth: usize) Call.Error!Adapter.Node {
        if (depth > max_depth) return reader.fail(where, "nodes nest more than {d} deep; does a node hold itself?", .{max_depth});
        const entries = try reader.fields(given, where, &.{ "key", "kind", "position", "value", "children" });
        const arena = reader.call.arena;
        const kind_loose = fieldOf(entries, "kind") orelse return reader.fail(where, "it has no kind; a node's kind is \"table\", \"list\" or \"scalar\"", .{});
        const kind: ?Adapter.Node.Kind = if (kind_loose.value == .string) std.meta.stringToEnum(Adapter.Node.Kind, kind_loose.value.string) else null;
        const position_loose = fieldOf(entries, "position") orelse return reader.fail(where, "it has no position", .{});
        const key: ?[]const u8 = if (fieldOf(entries, "key")) |key_loose| switch (key_loose.value) {
            .string => |text| try reader.allocator.dupe(u8, text),
            .null => null,
            else => return reader.fail(where, "key is {s}, not text", .{describe(key_loose)}),
        } else null;
        const value: ?Adapter.Range = if (fieldOf(entries, "value")) |range_loose| switch (range_loose.value) {
            .null => null,
            else => try reader.range(range_loose, try arena.print("{s}.value", .{where})),
        } else null;
        const children_loose = fieldOf(entries, "children") orelse Loose{ .value = .{ .list = &.{} } };
        const children_items = listOf(children_loose) orelse return reader.fail(where, "children is {s}, not a list of nodes", .{describe(children_loose)});
        const children = try reader.allocator.alloc(Adapter.Node, children_items.len);
        for (children_items, children, 1..) |child, *built, number| {
            built.* = try reader.node(child, try arena.print("{s}.children[{d}]", .{ where, number }), depth + 1);
        }
        return .{
            .key = key,
            .kind = kind orelse return reader.fail(where, "kind is {s}; a node's kind is \"table\", \"list\" or \"scalar\"", .{describe(kind_loose)}),
            .position = try reader.position(position_loose, where, "position"),
            .value = value,
            .children = children,
        };
    }

    /// The entries of the table `given`, which may hold only the fields `allowed`.
    fn fields(reader: *NodeReader, given: Loose, where: []const u8, comptime allowed: []const []const u8) Call.Error![]const Loose.Entry {
        const entries: []const Loose.Entry = switch (given.value) {
            .table => |entries| entries,
            // An empty table reads as an empty list.
            .list => |items| if (items.len == 0) &.{} else return reader.fail(where, "it is a list, not a table of {s}", .{comptime names(allowed)}),
            else => return reader.fail(where, "it is {s}, not a table of {s}", .{ describe(given), comptime names(allowed) }),
        };
        for (entries) |entry| {
            for (allowed) |name| {
                if (std.mem.eql(u8, entry.key, name)) break;
            } else return reader.fail(where, "it sets '{s}'; it holds {s}", .{ entry.key, comptime names(allowed) });
        }
        return entries;
    }

    /// A range given as its first and last position.
    fn range(reader: *NodeReader, given: Loose, where: []const u8) Call.Error!Adapter.Range {
        const ends = listOf(given) orelse return reader.fail(where, "it is {s}, not {{ first, last }}", .{describe(given)});
        if (ends.len != 2) return reader.fail(where, "it holds {d} items, not {{ first, last }}", .{ends.len});
        const start = try reader.position(ends[0], where, "first");
        if (ends[1].value != .integer) return reader.fail(where, "last is {s}, not a whole number", .{describe(ends[1])});
        const last = ends[1].value.integer;
        // Counting from 1, the last byte's position is where the range ends counting from 0.
        if (last < start or last > reader.length) return reader.fail(where, "{{ {d}, {d} }} is no range of the file's {d} bytes; it {s}", .{ ends[0].value.integer, last, reader.length, reader.rule() });
        return .{ .start = start, .end = @intCast(last) };
    }

    /// A position, as an offset from the file's start.
    fn position(reader: *NodeReader, given: Loose, where: []const u8, comptime name: []const u8) Call.Error!usize {
        if (given.value != .integer) return reader.fail(where, name ++ " is {s}, not a whole number", .{describe(given)});
        const offset = given.value.integer - reader.adapter.counts_from;
        if (offset < 0 or offset > reader.length) return reader.fail(where, name ++ " {d} lies outside the file's {d} bytes; positions count from {d}", .{ given.value.integer, reader.length, reader.adapter.counts_from });
        return @intCast(offset);
    }

    fn rule(reader: *const NodeReader) []const u8 {
        return if (reader.adapter.counts_from == 1) "counts from 1 and ends on its last byte, or one before its first when empty" else "counts from 0 and ends one past its last byte";
    }

    fn fail(reader: *NodeReader, where: []const u8, comptime format: []const u8, arguments: anytype) Call.Error {
        const message = try reader.call.arena.print(format, arguments);
        return reader.call.fail("{s}: {s} returned a node kosm cannot read: {s}: {s}", .{ reader.adapter.path, reader.function, where, message });
    }
};

/// `allowed` as messages list them: "key, kind and position".
fn names(comptime allowed: []const []const u8) []const u8 {
    comptime var text: []const u8 = "";
    inline for (allowed, 0..) |name, index| {
        text = text ++ (if (index == 0) "" else if (index == allowed.len - 1) " and " else ", ") ++ name;
    }
    return text;
}

fn fieldOf(entries: []const Loose.Entry, name: []const u8) ?Loose {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, name)) return entry.value;
    }
    return null;
}

/// The items of a list, an empty table counting as an empty list.
fn listOf(given: Loose) ?[]const Loose {
    return switch (given.value) {
        .list => |items| items,
        .table => |entries| if (entries.len == 0) &.{} else null,
        else => null,
    };
}

fn describe(given: Loose) []const u8 {
    return switch (given.value) {
        .table => "a table",
        .list => "a list",
        .string, .text => "text",
        .integer => "a whole number",
        .float => "a float",
        .boolean => "a boolean",
        .null => "nothing",
        .handle => "a Zig value",
    };
}

const testing = std.testing;
const Handle = @import("Handle.zig");
const Format = @import("../Format.zig");

/// Stands in for a script giving every capability, counting from 1 as Lua does.
const TestHost = struct {
    const Field = struct { []const u8, Loose.Kind };

    fn run(state: *anyopaque, call: *Call, script: ScriptFile, function: []const u8, arguments: []const Loose) Call.Error!Loose {
        _ = state;
        _ = script;
        if (std.mem.eql(u8, function, "format")) return formatted(call, arguments[0].value.table);
        if (std.mem.eql(u8, function, "serialize")) {
            // `{ kind = "table", value = { { key = "a", value = { kind = "list", value = { ... } } } } }`
            const entry = fieldOf(arguments[0].value.table, "value").?.value.list[0].value.table;
            const items = fieldOf(fieldOf(entry, "value").?.value.table, "value").?.value.list;
            return .{ .value = .{ .string = try call.arena.print("{s}={d}", .{ fieldOf(entry, "key").?.value.string, items.len }) } };
        }
        if (std.mem.eql(u8, function, "parser")) return parsed(call, arguments[0].value.string);
        // insert: adds `key = value` right after the parent's first child, found from its node.
        const parent = arguments[1].value.table;
        const child = fieldOf(parent, "children").?.value.list[0].value.table;
        const last = fieldOf(child, "value").?.value.list[1].value.integer;
        const content = try call.arena.print("\n{s} = {s}", .{ arguments[2].value.string, arguments[3].value.string });
        const insertion = try node(call, &.{ .{ "range", try ends(call, last + 1, last) }, .{ "content", .{ .string = content } } });
        return .{ .value = .{ .list = try call.arena.dupe(Loose, &.{insertion}) } };
    }

    fn formatted(call: *Call, entries: []const Loose.Entry) Call.Error!Loose {
        const kind = fieldOf(entries, "kind").?.value.string;
        if (std.mem.eql(u8, kind, "string")) return call.fail("adapters/keys.lua:4: strings are not written", .{});
        if (std.mem.eql(u8, kind, "integer")) return .{ .value = .null };
        if (std.mem.eql(u8, kind, "color") and fieldOf(entries, "value").?.value.handle.as(Color) == null) return call.fail("not a color", .{});
        return .{ .value = .{ .string = fieldOf(entries, "text").?.value.string } };
    }

    fn parsed(call: *Call, source: []const u8) Call.Error!Loose {
        if (std.mem.eql(u8, source, "past")) return node(call, &.{ .{ "kind", .{ .string = "scalar" } }, .{ "position", .{ .integer = 1 } }, .{ "value", try ends(call, 2, 9) } });
        if (std.mem.eql(u8, source, "odd")) return node(call, &.{ .{ "kind", .{ .string = "tree" } }, .{ "position", .{ .integer = 1 } } });
        if (std.mem.eql(u8, source, "extra")) return node(call, &.{ .{ "kind", .{ .string = "table" } }, .{ "position", .{ .integer = 1 } }, .{ "size", .{ .integer = 2 } } });
        if (std.mem.eql(u8, source, "zero")) return node(call, &.{ .{ "kind", .{ .string = "table" } }, .{ "position", .{ .integer = 0 } } });
        // `size = 12`: the root table, holding `size`, its value at 8..9.
        const size = try node(call, &.{ .{ "key", .{ .string = "size" } }, .{ "kind", .{ .string = "scalar" } }, .{ "position", .{ .integer = 1 } }, .{ "value", try ends(call, 8, 9) } });
        return node(call, &.{ .{ "kind", .{ .string = "table" } }, .{ "position", .{ .integer = 1 } }, .{ "children", .{ .list = try call.arena.dupe(Loose, &.{size}) } } });
    }

    fn node(call: *Call, fields: []const Field) Call.Error!Loose {
        const entries = try call.arena.alloc(Loose.Entry, fields.len);
        for (fields, entries) |field, *entry| entry.* = .{ .key = field[0], .value = .{ .value = field[1] } };
        return .{ .value = .{ .table = entries } };
    }

    fn ends(call: *Call, first: i64, last: i64) Call.Error!Loose.Kind {
        return .{ .list = try call.arena.dupe(Loose, &.{ .{ .value = .{ .integer = first } }, .{ .value = .{ .integer = last } } }) };
    }

    fn handle(state: *anyopaque, id: *const anyopaque, pointer: *anyopaque) ?Handle {
        _ = state;
        if (id != Handle.id(Color)) return null;
        return .{ .pointer = pointer, .type = &color_type };
    }

    /// Good only for telling the handle's type; nothing reads through it.
    const color_type: Handle.Type = .{ .id = Handle.id(Color), .name = "kosm.Color", .get = undefined, .set = undefined, .length = undefined };
};

const test_adapter: ScriptAdapter = .{ .frontend = "test", .path = "adapters/keys.lua", .counts_from = 1 };

fn testContext() Adapter.Context {
    const format: Format = .{ .boolean = .yes_no, .float_precision = 2 };
    return .{ .format = format.resolve() };
}

fn withTestHost(arena: std.mem.Allocator) Host {
    return .{ .state = undefined, .arena = arena, .run = TestHost.run, .handle = TestHost.handle };
}

test "format hands the script a tagged value with the file's spelling, and fails with its message" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    var written: std.Io.Writer.Allocating = .init(arena.allocator());
    var context = testContext();
    try test_adapter.formatValue(&written.writer, .{ .boolean = true }, &context);
    try test_adapter.formatValue(&written.writer, .{ .float = 0.125 }, &context);
    try test_adapter.formatValue(&written.writer, .{ .color = @import("../root.zig").hex("ff0000") }, &context);
    try testing.expectEqualStrings("yes0.13#ff0000", written.written());
    try testing.expectError(error.UnsupportedValue, test_adapter.formatValue(&written.writer, .{ .string = "x" }, &context));
    try testing.expectEqualStrings("adapters/keys.lua:4: strings are not written", context.message());
    try testing.expectError(error.UnsupportedValue, test_adapter.formatValue(&written.writer, .{ .integer = 1 }, &context));
    try testing.expectEqualStrings("adapters/keys.lua: format returned nothing; it returns the text to write", context.message());
}

test "serialize hands a table's entries over in order, each a key and a tagged value" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    var written: std.Io.Writer.Allocating = .init(arena.allocator());
    var context = testContext();
    const root: Value = .{ .table = &.{.{ .key = "a", .value = .{ .list = &.{ .{ .integer = 1 }, .{ .raw = "x" } } } }} };
    try test_adapter.serializeValue(&written.writer, root, &context);
    try testing.expectEqualStrings("a=2", written.written());
}

test "parser's nodes count from the frontend's first position, and each field and range is checked" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    var context = testContext();
    const root = try test_adapter.parse(arena.allocator(), "size = 12", &context);
    try testing.expectEqual(.table, root.kind);
    try testing.expectEqual(null, root.value);
    const size = root.children[0];
    try testing.expectEqualStrings("size", size.key.?);
    try testing.expectEqual(0, size.position);
    try testing.expectEqualStrings("12", "size = 12"[size.value.?.start..size.value.?.end]);

    const Case = struct { source: []const u8, message: []const u8 };
    const cases = [_]Case{
        .{ .source = "past", .message = "adapters/keys.lua: parser returned a node kosm cannot read: the root.value: { 2, 9 } is no range of the file's 4 bytes; it counts from 1 and ends on its last byte, or one before its first when empty" },
        .{ .source = "odd", .message = "adapters/keys.lua: parser returned a node kosm cannot read: the root: kind is text; a node's kind is \"table\", \"list\" or \"scalar\"" },
        .{ .source = "extra", .message = "adapters/keys.lua: parser returned a node kosm cannot read: the root: it sets 'size'; it holds key, kind, position, value and children" },
        .{ .source = "zero", .message = "adapters/keys.lua: parser returned a node kosm cannot read: the root: position 0 lies outside the file's 4 bytes; positions count from 1" },
    };
    for (cases) |case| {
        try testing.expectError(error.InvalidSyntax, test_adapter.parse(arena.allocator(), case.source, &context));
        try testing.expectEqualStrings(case.message, context.message());
    }
}

test "insert gets the parent node back as parser gave it, and its insertions count the same way" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const host = withTestHost(arena.allocator());
    Host.install(&host);
    defer Host.install(null);
    var context = testContext();
    const source = "size = 12";
    const root = try test_adapter.parse(arena.allocator(), source, &context);
    const changes = try test_adapter.insertEntry(arena.allocator(), source, &root, "gap", "4", &context);
    try testing.expectEqual(1, changes.len);
    try testing.expectEqual(source.len, changes[0].start);
    try testing.expectEqual(source.len, changes[0].end);
    try testing.expectEqualStrings("\ngap = 4", changes[0].content);
}

test "without a host every capability fails naming the script" {
    Host.install(null);
    var context = testContext();
    try testing.expectError(error.InvalidSyntax, test_adapter.parse(testing.allocator, "", &context));
    try testing.expectEqualStrings("adapters/keys.lua: " ++ no_host, context.message());
}
