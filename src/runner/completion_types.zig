//! Describes every type a script may set as a `kosm.Frontend.Completion`: reflection gives the
//! fields and their types, the sources give their doc comments and declared names.

const std = @import("std");
const kosm = @import("kosm");
const Sources = @import("Sources.zig");
const bindings = @import("bindings.zig");

const Completion = kosm.Frontend.Completion;
pub const Error = std.mem.Allocator.Error;

/// A Zig kosmos to describe.
pub const Kosmos = struct {
    /// As `kosm apply` spells it: "personal", "frost.iced".
    name: []const u8,
    /// The module declaring it and the path of names to its function there
    /// (`&.{ "group", "iced" }`).
    module: []const u8,
    path: []const []const u8,
    function: type,
};

fn declares(methods: []const Completion.Function, name: []const u8) bool {
    for (methods) |method| {
        if (std.mem.eql(u8, method.name, name)) return true;
    }
    return false;
}

/// Builds the records of every type below the given ones, each once.
pub const Builder = struct {
    arena: std.mem.Allocator,
    sources: *Sources,
    records: std.ArrayList(Completion.Record) = .empty,
    /// The record each struct type was described as, by `typeId`.
    described: std.AutoHashMapUnmanaged(usize, []const u8) = .empty,
    /// Every record name given so far.
    taken: std.StringHashMapUnmanaged(void) = .empty,

    /// The record of `T`, a struct; `container` is its source when known, and names it, otherwise
    /// `hint` does.
    pub fn record(builder: *Builder, comptime T: type, hint: []const u8, container: ?*const Sources.Container) Error![]const u8 {
        if (builder.described.get(typeId(T))) |name| return name;
        const name = try builder.unique(if (container) |known| known.name else hint);
        try builder.described.put(builder.arena, typeId(T), name);
        const index = builder.records.items.len;
        try builder.records.append(builder.arena, .{
            .name = name,
            .doc = if (container) |known| try builder.sources.containerDoc(known) else null,
            .fields = &.{},
            .methods = if (bindings.isService(T)) &.{} else try builder.copyMethod(name),
        });
        // Fields are described after the record is known, so a type holding itself ends.
        const fields = try builder.fieldsOf(T, name, container);
        builder.records.items[index].fields = fields;
        return name;
    }

    /// The record of `Tree`, a struct with a field per app, the app of each field exported as
    /// `App` by the module of the same index in `modules`.
    pub fn appsRecord(builder: *Builder, comptime Tree: type, comptime modules: []const []const u8, name: []const u8) Error![]const u8 {
        const info = @typeInfo(Tree).@"struct";
        var fields: std.ArrayList(Completion.Field) = .empty;
        inline for (info.field_names, info.field_types, modules) |field_name, Field, module| {
            const declared = try builder.sources.declarationPath(module, &.{"App"});
            const hint = module ++ ".App";
            const expression = if (declared) |found| found.value else null;
            if (try builder.typeOf(Field, hint, expression, 0)) |field_type| {
                try fields.append(builder.arena, .{ .name = field_name, .doc = if (declared) |found| found.doc else null, .type = field_type });
            }
        }
        const unique_name = try builder.unique(name);
        try builder.records.append(builder.arena, .{ .name = unique_name, .fields = fields.items, .methods = try builder.copyMethod(unique_name) });
        return unique_name;
    }

    /// The record of a type declared at `path` in `module` (`kosm`, `&.{ "Theme", "Input" }`).
    pub fn declaredRecord(builder: *Builder, comptime T: type, module: []const u8, comptime path: []const []const u8) Error![]const u8 {
        const declared = try builder.sources.declarationPath(module, path);
        const hint = try std.mem.join(builder.arena, ".", &.{ module, try std.mem.join(builder.arena, ".", path) });
        const container = if (declared) |found| if (found.value) |value| try builder.sources.resolve(value, found.name, 0) else null else null;
        return builder.record(T, hint, container);
    }

    /// Describes `kosmos`: its doc, and the records of its parameters and tree.
    pub fn kosmos(builder: *Builder, comptime described: Kosmos) Error!Completion.Kosmos {
        const function = @typeInfo(described.function).@"fn";
        const declared = try builder.sources.declarationPath(described.module, described.path);
        const prototype = if (declared) |found| found.function else null;
        const base_hint = try builder.arena.print("{s}.{s}", .{ described.module, try std.mem.join(builder.arena, ".", described.path) });
        var params: ?[]const u8 = null;
        if (function.param_types.len == 1) {
            const Params = function.param_types[0].?;
            const expression = if (prototype) |found| found.parameter else null;
            const hint = try builder.arena.print("{s}.Params", .{base_hint});
            params = try builder.record(Params, hint, if (expression) |known| try builder.sources.resolve(known, hint, 0) else null);
        }
        const Tree = Payload(function.return_type.?);
        const tree_expression = if (prototype) |found| found.return_type else null;
        const tree_hint = try builder.arena.print("{s}.Tree", .{base_hint});
        const tree = try builder.record(Tree, tree_hint, if (tree_expression) |known| try builder.sources.resolve(known, tree_hint, 0) else null);
        return .{ .name = described.name, .doc = if (declared) |found| found.doc else null, .params = params, .tree = tree };
    }

    fn fieldsOf(builder: *Builder, comptime T: type, name: []const u8, container: ?*const Sources.Container) Error![]const Completion.Field {
        @setEvalBranchQuota(100_000);
        var fields: std.ArrayList(Completion.Field) = .empty;
        const info = @typeInfo(T).@"struct";
        inline for (info.field_names, info.field_types, info.field_attrs) |field_name, Field, attributes| {
            if (attributes.@"comptime") continue;
            const source = if (container) |known| try builder.sources.field(known, field_name) else null;
            const hint = try builder.arena.print("{s}.{s}", .{ name, field_name });
            const expression = if (source) |found| found.type else null;
            if (try builder.typeOf(Field, hint, expression, 0)) |field_type| {
                try fields.append(builder.arena, .{ .name = field_name, .doc = if (source) |found| found.doc else null, .type = field_type });
            }
        }
        return fields.items;
    }

    /// Describes `F`, a function a script calls, declared at `declared` when its source is
    /// known; `hint` names the records of types written inline in it.
    pub fn describeFunction(builder: *Builder, comptime F: type, name: []const u8, hint: []const u8, declared: ?Sources.Declaration) Error!Completion.Function {
        const info = @typeInfo(F).@"fn";
        const prototype = if (declared) |found| found.function else null;
        var parameters: std.ArrayList(Completion.Field) = .empty;
        inline for (info.param_types, 0..) |maybe, index| {
            const Parameter = maybe.?;
            const source: ?Sources.Parameter = if (prototype) |known| if (index < known.parameters.len) known.parameters[index] else null else null;
            const parameter_name = if (source) |known| known.name orelse try builder.arena.print("argument{d}", .{index + 1}) else try builder.arena.print("argument{d}", .{index + 1});
            const parameter_info = @typeInfo(Parameter);
            const Described = if (parameter_info == .pointer and parameter_info.pointer.size == .one) parameter_info.pointer.child else Parameter;
            const expression = if (Described == Parameter) if (source) |known| known.type else null else null;
            const parameter_type = try builder.typeOf(Described, try builder.arena.print("{s}.{s}", .{ hint, parameter_name }), expression, 0);
            try parameters.append(builder.arena, .{ .name = parameter_name, .type = parameter_type });
        }
        const Result = Payload(info.return_type.?);
        const result = if (Result == void) null else try builder.typeOf(Result, try builder.arena.print("{s}.result", .{hint}), if (prototype) |known| known.return_type else null, 0);
        return .{ .name = name, .doc = if (declared) |found| found.doc else null, .parameters = parameters.items, .result = result };
    }

    /// Gives the record named `name` `methods` too, after the `copy` it may have; one of them
    /// named `copy` replaces that one, as a type's own `copy` does.
    pub fn addMethods(builder: *Builder, name: []const u8, methods: []const Completion.Function) Error!void {
        for (builder.records.items) |*described| {
            if (!std.mem.eql(u8, described.name, name)) continue;
            var combined: std.ArrayList(Completion.Function) = .empty;
            for (described.methods) |method| {
                if (!std.mem.eql(u8, method.name, bindings.copy_name) or !declares(methods, bindings.copy_name)) try combined.append(builder.arena, method);
            }
            try combined.appendSlice(builder.arena, methods);
            described.methods = combined.items;
        }
    }

    /// `value:copy()`, as the record named `name` gives it.
    fn copyMethod(builder: *Builder, name: []const u8) Error![]const Completion.Function {
        const parameters = try builder.arena.dupe(Completion.Field, &.{.{ .name = "self", .type = .{ .record = name } }});
        return builder.arena.dupe(Completion.Function, &.{.{
            .name = bindings.copy_name,
            .doc = "A copy of this value, which can be changed without changing the original.",
            .parameters = parameters,
            .result = .{ .record = name },
        }});
    }

    /// What a field of type `T` takes; null for a type a script cannot set, which is left out.
    pub fn typeOf(builder: *Builder, comptime T: type, hint: []const u8, expression: ?Sources.Expression, depth: usize) Error!?Completion.Type {
        // Unions are described inline, so a union holding itself is cut off here.
        if (depth > max_depth) return null;
        if (T == kosm.Color) return .color;
        if (T == kosm.ColorChoice) return .color_or_hue;
        if (T == kosm.Image or T == kosm.File) return .path;
        if (comptime kosm.isKosmos(T)) return .text;
        if (T == kosm.Value) return .value;
        if (T == []const u8) return .text;
        switch (@typeInfo(T)) {
            .bool => return .boolean,
            .int => return .integer,
            .float => return .number,
            .@"enum" => |info| return .{ .choice = info.field_names },
            .optional => |optional| {
                const child = try builder.typeOf(optional.child, hint, expression, depth + 1) orelse return null;
                return .{ .optional = try builder.create(child) };
            },
            .array => |array| {
                const child = try builder.typeOf(array.child, hint, expression, depth + 1) orelse return null;
                return .{ .list = try builder.create(child) };
            },
            .pointer => |pointer| {
                if (pointer.size != .slice or pointer.sentinel_ptr != null) return null;
                const child = try builder.typeOf(pointer.child, hint, expression, depth + 1) orelse return null;
                return .{ .list = try builder.create(child) };
            },
            .@"struct" => |info| {
                if (info.is_tuple) return null;
                return .{ .record = try builder.record(T, hint, try builder.resolve(expression, hint)) };
            },
            .@"union" => |info| {
                if (info.tag_type == null) return null;
                const container = try builder.resolve(expression, hint);
                var tags: std.ArrayList(Completion.Field) = .empty;
                inline for (info.field_names, info.field_types) |tag, Payload_| {
                    const source = if (container) |known| try builder.sources.field(known, tag) else null;
                    const doc = if (source) |found| found.doc else null;
                    if (Payload_ == void) {
                        try tags.append(builder.arena, .{ .name = tag, .doc = doc, .type = null });
                    } else {
                        const tag_hint = try builder.arena.print("{s}.{s}", .{ if (container) |known| known.name else hint, tag });
                        if (try builder.typeOf(Payload_, tag_hint, if (source) |found| found.type else null, depth + 1)) |payload| {
                            try tags.append(builder.arena, .{ .name = tag, .doc = doc, .type = payload });
                        }
                    }
                }
                return .{ .variant = tags.items };
            },
            else => return null,
        }
    }

    fn resolve(builder: *Builder, expression: ?Sources.Expression, hint: []const u8) Error!?*const Sources.Container {
        const known = expression orelse return null;
        return builder.sources.resolve(known, hint, 0);
    }

    fn create(builder: *Builder, value: Completion.Type) Error!*const Completion.Type {
        const created = try builder.arena.create(Completion.Type);
        created.* = value;
        return created;
    }

    /// `name`, or `name_2`, `name_3`... when another type already has it.
    fn unique(builder: *Builder, name: []const u8) Error![]const u8 {
        var candidate = name;
        var number: usize = 2;
        while (builder.taken.contains(candidate)) : (number += 1) candidate = try builder.arena.print("{s}_{d}", .{ name, number });
        try builder.taken.put(builder.arena, candidate, {});
        return candidate;
    }
};

/// How deeply unions and lists may nest inside one field before the rest is left out.
const max_depth = 16;

/// A number unique to `T` for the whole run.
fn typeId(comptime T: type) usize {
    const Marker = struct {
        const Of = T;
        var byte: u8 = 0;
    };
    return @intFromPtr(&Marker.byte);
}

fn Payload(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .error_union => |error_union| error_union.payload,
        else => T,
    };
}

const testing = std.testing;

const test_root =
    \\const kosm = @import("kosm");
    \\pub const App = @import("App.zig");
    \\pub const Tree = struct { kitty: App, other: ?App = null };
    \\/// The plain kosmos.
    \\pub fn kosmos(params: struct { size: u8 = 1 }) Tree {
    \\    _ = params;
    \\}
    \\
;

const test_app =
    \\//! The test app.
    \\/// How the cursor looks.
    \\shape: enum { block, beam } = .block,
    \\/// The border, or none.
    \\border: ?kosm.Color = null,
    \\fonts: struct {
    \\    /// Point sizes, in order.
    \\    sizes: []const f32 = &.{},
    \\} = .{},
    \\style: union(enum) {
    \\    /// No style.
    \\    disabled,
    \\    size: u16,
    \\} = .disabled,
    \\pointer: *const u8 = &byte,
    \\const kosm = @import("kosm");
    \\const byte: u8 = 0;
    \\
;

const TestApp = struct {
    shape: enum { block, beam } = .block,
    border: ?kosm.Color = null,
    fonts: struct { sizes: []const f32 = &.{} } = .{},
    style: union(enum) { disabled, size: u16 } = .disabled,
    pointer: *const u8 = &test_byte,
};
const test_byte: u8 = 0;
const TestTree = struct { kitty: TestApp, other: ?TestApp = null };
fn testKosmos(params: struct { size: u8 = 1 }) TestTree {
    _ = params;
    return .{ .kitty = .{} };
}

test "a kosmos is described with its sources' docs and names, each struct once" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "root.zig", .data = test_root });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "App.zig", .data = test_app });
    const root = try tmp.dir.realPathFileAlloc(testing.io, "root.zig", arena);
    var sources: Sources = .{ .arena = arena, .io = testing.io, .modules = &.{.{ .name = "frost", .root = root }} };
    var builder: Builder = .{ .arena = arena, .sources = &sources };

    const described = try builder.kosmos(.{ .name = "frost", .module = "frost", .path = &.{"kosmos"}, .function = @TypeOf(testKosmos) });
    try testing.expectEqualStrings("The plain kosmos.", described.doc.?);
    try testing.expectEqualStrings("frost.kosmos.Params", described.params.?);
    try testing.expectEqualStrings("frost.Tree", described.tree);

    const completion: Completion = .{ .records = builder.records.items, .kosmoi = &.{}, .standalone = "", .theme = "" };
    const tree = completion.find("frost.Tree").?;
    try testing.expectEqual(2, tree.fields.len);
    try testing.expectEqualStrings("frost.App", tree.fields[0].type.?.record);
    try testing.expectEqualStrings("frost.App", tree.fields[1].type.?.optional.record);

    const app = completion.find("frost.App").?;
    try testing.expectEqualStrings("The test app.", app.doc.?);
    // The pointer cannot be set from a script, so it is left out.
    try testing.expectEqual(4, app.fields.len);
    try testing.expectEqualStrings("How the cursor looks.", app.fields[0].doc.?);
    try testing.expectEqualStrings("beam", app.fields[0].type.?.choice[1]);
    try testing.expectEqual(Completion.Type.color, app.fields[1].type.?.optional.*);
    try testing.expectEqualStrings("frost.App.fonts", app.fields[2].type.?.record);
    const style = app.fields[3].type.?.variant;
    try testing.expectEqualStrings("No style.", style[0].doc.?);
    try testing.expectEqual(null, style[0].type);
    try testing.expectEqual(Completion.Type.integer, style[1].type.?);

    const fonts = completion.find("frost.App.fonts").?;
    try testing.expectEqualStrings("Point sizes, in order.", fonts.fields[0].doc.?);
    try testing.expectEqual(Completion.Type.number, fonts.fields[0].type.?.list.*);
}

test "types without sources are named by where they are found, and names stay unique" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sources: Sources = .{ .arena = arena, .io = testing.io, .modules = &.{} };
    var builder: Builder = .{ .arena = arena, .sources = &sources };
    const First = struct { a: u8 = 0 };
    const Second = struct { b: u8 = 0 };
    try testing.expectEqualStrings("x.Tree", try builder.record(First, "x.Tree", null));
    try testing.expectEqualStrings("x.Tree", try builder.record(First, "y.Tree", null));
    try testing.expectEqualStrings("x.Tree_2", try builder.record(Second, "x.Tree", null));
    try testing.expectEqual(null, builder.records.items[0].doc);
}
